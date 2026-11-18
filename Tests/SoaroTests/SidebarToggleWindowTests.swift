import AppKit
import SwiftUI
import Testing
@testable import Soaro

/// SL20 : le bouton dans la vraie fenêtre (hors écran, rien n'est montré à l'utilisateur). Les calculs purs sont dans `SidebarToggleTests`.
/// Ce qu'on ne peut pas tester : un vrai clic de souris (on envoie les événements à la fenêtre), l'animation, VoiceOver lui-même.
@MainActor @Suite(.serialized) struct SidebarToggleWindowTests {
    // MARK: Dans la vraie fenêtre (hors écran, rien n'est montré à l'utilisateur)

    /// Même réglage que `MainWindowController.show`, fenêtre placée très loin hors de l'écran.
    private func makeWindow() async throws -> NSWindow {
        let state = AppState(history: HistoryStore(path: ":memory:"))
        let host = NSHostingController(rootView: MainWindowView(initialSection: .tab(.overview)).environmentObject(state))
        host.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: host)
        window.title = "Soaro"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.setContentSize(NSSize(width: 860, height: 680))
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderFrontRegardless()
        try await Task.sleep(for: .seconds(1.5))
        return window
    }

    @Test func theToolbarHoldsOneSidebarToggleAndThePinButton() async throws {
        guard NSScreen.main != nil else { return }      // pas de serveur de fenêtres : rien à tester
        let window = try await makeWindow()
        defer { window.orderOut(nil) }
        let items = try #require(window.toolbar?.items)
        let toggles = items.filter { $0.label == String(localized: "Toggle Sidebar") }
        #expect(toggles.count == 1, "\(items.map(\.label))")
        // Aucun bouton automatique du système en plus du nôtre.
        #expect(!items.contains { $0.itemIdentifier.rawValue.localizedCaseInsensitiveContains("sidebar") })
        #expect(!items.contains { $0.itemIdentifier == .toggleSidebar })
        #expect(items.contains { $0.label == String(localized: "Always on top") }, "le bouton d'épingle doit rester : \(items.map(\.label))")
        #expect(items.count == 2)
    }

    @Test func theToggleHasATooltipAndALabelForVoiceOver() async throws {
        guard NSScreen.main != nil else { return }
        let window = try await makeWindow()
        defer { window.orderOut(nil) }
        let items = try #require(window.toolbar?.items)
        let expected = String(localized: "Toggle Sidebar")
        let toggle = try #require(items.first { $0.label == expected })
        // Selon l'OS, SwiftUI expose `.help` et `.accessibilityLabel` par un mécanisme différent : `toolTip` de l'`NSToolbarItem`
        // (macOS 27, constaté), `toolTip` ou aide d'accessibilité de la vue de l'élément, de ses descendants ou de son conteneur.
        // Le test exige la PROPRIÉTÉ (une info-bulle exacte, un nom exact pour VoiceOver) par au moins un de ces chemins.
        let tooltips = WindowProbe.tooltipSources(of: toggle)
        let labels = WindowProbe.accessibilityLabelSources(of: toggle)
        print("INFO bouton de la barre latérale sur \(ProcessInfo.processInfo.operatingSystemVersionString) : info-bulle par \(tooltips.filter { $0.text == expected }.map(\.mechanism)) ; nom VoiceOver par \(labels.filter { $0.text == expected }.map(\.mechanism))")
        #expect(tooltips.contains { $0.text == expected }, "aucune info-bulle \"\(expected)\" : \(tooltips) ; toolTip de l'élément : \(String(describing: toggle.toolTip))")
        #expect(labels.contains { $0.text == expected }, "aucun nom VoiceOver \"\(expected)\" : \(labels)")
        #expect(toggle.isEnabled)
    }

    @Test func theToggleSitsBeforeThePinButton() async throws {
        guard NSScreen.main != nil else { return }
        let window = try await makeWindow()
        defer { window.orderOut(nil) }
        let items = try #require(window.toolbar?.items)
        let toggleIndex = try #require(items.firstIndex { $0.label == String(localized: "Toggle Sidebar") })
        let pinIndex = try #require(items.firstIndex { $0.label == String(localized: "Always on top") })
        #expect(toggleIndex < pinIndex, "à gauche, là où le bouton standard se trouve : \(items.map(\.label))")
    }

    // MARK: Le clic (événements envoyés à la vraie fenêtre : la barre d'outils SwiftUI n'expose pas d'action AppKit)

    private func toolbarItem(_ window: NSWindow, _ label: String) throws -> NSToolbarItem {
        try #require(window.toolbar?.items.first { $0.label == label })
    }

    private func click(_ item: NSToolbarItem, in window: NSWindow) throws {
        let view = try #require(item.view)
        let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        window.makeKey()
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
    }

    /// La colonne de la barre latérale du `NSSplitView` (la plus étroite) : masquée quand la barre est repliée.
    private func sidebarIsHidden(_ window: NSWindow) throws -> Bool {
        func find(_ view: NSView) -> NSSplitView? {
            if let split = view as? NSSplitView { return split }
            for sub in view.subviews { if let found = find(sub) { return found } }
            return nil
        }
        let split = try #require(window.contentView?.superview.flatMap(find))
        let columns = split.subviews.filter { String(describing: type(of: $0)).contains("ItemViewWrapper") }
        let sidebar = try #require(columns.min { $0.frame.width < $1.frame.width })
        return sidebar.isHidden
    }

    /// Attend (au plus 3 s) que la condition soit vraie : le repli est animé par le système.
    private func wait(until condition: () throws -> Bool) async throws -> Bool {
        for _ in 0..<30 {
            if try condition() { return true }
            try await Task.sleep(for: .milliseconds(100))
        }
        return try condition()
    }

    @Test func theSidebarIsOpenWhenTheWindowOpens() async throws {
        guard NSScreen.main != nil else { return }
        let window = try await makeWindow()
        defer { window.orderOut(nil) }
        #expect(try !sidebarIsHidden(window))
    }

    @Test func clickingTheButtonCollapsesThenReopensTheSidebar() async throws {
        guard NSScreen.main != nil else { return }
        let window = try await makeWindow()
        defer { window.orderOut(nil) }
        let toggle = try toolbarItem(window, String(localized: "Toggle Sidebar"))
        try click(toggle, in: window)
        #expect(try await wait { try sidebarIsHidden(window) }, "la barre latérale devrait être repliée")
        // Repliée, le bouton reste dans la barre d'outils de la colonne de détail et fonctionne encore.
        let stillThere = try toolbarItem(window, String(localized: "Toggle Sidebar"))
        #expect(stillThere.view?.window === window)
        try click(stillThere, in: window)
        #expect(try await wait { try !sidebarIsHidden(window) }, "la barre latérale devrait être rouverte")
    }

    @Test func thePinButtonStillWorksWithTheSidebarCollapsed() async throws {
        guard NSScreen.main != nil else { return }
        let saved = UserDefaults.standard.object(forKey: MainWindowController.pinnedKey)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: MainWindowController.pinnedKey) }
            else { UserDefaults.standard.removeObject(forKey: MainWindowController.pinnedKey) }
        }
        UserDefaults.standard.set(false, forKey: MainWindowController.pinnedKey)
        let window = try await makeWindow()
        defer { window.orderOut(nil) }
        try click(try toolbarItem(window, String(localized: "Toggle Sidebar")), in: window)
        #expect(try await wait { try sidebarIsHidden(window) })
        try click(try toolbarItem(window, String(localized: "Always on top")), in: window)
        #expect(try await wait { UserDefaults.standard.bool(forKey: MainWindowController.pinnedKey) }, "le bouton d'épingle doit répondre")
    }
}
