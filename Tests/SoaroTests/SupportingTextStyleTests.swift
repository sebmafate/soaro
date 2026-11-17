import Foundation
import SwiftUI
import Testing
@testable import Soaro

/// Jeton « texte de soutien » sous forme de `ShapeStyle` (SL4 T1) : une seule source pour la couleur,
/// utilisable partout où un style est attendu (y compris dans un ternaire).
@Suite struct SupportingTextStyleTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
    }

    private func components(_ environment: EnvironmentValues) -> (red: Double, green: Double, blue: Double, opacity: Double) {
        let resolved = SupportingTextShapeStyle.color(in: environment).resolve(in: environment)
        // Les composantes `red`, `green`, `blue` sont celles de sRGB (avec courbe), pas les composantes linéaires.
        return (Double(resolved.red), Double(resolved.green), Double(resolved.blue), Double(resolved.opacity))
    }

    /// Corps d'un type de premier niveau : de sa déclaration jusqu'à l'accolade fermante en colonne 0.
    private func typeBody(_ declaration: String, in path: String) throws -> String {
        let text = try source(path)
        let start = try #require(text.range(of: declaration), "\(declaration) introuvable dans \(path)")
        let end = text.range(of: "\n}\n", range: start.upperBound..<text.endIndex)?.upperBound ?? text.endIndex
        return String(text[start.lowerBound..<end])
    }

    @Test func anInstanceOfTheShapeStyleResolvesToTheTokenInLightAndDark() {
        // On passe par `resolve(in:)` d'une instance, c'est ce que SwiftUI appelle : un `resolve` qui renverrait
        // une autre couleur (par exemple `Color.gray`) doit faire échouer ce test.
        for scheme in [ColorScheme.light, .dark] {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            let resolved: Color = SupportingTextShapeStyle().resolve(in: environment)
            let expected = DesignTokens.supportingTextColor(dark: scheme == .dark, contrastIncreased: false)
            let a = resolved.resolve(in: environment)
            let b = expected.resolve(in: environment)
            #expect(a.red == b.red && a.green == b.green && a.blue == b.blue && a.opacity == b.opacity,
                    "\(scheme) : l'instance du style doit se résoudre en la couleur du jeton")
            let base: Float = scheme == .dark ? 1 : 0
            #expect(abs(a.red - base) < 0.002 && abs(a.green - base) < 0.002 && abs(a.blue - base) < 0.002)
            #expect(abs(a.opacity - 0.56) < 0.002)
        }
    }

    @Test func lightResolvesToBlackAtFiftySixPercent() {
        let c = components(EnvironmentValues())
        #expect(abs(c.red) < 0.002 && abs(c.green) < 0.002 && abs(c.blue) < 0.002)
        #expect(abs(c.opacity - 0.56) < 0.002)
    }

    @Test func darkResolvesToWhiteAtFiftySixPercent() {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        let c = components(environment)
        #expect(abs(c.red - 1) < 0.002 && abs(c.green - 1) < 0.002 && abs(c.blue - 1) < 0.002)
        #expect(abs(c.opacity - 0.56) < 0.002)
    }

    @Test func theShapeStyleResolvesToTheSameColourAsTheTokenFunction() {
        var environment = EnvironmentValues()
        for scheme in [ColorScheme.light, .dark] {
            environment.colorScheme = scheme
            let expected = DesignTokens.supportingTextColor(dark: scheme == .dark, contrastIncreased: false)
            let a = SupportingTextShapeStyle.color(in: environment).resolve(in: environment)
            let b = expected.resolve(in: environment)
            #expect(a.red == b.red && a.green == b.green && a.blue == b.blue && a.opacity == b.opacity)
        }
    }

    @Test func theShapeStyleIsUsableInATernaryAndThroughTheViewModifier() {
        // Compile seulement : un ternaire de `AnyShapeStyle` et le modificateur existant.
        let highlighted = Bool.random()
        _ = Text("x").foregroundStyle(highlighted ? AnyShapeStyle(.primary) : AnyShapeStyle(.supportingText))
        _ = Text("x").supportingText()
    }

    /// Modificateurs qui changeraient la couleur du jeton après coup (le jeton est une couleur plate, à opacité absolue).
    private static let colourAlteringModifiers = [".opacity(", ".brightness(", ".saturation(", ".contrast(", ".colorMultiply(",
                                                   ".blendMode(", ".foregroundColor(", ".tint(", ".luminanceToAlpha(", ".grayscale("]

    @Test func theShapeStyleReadsTheContrastSettingAndTheTokenFunctionOnly() throws {
        let body = try typeBody("struct SupportingTextShapeStyle", in: "Sources/Soaro/Views/DesignTokens.swift")
        #expect(body.contains("colorSchemeContrast"))
        #expect(body.contains("supportingTextColor("))
        #expect(!body.contains("Color.primary"), "jamais `Color.primary.opacity` : l'opacité doit être absolue")
        for modifier in Self.colourAlteringModifiers {
            #expect(!body.contains(modifier), "le style du jeton ne doit pas altérer la couleur : `\(modifier)` interdit dans SupportingTextShapeStyle (la couleur vient de DesignTokens.supportingTextColor)")
        }
    }

    @Test func theViewModifierAppliesTheShapeStyleAndNothingElse() throws {
        let text = try source("Sources/Soaro/Views/DesignTokens.swift")
        let start = try #require(text.range(of: "func supportingText()"))
        let line = String(text[start.lowerBound...].prefix { $0 != "\n" })
        #expect(line.contains("foregroundStyle(.supportingText)") || line.contains("foregroundStyle(SupportingTextShapeStyle())"),
                "supportingText() applique le style du jeton")
        for modifier in Self.colourAlteringModifiers {
            #expect(!line.contains(modifier), "supportingText() ne doit pas altérer la couleur : `\(modifier)` interdit (un seul chemin vers la couleur)")
        }
        #expect(line.hasSuffix("{ foregroundStyle(.supportingText) }") || line.hasSuffix("{ foregroundStyle(SupportingTextShapeStyle()) }"),
                "supportingText() est exactement le style du jeton, sans modificateur ajouté : \(line)")
    }
}
