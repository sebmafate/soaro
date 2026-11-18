import AppKit
import SwiftUI
import Testing
@testable import Soaro

/// Expérience 1.2.0 : fond opaque pour la zone principale de la fenêtre, barre latérale translucide, cartes à plat.
/// Le rendu (flou réel derrière la fenêtre, jonction avec la barre d'outils) ne se teste pas hors écran : l'auteur le juge à l'œil
/// sur l'application. Ces tests couvrent ce qui se calcule : l'interrupteur, la couleur choisie, son contraste, et que le panneau
/// de la barre de menus ne change pas.
@Suite struct WindowSurfaceTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
    }

    /// Couleur système résolue dans une apparence, en sRGB opaque.
    private func resolved(_ color: NSColor, dark: Bool) throws -> (rgb: DesignTokens.RGB, alpha: Double) {
        var result: NSColor?
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        appearance.performAsCurrentDrawingAppearance { result = color.usingColorSpace(.sRGB) }
        let c = try #require(result)
        return (DesignTokens.RGB(red: Double(c.redComponent), green: Double(c.greenComponent), blue: Double(c.blueComponent)), Double(c.alphaComponent))
    }

    // MARK: L'interrupteur

    @Test func cardsAreFlatWhenTheMainAreaIsOpaque() {
        #expect(WindowSurface.cardsAreGlass(opaqueMainArea: true) == false)
    }

    @Test func cardsAreGlassWhenTheMainAreaIsTranslucent() {
        // Retour à l'état 1.1.0 : verre sur fond flouté.
        #expect(WindowSurface.cardsAreGlass(opaqueMainArea: false) == true)
    }

    @Test func theWindowReadsTheSwitchThroughOnePlace() {
        #expect(WindowSurface.cardsAreGlass == WindowSurface.cardsAreGlass(opaqueMainArea: WindowSurface.opaqueMainArea))
    }

    // MARK: La couleur de la zone principale

    @Test(arguments: [false, true])
    func mainAreaColourIsFullyOpaque(dark: Bool) throws {
        let c = try resolved(WindowSurface.mainAreaNSColor, dark: dark)
        #expect(c.alpha == 1)
    }

    @Test func mainAreaColourIsTheDesignReferenceBackgroundInLightAndDark() throws {
        // DESIGN.md calcule les rapports de contraste sur blanc et #1E1E1E : la zone principale est exactement ce fond.
        let light = try resolved(WindowSurface.mainAreaNSColor, dark: false).rgb
        let dark = try resolved(WindowSurface.mainAreaNSColor, dark: true).rgb
        for (got, want) in [(light, DesignTokens.lightReferenceBackground), (dark, DesignTokens.darkReferenceBackground)] {
            #expect(abs(got.red - want.red) < 0.02 && abs(got.green - want.green) < 0.02 && abs(got.blue - want.blue) < 0.02,
                    "attendu \(want), obtenu \(got)")
        }
    }

    @Test(arguments: [false, true])
    func supportingTextKeepsAAOnTheMainAreaColour(increased: Bool) throws {
        let alpha = DesignTokens.supportingTextAlpha(contrastIncreased: increased)
        for dark in [false, true] {
            let background = try resolved(WindowSurface.mainAreaNSColor, dark: dark).rgb
            let ratio = DesignTokens.contrastRatio(DesignTokens.supportingTextBase(dark: dark), alpha: alpha, on: background)
            #expect(ratio >= 4.5, "\(dark ? "sombre" : "clair"), contraste accru \(increased) : \(ratio)")
        }
    }

    // MARK: Le fond opaque s'arrête sous la barre de titre

    @Test func theOpaqueFillStopsAtTheTitleBar() throws {
        // Sous la barre de titre et la barre d'outils, on voit le fond translucide de la fenêtre, cohérent avec la barre latérale :
        // le fond opaque ne couvre que le contenu. Le texte reste lisible grâce à `TitleBarBlur` (flou « dans la fenêtre »).
        let text = try source("Sources/Soaro/Views/GlassStyle.swift")
        let start = try #require(text.range(of: "func windowMainAreaBackground()"))
        let end = try #require(text.range(of: "/// Le message passager", range: start.upperBound..<text.endIndex))
        let body = text[start.lowerBound..<end.lowerBound]
        #expect(!body.contains("ignoresSafeArea"), "le fond de la zone principale ne doit pas monter sous la barre de titre")
        #expect(body.contains("WindowSurface.mainAreaColor"))
    }

    @Test func theHeaderBlurStillCoversTheTitleStripOfTheDetailColumn() throws {
        let text = try source("Sources/Soaro/Views/MainWindow.swift")
        #expect(text.contains(".overlay(alignment: .top) { TitleBarBlur() }"))
        #expect(text.contains("view.material = .headerView"))
        #expect(text.contains("view.blendingMode = .withinWindow"))
    }

    // MARK: Le panneau ne change pas

    @Test func theMenuBarPanelKeepsFlatCardsByDefault() {
        #expect(EnvironmentValues().glassSurface == false)
    }

    @Test func thePanelAndTheSharedCardsDoNotKnowTheExperiment() throws {
        for path in ["Sources/Soaro/Views/PopoverView.swift", "Sources/Soaro/Views/Components.swift", "Sources/Soaro/Views/CleanupTab.swift"] {
            let text = try source(path)
            #expect(!text.contains("WindowSurface"), "\(path) ne doit pas lire l'interrupteur de la fenêtre")
            #expect(!text.contains("windowMainArea"), "\(path) ne doit pas poser le fond de la zone principale")
        }
    }

    @Test func theCardBackgroundModifierIsUnchangedByTheExperiment() throws {
        // L'expérience agit sur la valeur de `glassSurface` posée par la fenêtre, pas sur le modificateur des cartes.
        let text = try source("Sources/Soaro/Views/GlassStyle.swift")
        let start = try #require(text.range(of: "struct CardBackground"))
        let end = try #require(text.range(of: "extension View {", range: start.upperBound..<text.endIndex))
        #expect(!text[start.lowerBound..<end.lowerBound].contains("WindowSurface"))
    }

    // MARK: La fenêtre

    @Test func theWindowSetsTheSurfacesFromTheSwitchOnly() throws {
        let text = try source("Sources/Soaro/Views/MainWindow.swift")
        #expect(text.contains(".environment(\\.glassSurface, WindowSurface.cardsAreGlass)"))
        #expect(!text.contains(".environment(\\.glassSurface, true)"))
        #expect(text.contains(".windowMainAreaBackground()"))
        // Le fond flouté de toute la fenêtre reste : c'est lui qu'on voit à travers la barre latérale.
        #expect(text.contains("WindowGlassBackground()"))
        #expect(text.contains("window.isOpaque = false"))
        // La barre latérale ne reçoit pas le fond opaque.
        let sidebar = try #require(text.range(of: "NavigationSplitView {"))
        let detail = try #require(text.range(of: "} detail: {", range: sidebar.upperBound..<text.endIndex))
        #expect(!text[sidebar.lowerBound..<detail.lowerBound].contains("windowMainAreaBackground"))
    }

    @Test func theMacOS26GlassGuardIsKept() throws {
        let text = try source("Sources/Soaro/Views/GlassStyle.swift")
        #expect(text.contains("#if compiler(>=6.2)"))
        #expect(text.contains("if #available(macOS 26.0, *)"))
        #expect(text.contains("content.glassEffect("))
    }
}
