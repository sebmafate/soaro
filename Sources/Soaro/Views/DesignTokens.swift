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

    /// Rapport de contraste d'une couleur d'opacité `alpha`, composée sur `background`.
    static func contrastRatio(_ foreground: RGB, alpha: Double, on background: RGB) -> Double {
        let composited = RGB(
            red: foreground.red * alpha + background.red * (1 - alpha),
            green: foreground.green * alpha + background.green * (1 - alpha),
            blue: foreground.blue * alpha + background.blue * (1 - alpha))
        return contrastRatio(composited, on: background)
    }
}

// MARK: - Texte de soutien dans une vue

/// Applique le jeton « texte de soutien » : couleur selon le thème (clair / sombre) et « Augmenter le contraste ».
private struct SupportingTextStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.foregroundStyle(DesignTokens.supportingTextColor(dark: scheme == .dark, contrastIncreased: contrast == .increased))
    }
}

extension View {
    /// Texte de soutien (tailles, résumés, pieds de page) : jamais `.secondary` ni `.tertiary` (DESIGN.md partie 2).
    func supportingText() -> some View { modifier(SupportingTextStyle()) }
}
