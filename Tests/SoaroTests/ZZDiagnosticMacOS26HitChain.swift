import AppKit
import SwiftUI
import Testing
@testable import Soaro

/// DIAGNOSTIC TEMPORAIRE (CI macOS 26) : ne vérifie RIEN et ne peut pas échouer. Il écrit dans le journal (`print("DIAG ...")`)
/// ce que la fenêtre contient vraiment sur l'OS qui l'exécute, pour comprendre pourquoi la CI (macOS 26) et les Mac de
/// développement (macOS 27) ne construisent pas les mêmes vues : le haut de la barre latérale, la « poche » de défilement
/// (`NSScrollPocket`), notre `WindowDragView`, les éléments de la barre d'outils.
/// À supprimer une fois la cause connue et corrigée (voir PLAN.md, EXP1).
@MainActor @Suite(.serialized) struct ZZDiagnosticMacOS26HitChainSuite {
    private func line(_ text: String) { print("DIAG \(text)") }

    private func makeWindow() async -> NSWindow {
        let state = AppState(history: HistoryStore(path: ":memory:"))
        let host = NSHostingController(rootView: MainWindowView(initialSection: .tab(.overview)).environmentObject(state))
        host.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: host)
        MainWindowController.configure(window)
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderFrontRegardless()
        try? await Task.sleep(for: .seconds(1.5))
        return window
    }

    @Test func ZZDiagnosticMacOS26HitChain() async {
        guard NSScreen.main != nil else { line("pas de serveur de fenêtres : rien à décrire"); return }
        let window = await makeWindow()
        defer { window.orderOut(nil) }
        guard let root = window.contentView?.superview else { line("pas de vue racine"); return }

        line("===== début =====")
        line("OS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        line("window styleMask=\(window.styleMask.rawValue) titlebarAppearsTransparent=\(window.titlebarAppearsTransparent) toolbarStyle=\(window.toolbarStyle.rawValue)"
             + " isOpaque=\(window.isOpaque) movableByBackground=\(window.isMovableByWindowBackground)")
        line("window frame=\(window.frame) contentView.frame=\(window.contentView?.frame ?? .zero) contentLayoutRect=\(window.contentLayoutRect) root.bounds=\(root.bounds)")

        describeToolbar(window)
        describeDragViewsAndPockets(root)
        for (name, x) in [("barre latérale", CGFloat(120)), ("détail", CGFloat(500))] {
            for dy in [CGFloat(4), 14, 26, 40] { describeHit(root, name: name, x: x, fromTop: dy) }
        }
        describeTopStripTree(root)
        line("===== fin =====")
    }

    // MARK: Barre d'outils

    private func describeToolbar(_ window: NSWindow) {
        guard let items = window.toolbar?.items else { line("toolbar : aucune"); return }
        line("toolbar : \(items.count) éléments")
        for item in items {
            line("toolbar item id=\(item.itemIdentifier.rawValue) label=\"\(item.label)\" paletteLabel=\"\(item.paletteLabel)\" toolTip=\(item.toolTip.map { "\"\($0)\"" } ?? "nil")"
                 + " enabled=\(item.isEnabled) view=\(item.view.map { WindowProbe.className($0) } ?? "nil")")
            if let view = item.view {
                line("  view.toolTip=\(view.toolTip.map { "\"\($0)\"" } ?? "nil") a11yLabel=\(view.accessibilityLabel().map { "\"\($0)\"" } ?? "nil")"
                     + " a11yHelp=\(view.accessibilityHelp().map { "\"\($0)\"" } ?? "nil") a11yTitle=\(view.accessibilityTitle().map { "\"\($0)\"" } ?? "nil")")
                for sub in WindowProbe.allViews(view).dropFirst() {
                    line("  descendant \(WindowProbe.className(sub)) toolTip=\(sub.toolTip.map { "\"\($0)\"" } ?? "nil")"
                         + " a11yLabel=\(sub.accessibilityLabel().map { "\"\($0)\"" } ?? "nil") a11yHelp=\(sub.accessibilityHelp().map { "\"\($0)\"" } ?? "nil")")
                }
            }
            line("  sources de l'info-bulle : \(WindowProbe.tooltipSources(of: item))")
            line("  sources du nom VoiceOver : \(WindowProbe.accessibilityLabelSources(of: item))")
        }
    }

    // MARK: Nos vues de glissement et les poches de défilement

    private func describeDragViewsAndPockets(_ root: NSView) {
        let everything = WindowProbe.allViews(root)
        let drags = everything.filter { $0 is WindowDragView }
        let pockets = everything.filter { WindowProbe.isPocketRelated($0) }
        line("WindowDragView : \(drags.count) ; vues « Pocket » : \(pockets.count)")
        for drag in drags {
            line("WindowDragView \(WindowProbe.describe(drag, in: root))")
            line("  parents : \(WindowProbe.chain(drag).dropFirst().map { WindowProbe.describe($0, in: root) }.joined(separator: "\n    < "))")
        }
        for pocket in pockets {
            line("Pocket \(WindowProbe.describe(pocket, in: root))")
            line("  parents : \(WindowProbe.chain(pocket).dropFirst().map { WindowProbe.className($0) }.joined(separator: " < "))")
            if let parent = pocket.superview {
                line("  sous-vues du parent (\(WindowProbe.className(parent))), de bas en haut :")
                for (index, sub) in parent.subviews.enumerated() { line("    [\(index)] \(WindowProbe.describe(sub, in: root))\(sub === pocket ? "   <== la poche" : "")") }
            }
            for drag in drags {
                let overlap = WindowProbe.rect(pocket, in: root).intersection(WindowProbe.rect(drag, in: root))
                line("  face à la vue de glissement (\(Int(WindowProbe.rect(drag, in: root).width)) pt de large) : recouvrement \(overlap.isNull ? "aucun" : "\(overlap)") ; \(WindowProbe.zOrder(drag, versus: pocket))")
            }
        }
    }

    // MARK: Hit tests

    private func describeHit(_ root: NSView, name: String, x: CGFloat, fromTop dy: CGFloat) {
        let point = NSPoint(x: x, y: root.bounds.height - dy)
        guard let hit = root.hitTest(point) else { line("hit \(name) x=\(Int(x)) dy=\(Int(dy)) : nil"); return }
        let event: NSEvent? = nil
        line("hit \(name) x=\(Int(x)) dy=\(Int(dy)) : \(WindowProbe.describe(hit, in: root)) acceptsFirstMouse=\(hit.acceptsFirstMouse(for: event))"
             + " dragSource=\(WindowProbe.dragSource(of: hit).map { "\($0)" } ?? "AUCUNE")")
        for (level, view) in WindowProbe.chain(hit).enumerated().dropFirst() {
            line("    parent \(level) : \(WindowProbe.describe(view, in: root))")
            if view === root.window?.contentView { break }
        }
        // Ce qu'il y aurait sous nos vues de glissement : si c'est une vue de la poche, la poche les recouvrirait sur un OS où elle est au-dessus.
        let drags = WindowProbe.allViews(root).filter { $0 is WindowDragView }
        let wasHidden = drags.map(\.isHidden)
        drags.forEach { $0.isHidden = true }
        let below = root.hitTest(point)
        for (drag, hidden) in zip(drags, wasHidden) { drag.isHidden = hidden }
        line("    sans les vues de glissement, le hit test donnerait : \(below.map { WindowProbe.describe($0, in: root) } ?? "nil")")
        let pockets = WindowProbe.allViews(root).filter { WindowProbe.isPocketRelated($0) }
        for pocket in pockets where WindowProbe.rect(pocket, in: root).contains(point) {
            line("    la poche \(WindowProbe.className(pocket)) contient ce point ; touché dans la poche : \(hit.isDescendant(of: pocket) || hit === pocket)")
        }
    }

    // MARK: Arbre du haut de la fenêtre

    /// Toutes les vues qui recouvrent la bande du haut (60 pt) de la barre latérale et du début de la colonne de détail,
    /// dans l'ordre d'empilement (le dernier de la liste d'un parent est au-dessus).
    private func describeTopStripTree(_ root: NSView) {
        let zone = NSRect(x: 0, y: root.bounds.height - 60, width: 260, height: 60)
        var count = 0
        func walk(_ view: NSView, depth: Int) {
            guard count < 400 else { return }
            let rect = WindowProbe.rect(view, in: root)
            guard rect.intersects(zone) else { return }
            count += 1
            line("tree \(String(repeating: "  ", count: depth))\(WindowProbe.describe(view, in: root))")
            for sub in view.subviews { walk(sub, depth: depth + 1) }
        }
        line("arbre des vues qui recouvrent le haut (x 0 à 260, 60 pt) :")
        walk(root, depth: 0)
    }
}
