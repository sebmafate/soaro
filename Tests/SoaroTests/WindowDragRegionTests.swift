import AppKit
import SwiftUI
import Testing
@testable import Soaro

/// EXP1 : la bande du haut de la fenêtre (barre de titre et barre d'outils) doit déplacer la fenêtre sur les deux colonnes.
///
/// Cause constatée (voir PLAN.md, EXP1) : dans la bande du haut de la barre latérale, le clic tombe sur la vue SwiftUI de la
/// colonne, dont la chaîne de répondeurs passe par le contrôleur puis la fenêtre sans jamais atteindre une vue qui déplace la
/// fenêtre. Dans la colonne de détail, c'est la barre de titre système qui reçoit le clic, avec ou sans l'expérience.
/// Ce qu'on ne peut pas tester : la sensation réelle du glissement (les événements de la souris matérielle ne se simulent pas).
@MainActor @Suite(.serialized) struct WindowDragRegionTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: Double-clic : la préférence du système

    @Test func defaultDoubleClickZooms() {
        #expect(TitleBarDoubleClick.action(actionPreference: nil, legacyMiniaturize: nil) == .zoom)
        #expect(TitleBarDoubleClick.action(actionPreference: "Maximize", legacyMiniaturize: nil) == .zoom)
    }

    @Test func minimizePreferenceMiniaturizes() {
        #expect(TitleBarDoubleClick.action(actionPreference: "Minimize", legacyMiniaturize: nil) == .miniaturize)
        #expect(TitleBarDoubleClick.action(actionPreference: nil, legacyMiniaturize: true) == .miniaturize)
    }

    @Test func nonePreferenceDoesNothing() {
        #expect(TitleBarDoubleClick.action(actionPreference: "None", legacyMiniaturize: nil) == .nothing)
    }

    @Test func theNewPreferenceWinsOverTheLegacyOne() {
        #expect(TitleBarDoubleClick.action(actionPreference: "Maximize", legacyMiniaturize: true) == .zoom)
    }

    @Test func anUnknownValueFallsBackToZoom() {
        #expect(TitleBarDoubleClick.action(actionPreference: "Something", legacyMiniaturize: nil) == .zoom)
    }

    // MARK: La vue de glissement

    @Test func theDragViewCanMoveTheWindowAndAcceptsTheFirstClick() {
        let view = WindowDragView()
        #expect(view.mouseDownCanMoveWindow)
        #expect(view.acceptsFirstMouse(for: nil))
    }

    // MARK: Dans la vraie fenêtre (hors écran, rien n'est montré à l'utilisateur)

    /// Même réglage que `MainWindowController.show`, fenêtre placée très loin hors de l'écran.
    private func makeWindow(dark: Bool) async throws -> NSWindow {
        let state = AppState(history: HistoryStore(path: ":memory:"))
        let host = NSHostingController(rootView: MainWindowView(initialSection: .tab(.overview)).environmentObject(state))
        host.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: host)
        MainWindowController.configure(window)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderFrontRegardless()
        try await Task.sleep(for: .seconds(1.5))
        return window
    }

    private func hit(_ window: NSWindow, x: CGFloat, fromTop dy: CGFloat) throws -> NSView {
        let frame = try #require(window.contentView?.superview)
        return try #require(frame.hitTest(NSPoint(x: x, y: frame.bounds.height - dy)))
    }

    private func isInTitlebar(_ view: NSView) -> Bool {
        var v: NSView? = view
        while let current = v {
            if String(describing: type(of: current)).contains("Titlebar") { return true }
            v = current.superview
        }
        return false
    }

    @Test(arguments: [false, true])
    func theTopOfTheSidebarIsADragRegion(dark: Bool) async throws {
        guard NSScreen.main != nil else { return }      // pas de serveur de fenêtres : rien à tester
        let window = try await makeWindow(dark: dark)
        defer { window.orderOut(nil) }
        for dy in [CGFloat(4), 14, 26, 40] {
            let view = try hit(window, x: 120, fromTop: dy)
            #expect(view is WindowDragView, "barre latérale, à \(dy) pt du haut : \(type(of: view))")
        }
    }

    @Test(arguments: [false, true])
    func theTopOfTheDetailColumnMovesTheWindow(dark: Bool) async throws {
        guard NSScreen.main != nil else { return }
        let window = try await makeWindow(dark: dark)
        defer { window.orderOut(nil) }
        for x in [CGFloat(300), 500, 700] {
            for dy in [CGFloat(4), 14, 26, 40] {
                let view = try hit(window, x: x, fromTop: dy)
                // Soit notre vue, soit la barre de titre système : toutes deux déplacent la fenêtre.
                #expect(view is WindowDragView || isInTitlebar(view), "détail x=\(x), à \(dy) pt du haut : \(type(of: view))")
                #expect(view.mouseDownCanMoveWindow)
            }
        }
    }

    @Test(arguments: [false, true])
    func theTrafficLightsStillReceiveTheirClicks(dark: Bool) async throws {
        guard NSScreen.main != nil else { return }
        let window = try await makeWindow(dark: dark)
        defer { window.orderOut(nil) }
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            let button = try #require(window.standardWindowButton(kind))
            let frame = try #require(window.contentView?.superview)
            let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: frame)
            let view = try #require(frame.hitTest(center))
            #expect(view === button || view.isDescendant(of: button) || button.isDescendant(of: view) && !(view is WindowDragView),
                    "\(kind) : \(type(of: view))")
            #expect(!(view is WindowDragView))
        }
    }

    @Test(arguments: [false, true])
    func theContentBelowTheStripIsNotADragRegion(dark: Bool) async throws {
        guard NSScreen.main != nil else { return }
        let window = try await makeWindow(dark: dark)
        defer { window.orderOut(nil) }
        // 70 pt : la première ligne de la barre latérale (Overview) doit rester une ligne, pas une zone de glissement.
        for x in [CGFloat(120), 500] {
            for dy in [CGFloat(70), 200] {
                let view = try hit(window, x: x, fromTop: dy)
                #expect(!(view is WindowDragView), "x=\(x), à \(dy) pt du haut : \(type(of: view))")
            }
        }
    }

    // MARK: Le code

    @Test func theWholeWindowIsNotMovableByItsBackground() throws {
        // Des gestes propres à l'app (curseur de seuil, lignes de sélection, graphiques) se feraient voler par un glissement global.
        for path in ["Sources/Soaro/Views/MainWindow.swift", "Sources/Soaro/Views/WindowDragRegion.swift"] {
            let text = try source(path)
            #expect(!text.contains("isMovableByWindowBackground = true"), "\(path)")
        }
    }

    @Test func bothColumnsPlaceTheDragRegionAndTheWindowIsConfiguredInOnePlace() throws {
        let text = try source("Sources/Soaro/Views/MainWindow.swift")
        #expect(text.components(separatedBy: ".windowDragStrip()").count - 1 == 2, "une fois pour la barre latérale, une fois pour le détail")
        #expect(text.contains("MainWindowController.configure(window)") || text.contains("Self.configure(window)"))
        #expect(text.contains("window.isOpaque = false"))
    }
}
