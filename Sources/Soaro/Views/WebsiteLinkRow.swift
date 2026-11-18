import AppKit
import SwiftUI

/// Réglages > À propos (SL18) : le logo de l'app et un lien vers le site. `Link` ouvre le navigateur : l'app n'envoie rien.
/// Une seule ligne pour VoiceOver (« soaro.app, lien, Website ») ; le logo est décoratif.
struct WebsiteLinkRow: View {
    /// Le logo mesure environ 36 à 40 pt ; la ligne entière est cliquable et jamais plus basse que lui (au moins 24 pt exigés).
    static let logoSize: CGFloat = 38
    static let minimumHeight: CGFloat = 38

    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 10) {
                logo
                    .frame(width: Self.logoSize, height: Self.logoSize)
                    .accessibilityHidden(true)
                Text(verbatim: SupportLink.websiteText)
                Spacer(minLength: 0)
            }
            .frame(minHeight: Self.minimumHeight)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(verbatim: SupportLink.websiteText))
        .accessibilityHint(Text("Website"))
    }

    /// L'icône de l'app (plusieurs tailles dans le .icns : nette en clair comme en sombre) ; le glyphe seul si elle manque.
    @ViewBuilder private var logo: some View {
        if let icon = NSApp?.applicationIconImage {
            Image(nsImage: icon).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            BrandGlyph()
                .stroke(style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .frame(width: 26, height: 20)
        }
    }
}
