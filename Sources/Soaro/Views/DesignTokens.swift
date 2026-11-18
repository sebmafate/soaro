import SwiftUI

/// Jetons de couleur de l'accessibilité (DESIGN.md partie 2) et calcul de contraste.
///
/// Les valeurs sont des constantes testées (`ContrastTests`) : on ne mesure pas les pixels.
/// Rien dans l'interface existante n'utilise encore le texte secondaire (SL4).
enum DesignTokens {
    /// Couleur sRGB, composantes de 0 à 1.
    struct RGB: Equatable {
        var red: Double
        var green: Double
        var blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = red; self.green = green; self.blue = blue
        }

        /// `0xRRGGBB`.
        init(hex: UInt32) {
            self.init(red: Double((hex >> 16) & 0xFF) / 255,
                      green: Double((hex >> 8) & 0xFF) / 255,
                      blue: Double(hex & 0xFF) / 255)
        }

        static let black = RGB(red: 0, green: 0, blue: 0)
        static let white = RGB(red: 1, green: 1, blue: 1)

        var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
    }

    // MARK: Fonds de référence (ceux sur lesquels DESIGN.md calcule les rapports)

    static let lightReferenceBackground = RGB.white
    static let darkReferenceBackground = RGB(hex: 0x1E1E1E)

    // MARK: Bouton destructeur (danger-fill)

    /// Fond du bouton destructeur : texte blanc dessus à 4,98 : 1.
    static let dangerFill = RGB(hex: 0xD32F2F)
    /// Même fond avec « Augmenter le contraste » : 6,57 : 1 avec du texte blanc.
    static let dangerFillIncreasedContrast = RGB(hex: 0xB71C1C)

    static func dangerFill(contrastIncreased: Bool) -> RGB {
        contrastIncreased ? dangerFillIncreasedContrast : dangerFill
    }

    // MARK: Texte secondaire (text-supporting)

    /// Noir pur en clair, blanc pur en sombre, à une opacité ABSOLUE. `Color.primary.opacity(x)`
    /// part de `labelColor` (≈ 85 % d'opacité) et donne ≈ 0,48 effectif : trop clair.
    static func supportingTextBase(dark: Bool) -> RGB { dark ? .white : .black }

    static func supportingTextAlpha(contrastIncreased: Bool) -> Double {
        contrastIncreased ? 0.70 : 0.56
    }

    static func supportingTextColor(dark: Bool, contrastIncreased: Bool) -> Color {
        let base = supportingTextBase(dark: dark)
        return Color(.sRGB, red: base.red, green: base.green, blue: base.blue,
                     opacity: supportingTextAlpha(contrastIncreased: contrastIncreased))
    }

    // MARK: Contraste (WCAG 2.x)

    /// Luminance relative d'une couleur sRGB (WCAG 2.x).
    static func relativeLuminance(_ color: RGB) -> Double {
        func linear(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    /// Rapport de contraste entre deux couleurs opaques (de 1 à 21).
    static func contrastRatio(_ a: RGB, on b: RGB) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Couleur d'opacité `alpha` composée sur un fond opaque.
    static func composited(_ foreground: RGB, alpha: Double, on background: RGB) -> RGB {
        RGB(red: foreground.red * alpha + background.red * (1 - alpha),
            green: foreground.green * alpha + background.green * (1 - alpha),
            blue: foreground.blue * alpha + background.blue * (1 - alpha))
    }

    /// Rapport de contraste d'une couleur d'opacité `alpha`, composée sur `background`.
    static func contrastRatio(_ foreground: RGB, alpha: Double, on background: RGB) -> Double {
        contrastRatio(composited(foreground, alpha: alpha, on: background), on: background)
    }

    // MARK: Barre mémoire segmentée (SL26)

    /// Piste de la barre : noir (clair) ou blanc (sombre) à une opacité absolue basse, comme le texte de soutien.
    /// Elle est identique avec « Augmenter le contraste » : ce sont les segments qui se renforcent, pas la piste.
    static func memoryTrackBase(dark: Bool) -> RGB { dark ? .white : .black }

    static func memoryTrackAlpha(dark: Bool) -> Double { dark ? 0.14 : 0.10 }

    /// Piste composée sur le fond de référence : la couleur contre laquelle les segments doivent faire 3 : 1.
    static func memoryTrackOnReference(dark: Bool) -> RGB {
        composited(memoryTrackBase(dark: dark), alpha: memoryTrackAlpha(dark: dark),
                   on: dark ? darkReferenceBackground : lightReferenceBackground)
    }

    /// Opacité du remplissage léger du cache (le contour, lui, est la couleur pleine du jeton).
    static let memoryCacheFillAlpha = 0.28

    /// Couleur d'un segment de la barre mémoire. Tous au moins 3 : 1 contre la piste en clair et en sombre
    /// (éléments graphiques, WCAG 1.4.11) ; avec « Augmenter le contraste » : plus foncés en clair, plus clairs en sombre.
    /// Les teintes (bleu, violet, sarcelle, gris) évitent le vert, l'orange et le rouge de la pression.
    static func memorySegment(_ kind: MemorySegmentKind, dark: Bool, contrastIncreased: Bool) -> RGB {
        let hex: UInt32
        switch (dark, contrastIncreased) {
        case (false, false):
            switch kind {
            case .app: hex = 0x1F6FEB
            case .wired: hex = 0x7B4FC9
            case .compressed: hex = 0x0E7C8C
            case .cached: hex = 0x6B6B70
            case .unattributed: hex = 0x7C7C82
            }
        case (false, true):
            switch kind {
            case .app: hex = 0x0B4FB8
            case .wired: hex = 0x5B34A8
            case .compressed: hex = 0x0A6573
            case .cached: hex = 0x4A4A50
            case .unattributed: hex = 0x5E5E64
            }
        case (true, false):
            switch kind {
            case .app: hex = 0x5AA2FF
            case .wired: hex = 0xA98BFF
            case .compressed: hex = 0x3CC4D8
            case .cached: hex = 0x9A9AA2
            case .unattributed: hex = 0x8A8A92
            }
        case (true, true):
            switch kind {
            case .app: hex = 0x7DB6FF
            case .wired: hex = 0xC0A8FF
            case .compressed: hex = 0x66D6E6
            case .cached: hex = 0xBDBDC4
            case .unattributed: hex = 0xA8A8AF
            }
        }
        return RGB(hex: hex)
    }
}

// MARK: - Texte de soutien dans une vue

/// Le jeton « texte de soutien » sous forme de `ShapeStyle` : la couleur se résout depuis l'environnement
/// (thème clair / sombre et « Augmenter le contraste »). Utilisable partout où un style est attendu,
/// y compris dans un ternaire : `highlighted ? AnyShapeStyle(.primary) : AnyShapeStyle(.supportingText)`.
struct SupportingTextShapeStyle: ShapeStyle {
    /// Couleur du jeton pour un environnement donné (testable sans rendu).
    static func color(in environment: EnvironmentValues) -> Color {
        DesignTokens.supportingTextColor(dark: environment.colorScheme == .dark,
                                         contrastIncreased: environment.colorSchemeContrast == .increased)
    }

    /// Type de retour explicite (`Color`) : un test résout une instance du style et compare au jeton.
    func resolve(in environment: EnvironmentValues) -> Color { Self.color(in: environment) }
}

extension ShapeStyle where Self == SupportingTextShapeStyle {
    /// Texte de soutien : `.foregroundStyle(.supportingText)`. Jamais `.secondary` ni `.tertiary` pour du texte.
    static var supportingText: SupportingTextShapeStyle { SupportingTextShapeStyle() }
}

extension View {
    /// Texte de soutien (tailles, résumés, pieds de page) : jamais `.secondary` ni `.tertiary` (DESIGN.md partie 2).
    /// Même résultat que `.foregroundStyle(.supportingText)`, qui est la forme à écrire dans le nouveau code. Le modificateur
    /// reste pour l'écran des simulateurs (SL8) et pour les `Label` d'`EmptyHint`, qui ne changent pas d'appel ; aucun
    /// modificateur de couleur n'y est ajouté (`SupportingTextStyleTests`).
    func supportingText() -> some View { foregroundStyle(.supportingText) }
}
