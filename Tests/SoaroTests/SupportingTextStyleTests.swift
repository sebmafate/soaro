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

    @Test func theShapeStyleReadsTheContrastSettingAndTheTokenFunctionOnly() throws {
        let text = try source("Sources/Soaro/Views/DesignTokens.swift")
        let start = try #require(text.range(of: "struct SupportingTextShapeStyle"))
        let body = String(text[start.lowerBound...].prefix(900))
        #expect(body.contains("colorSchemeContrast"))
        #expect(body.contains("supportingTextColor("))
        #expect(!body.contains("Color.primary"), "jamais `Color.primary.opacity` : l'opacité doit être absolue")
        #expect(!body.contains(".opacity("))
    }

    @Test func theViewModifierAppliesTheShapeStyle() throws {
        let text = try source("Sources/Soaro/Views/DesignTokens.swift")
        let start = try #require(text.range(of: "func supportingText()"))
        let body = String(text[start.lowerBound...].prefix(200))
        #expect(body.contains("foregroundStyle(.supportingText)") || body.contains("foregroundStyle(SupportingTextShapeStyle())"))
    }
}
