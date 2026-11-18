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
        let root = try #require(window.contentView?.superview)
        // Ce qui compte : un clic en haut de la barre latérale DÉPLACE la fenêtre. Le `mouseDown` monte la chaîne des répondeurs
        // depuis la vue touchée ; le déplacement vient de notre `WindowDragView` ou d'une vue de barre de titre du système, vue touchée
        // ou ancêtre. On n'exige plus que ce soit exactement `WindowDragView` : sur macOS 26 une vue privée (« scroll pocket »,
        // Liquid Glass) peut être touchée à la place, et c'est un problème seulement si le déplacement n'y arrive plus.
        // `mouseDownCanMoveWindow` n'est pas un critère : la fenêtre n'est pas `isMovableByWindowBackground` (testé plus bas).
        #expect(!window.isMovableByWindowBackground)
        for dy in [CGFloat(4), 14, 26, 40] {
            let view = try hit(window, x: 120, fromTop: dy)
            let source = WindowProbe.dragSource(of: view)
            #expect(source != nil, "barre latérale, à \(dy) pt du haut : rien ne déplace la fenêtre. \(WindowProbe.hitReport(view, in: root))")
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

    // MARK: Le flou de l'en-tête de la colonne de détail

    private func allViews(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(allViews) }

    /// Le flou « dans la fenêtre » de `TitleBarBlur` (matériau d'en-tête).
    private func headerBlur(_ window: NSWindow) throws -> NSVisualEffectView {
        let root = try #require(window.contentView?.superview)
        let blurs = allViews(root).compactMap { $0 as? NSVisualEffectView }.filter { $0.material == .headerView && $0.blendingMode == .withinWindow }
        return try #require(blurs.first, "TitleBarBlur absent")
    }

    @Test(arguments: [false, true])
    func theHeaderBlurCoversTheWholeTitleStripOfTheDetailColumn(dark: Bool) async throws {
        guard NSScreen.main != nil else { return }
        let window = try await makeWindow(dark: dark)
        defer { window.orderOut(nil) }
        let root = try #require(window.contentView?.superview)
        let blur = try headerBlur(window)
        let rect = blur.convert(blur.bounds, to: root)
        let stripHeight = window.frame.height - window.contentLayoutRect.height     // barre de titre + barre d'outils
        #expect(stripHeight > 0)
        // En haut, sur toute la hauteur de la bande, sans trou, jusqu'au bord droit (côté barre de défilement).
        #expect(abs(rect.maxY - root.bounds.height) < 0.5, "colle au haut de la fenêtre : \(rect)")
        #expect(abs(rect.height - stripHeight) < 0.5, "hauteur \(rect.height), attendue \(stripHeight)")
        #expect(abs(rect.maxX - root.bounds.width) < 0.5, "bord droit : \(rect)")
        // À gauche, elle commence au bord de la barre latérale : elle ne passe pas dessous (le verre de la barre latérale
        // y montrerait une bande d'une autre teinte) et ne laisse pas de trou à côté d'elle.
        let sidebar = try #require(allViews(root).first { String(describing: type(of: $0)).contains("ItemViewWrapper") && $0.frame.width < root.bounds.width / 2 })
        let sidebarEdge = sidebar.convert(sidebar.bounds, to: root).maxX
        #expect(abs(rect.minX - sidebarEdge) < 0.5, "bord gauche \(rect.minX), bord de la barre latérale \(sidebarEdge)")
    }

    @Test(arguments: [false, true])
    func theScrollContentStillExtendsUnderTheTitleStrip(dark: Bool) async throws {
        guard NSScreen.main != nil else { return }
        let window = try await makeWindow(dark: dark)
        defer { window.orderOut(nil) }
        let root = try #require(window.contentView?.superview)
        let scrollViews = allViews(root).compactMap { $0 as? NSScrollView }.filter { $0.frame.width > root.bounds.width / 2 }
        let scroll = try #require(scrollViews.first, "défilement du détail introuvable")
        let rect = scroll.convert(scroll.bounds, to: root)
        // Le contenu défile jusque sous la barre de titre (pas de bande vide ni de coupure franche) ; l'inset garde la première ligne lisible.
        #expect(abs(rect.maxY - root.bounds.height) < 0.5, "le défilement part du haut de la fenêtre : \(rect)")
        #expect(scroll.contentInsets.top > 0)
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
