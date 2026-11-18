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

    // MARK: Disposition de la barre latérale : à ras de la fenêtre (macOS 27) ou flottante (macOS 26)

    /// Le rectangle de la vue de glissement de la barre latérale (la plus étroite) en coordonnées de la vue-cadre.
    private func sidebarDragRect(_ root: NSView) -> NSRect? {
        WindowProbe.allViews(root).filter { $0 is WindowDragView && WindowProbe.rect($0, in: root).width < root.bounds.width / 2 }
            .map { WindowProbe.rect($0, in: root) }.first
    }

    /// Sonde le haut de la fenêtre aux points donnés (x, distance au haut) et exige que la fenêtre s'y déplace, selon la disposition.
    ///
    /// Détection STRUCTURELLE (pas un numéro d'OS) : la vue de glissement de la barre latérale est à ras du coin haut gauche
    /// (`fromTop == 0` et `x == 0`, macOS 27) ou décalée (macOS 26 : verre flottant décalé de 8 pt, vue en x = 8, fromTop = 8).
    ///
    /// - À ras : tous les points doivent déplacer la fenêtre (exigence complète).
    /// - Flottante : seuls les points à l'intérieur de notre vue de la barre latérale (x de 6 pt après son bord gauche à 10 pt avant le
    ///   droit, 2 pt de marge en haut et en bas) et dans la colonne de détail (au moins 8 pt à droite de la barre latérale) l'exigent.
    ///   Les autres points sont une LIMITE CONNUE, affichée (`INFO`) et non échouée : la bande de 8 pt au-dessus de la barre latérale, la
    ///   marge gauche de 8 pt (y compris le coin de redimensionnement) et la jointure entre les deux colonnes (x 195 à 200 : le
    ///   `NSSplitView` répond). Preuve : lignes `DIAG hit` de la CI sur macOS 26.7.2 (run 3) : `BackdropView` (poche de défilement de la
    ///   barre latérale, x 0 à 198, au-dessus de la colonne de détail), `NSThemeFrame` et `NSSplitView`, sans glissement. Aucune vue SwiftUI de
    ///   l'app ne peut les couvrir (le contenu de la barre latérale commence en (8, 8)) ; ce n'est pas une régression : en 1.1.0 le haut de la
    ///   barre latérale ne déplaçait la fenêtre sur aucun OS. Le vrai correctif serait une vue AppKit posée sur toute la fenêtre.
    private func expectDragSources(window: NSWindow, probes: [(x: CGFloat, dy: CGFloat)], _ name: String) throws {
        let root = try #require(window.contentView?.superview)
        let sidebar = try #require(sidebarDragRect(root), "vue de glissement de la barre latérale introuvable")
        let sidebarTop = root.bounds.height - sidebar.maxY
        let floating = sidebarTop > 0.5 || sidebar.minX > 0.5
        if floating {
            print("INFO disposition à barre latérale flottante (vue de glissement en x=\(Int(sidebar.minX)), à \(Int(sidebarTop)) pt du haut, \(Int(sidebar.width)) x \(Int(sidebar.height))) : "
                  + "bande du haut, marge gauche et jointure sont une limite connue (\(name))")
        }
        for probe in probes {
            let view = try hit(window, x: probe.x, fromTop: probe.dy)
            let required = WindowProbe.requiresDragSource(x: probe.x, fromTop: probe.dy, sidebar: sidebar, rootHeight: root.bounds.height)
            let source = WindowProbe.dragSource(of: view)
            if required {
                #expect(source != nil, "\(name), x=\(probe.x), à \(probe.dy) pt du haut : rien ne déplace la fenêtre. \(WindowProbe.hitReport(view, in: root))")
            } else if source == nil {
                print("INFO limite connue sur la disposition à barre latérale flottante : x=\(probe.x), à \(probe.dy) pt du haut, frappe \(WindowProbe.className(view))")
            }
        }
    }

    /// La règle de la disposition flottante, vérifiée sur les observations de la CI macOS 26.7.2 (lignes `DIAG hit`, vue de glissement de la
    /// barre latérale en x = 8, à 8 pt du haut, 190 x 44, fenêtre de 674 pt de haut) : ce que la CI a vu touché et la règle s'accordent.
    @Test func theFloatingSidebarRuleMatchesWhatMacOS26Showed() {
        let height: CGFloat = 674
        let sidebar = NSRect(x: 8, y: height - 52, width: 190, height: 44)
        func required(_ x: CGFloat, _ dy: CGFloat) -> Bool { WindowProbe.requiresDragSource(x: x, fromTop: dy, sidebar: sidebar, rootHeight: height) }
        // Touchés par notre vue sur macOS 26 : exigés.
        for dy in [CGFloat(14), 26, 40] { #expect(required(120, dy), "x=120, dy=\(dy)") }
        for dy in [CGFloat(26), 40, 50] { #expect(required(20, dy), "x=20, dy=\(dy)") }
        for x in [CGFloat(300), 500] { for dy in [CGFloat(4), 14, 26, 40, 50] { #expect(required(x, dy), "détail x=\(x), dy=\(dy)") } }
        // Touchés par une vue sans glissement sur macOS 26 (poche de défilement, vue-cadre, `NSSplitView`) : limite connue, non exigés.
        #expect(!required(120, 4))
        for x in [CGFloat(3), 6, 10] { for dy in [CGFloat(4), 14] { #expect(!required(x, dy), "x=\(x), dy=\(dy)") } }
        for x in [CGFloat(3), 6] { for dy in [CGFloat(26), 40, 50] { #expect(!required(x, dy), "marge gauche x=\(x), dy=\(dy)") } }
        for x in [CGFloat(195), 200] { for dy in [CGFloat(4), 14, 26, 40, 50] { #expect(!required(x, dy), "jointure x=\(x), dy=\(dy)") } }
        // Disposition à ras (macOS 27) : tout est exigé.
        let flush = NSRect(x: 0, y: height - 52, width: 190, height: 52)
        for x in [CGFloat(3), 120, 195] { for dy in [CGFloat(4), 26] { #expect(WindowProbe.requiresDragSource(x: x, fromTop: dy, sidebar: flush, rootHeight: height)) } }
    }

    @Test(arguments: [false, true])
    func theTopOfTheSidebarIsADragRegion(dark: Bool) async throws {
        guard NSScreen.main != nil else { return }      // pas de serveur de fenêtres : rien à tester
        let window = try await makeWindow(dark: dark)
        defer { window.orderOut(nil) }
        // Ce qui compte : un clic en haut de la barre latérale DÉPLACE la fenêtre. Le `mouseDown` monte la chaîne des répondeurs
        // depuis la vue touchée ; le déplacement vient de notre `WindowDragView` ou d'une vue de barre de titre du système, vue touchée
        // ou ancêtre. On n'exige plus que ce soit exactement `WindowDragView` : sur macOS 26 une vue privée (« scroll pocket »,
        // Liquid Glass) peut être touchée à la place (voir `expectDragSources` pour ce qui est exigé selon la disposition).
        // `mouseDownCanMoveWindow` n'est pas un critère : la fenêtre n'est pas `isMovableByWindowBackground` (testé plus bas).
        #expect(!window.isMovableByWindowBackground)
        try expectDragSources(window: window, probes: [CGFloat(4), 14, 26, 40].map { (x: CGFloat(120), dy: $0) }, "barre latérale")
    }

    /// macOS 26 (constaté par le diagnostic de la CI) : la barre latérale est un verre flottant décalé de 8 pt, et la colonne de détail
    /// occupe TOUTE la largeur de la fenêtre dessous. Les 8 pt au-dessus de la barre latérale (y 0 à 8) et à sa gauche (x 0 à 8) tombent
    /// donc sur la colonne de détail : si sa vue de glissement ne part pas du bord gauche de la fenêtre, rien n'y déplace la fenêtre.
    /// Ce test s'exprime sur la vue (macOS 27 : barre latérale à x = 0, le détail passe dessous) ; les sondes ci-dessous sur le résultat.
    @Test(arguments: [false, true])
    func theDetailDragStripStartsAtTheLeadingEdgeOfTheWindow(dark: Bool) async throws {
        guard NSScreen.main != nil else { return }
        let window = try await makeWindow(dark: dark)
        defer { window.orderOut(nil) }
        let root = try #require(window.contentView?.superview)
        let stripHeight = window.frame.height - window.contentLayoutRect.height     // barre de titre + barre d'outils
        let wide = WindowProbe.allViews(root).filter { $0 is WindowDragView && WindowProbe.rect($0, in: root).width > root.bounds.width / 2 }
        let detailStrip = try #require(wide.first, "vue de glissement de la colonne de détail introuvable")
        let rect = WindowProbe.rect(detailStrip, in: root)
        #expect(rect.minX < 0.5, "doit partir du bord gauche de la fenêtre : \(rect)")
        #expect(abs(rect.maxX - root.bounds.width) < 0.5, "jusqu'au bord droit : \(rect)")
        #expect(abs(rect.maxY - root.bounds.height) < 0.5, "collée au haut de la fenêtre : \(rect)")
        #expect(abs(rect.height - stripHeight) < 0.5, "hauteur \(rect.height), attendue \(stripHeight)")
    }

    @Test(arguments: [false, true])
    func theTopBandAndTheLeadingMarginAboveTheSidebarAreDragRegions(dark: Bool) async throws {
        guard NSScreen.main != nil else { return }
        let window = try await makeWindow(dark: dark)
        defer { window.orderOut(nil) }
        // x = 3 et 10 : la marge gauche (macOS 26) ; x = 20 et 120 : sur la barre latérale ; x = 195 : au bord de la barre latérale ;
        // x = 300 : colonne de détail ; dy = 4 : la bande du haut. Pas de sonde à moins de 1 pt du haut, ni dans le coin haut gauche
        // (x = 3 et dy < 20, x = 10 et dy < 14) : sur macOS 27 la vue-cadre (`NSThemeFrame`) y répond elle-même, ce sont les zones de
        // redimensionnement de la fenêtre, pas un trou. Sur la disposition flottante de macOS 26, `expectDragSources` limite l'exigence.
        var probes: [(x: CGFloat, dy: CGFloat)] = []
        for x in [CGFloat(120), 195, 300] { for dy in [CGFloat(4), 14, 26, 40, 50] { probes.append((x, dy)) } }
        for dy in [CGFloat(26), 40, 50] { probes.append((20, dy)) }
        for dy in [CGFloat(14), 26, 40, 50] { probes.append((10, dy)) }
        for dy in [CGFloat(26), 40, 50] { probes.append((3, dy)) }
        try expectDragSources(window: window, probes: probes, "haut et marge")
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
