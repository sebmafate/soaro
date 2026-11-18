import SwiftUI

/// Largeur naturelle du contenu de la bande, remontée à la bande pour qu'elle le rétrécisse s'il est trop large.
private struct StripContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Une fausse barre de menus (SL22) : un rectangle arrondi qui imite le fond de la barre, avec dessus le MÊME dessin que le vrai
/// libellé (`MenuBarRenderer`, SL23 : la même image dynamique, dessinée avec Core Text) : le glyphe d'Soaro d'abord, puis les mesures choisies dans l'ordre choisi.
///
/// Le vrai libellé est une image « modèle » que macOS teinte lui-même ; un aperçu ne peut pas l'utiliser, il dessine donc la vue
/// avec la couleur de base de la bande : blanc sur une bande sombre, noir sur une bande claire (comme le fait
/// `MenuBarRenderer` quand l'image porte ses couleurs). La bande suit le thème de l'app, pas le fond d'écran comme la vraie barre.
/// Trop large pour la bande (six mesures sur une ligne), le contenu est rétréci pour que tout reste visible.
struct MenuBarPreviewStrip: View {
    /// Hauteur de la bande : un peu plus que la barre de menus (24 à 37 pt selon le Mac) pour laisser respirer le libellé de 22 pt.
    static let height: CGFloat = 30
    static let horizontalPadding: CGFloat = 12
    static let cornerRadius: CGFloat = 8

    /// Dit ce qui s'affiche quand rien n'est choisi : seul le glyphe d'Soaro reste dans la vraie barre.
    static var emptyText: String { String(localized: "Nothing selected: only the Soaro icon shows") }

    static func showsEmptyText(items: [MenuBarItem]) -> Bool { items.isEmpty }

    /// Couleur du glyphe et des valeurs : blanc sur bande sombre, noir sur bande claire.
    static func baseColor(dark: Bool) -> Color { dark ? .white : .black }

    /// Fond de la bande, d'un gris de barre de menus : clair ou sombre, sans transparence (le vrai fond dépend du fond d'écran).
    static func stripColor(dark: Bool) -> Color {
        dark ? Color(white: 0.07) : Color(red: 0.89, green: 0.90, blue: 0.92)
    }

    let items: [MenuBarItem]
    let compact: Bool
    var severity: Severity?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var contentWidth: CGFloat = 0

    private var dark: Bool { colorScheme == .dark }

    var body: some View {
        let base = Self.baseColor(dark: dark)
        GeometryReader { proxy in
            let available = proxy.size.width - 2 * Self.horizontalPadding
            let scale = contentWidth > available && available > 0 ? available / contentWidth : 1
            HStack(spacing: 10) {
                // Le MÊME dessin que le vrai libellé (`MenuBarRenderer`, Core Text, pixels entiers), à la couleur de la bande, à l'échelle de l'écran de la fenêtre.
                Image(nsImage: MenuBarRenderer.previewImage(severity: severity, compact: compact, items: items, darkStrip: dark, increasedContrast: contrast == .increased))
                if Self.showsEmptyText(items: items) {
                    Text(Self.emptyText)
                        .font(.caption)
                        .foregroundStyle(base.opacity(contrast == .increased ? 0.9 : 0.7))
                        .lineLimit(1)
                }
            }
            .fixedSize()
            .background(GeometryReader { Color.clear.preference(key: StripContentWidthKey.self, value: $0.size.width) })
            .onPreferenceChange(StripContentWidthKey.self) { contentWidth = $0 }
            .scaleEffect(scale, anchor: .leading)
            .padding(.leading, Self.horizontalPadding)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: Self.cornerRadius).fill(Self.stripColor(dark: dark)))
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(base.opacity(0.14), lineWidth: 0.5))
    }
}

/// L'aperçu des Réglages : la légende « Preview », la bande, et une phrase pour VoiceOver.
struct MenuBarPreview: View {
    let items: [MenuBarItem]
    let compact: Bool
    var severity: Severity?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview")
                .font(.caption).foregroundStyle(.supportingText)
                .accessibilityHidden(true)
            MenuBarPreviewStrip(items: items, compact: compact, severity: severity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.accessibilityLabel(for: items))
        }
    }

    /// « Menu bar preview: CPU, Memory and Battery », dans l'ordre affiché. Le drapeau n'est pas une mesure. Rien d'affiché : l'explication.
    static func accessibilityLabel(for items: [MenuBarItem], locale: Locale = MenuBarTooltip.appLocale) -> String {
        let names = items.compactMap(\.measure?.shortName)
        guard !names.isEmpty else { return MenuBarPreviewStrip.emptyText }
        let formatter = ListFormatter()
        formatter.locale = locale
        let list = formatter.string(from: names) ?? names.joined(separator: ", ")
        return String(localized: "Menu bar preview: \(list)")
    }
}
