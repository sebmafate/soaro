import AppKit
import SwiftUI

/// `Soaro --snapshot <dossier> [--dark]` : rend chaque onglet en PNG (rendu hors écran) puis quitte.
/// Sert à vérifier l'interface sans ouvrir la barre de menus (tests visuels, captures de documentation).
@MainActor
enum Snapshot {
    static var outputDirectory: String? {
        guard let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    static func run(into directory: String) {
        let dark = CommandLine.arguments.contains("--dark")
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        // Base en mémoire pré-remplie : on ne touche jamais à l'historique réel.
        let store = HistoryStore(path: ":memory:")
        Self.seed(store)
        let state = AppState(history: store)
        state.start()
        state.isPopoverVisible = true

        // Fenêtre réellement « affichée » (donc cycle de vie SwiftUI complet : .task, onAppear…) mais très loin hors de l'écran.
        let host = NSHostingView(rootView: PopoverContent().environmentObject(state))
        host.frame = NSRect(origin: .zero, size: PanelMetrics.size)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: PanelMetrics.size.width, height: PanelMetrics.size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = host.appearance
        window.contentView = host
        window.orderFrontRegardless()

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))          // laisse les mesures arriver
            for tab in AppTab.allCases where tab != .battery || state.hasBattery {
                state.activeTab = tab
                try? await Task.sleep(for: .seconds(tab == .battery || tab == .network ? 5 : 2))
                capture(host, named: tab.rawValue, in: directory)
            }
            captureMenuBar(state: state, directory: directory)
            if CommandLine.arguments.contains("--window") { await captureWindow(state: state, directory: directory, dark: dark) }
            if CommandLine.arguments.contains("--tools") { await captureTools(state: state, window: window, directory: directory, dark: dark) }
            print("snapshots written to \(directory)")
            exit(0)
        }
    }

    /// Les outils de nettoyage et les réglages, avec de vraies analyses (en lecture seule) du dossier personnel.
    private static func captureTools(state: AppState, window: NSWindow, directory: String, dark: Bool) async {
        let notify: (String) -> Void = { _ in }
        let largeFiles = LargeFilesModel(notify: notify)
        let devProjects = DevArtifactsModel(notify: notify)
        let uninstaller = UninstallerModel(notify: notify)
        let startup = StartupModel(notify: notify)

        let steps: [(name: String, wait: Double, view: AnyView)] = [
            ("tool-largefiles", 22, AnyView(LargeFilesView(model: largeFiles))),
            ("tool-devprojects", 14, AnyView(DevProjectsView(model: devProjects))),
            ("tool-uninstaller", 8, AnyView(UninstallerView(model: uninstaller))),
            ("tool-startup", 5, AnyView(StartupItemsView(model: startup))),
            ("settings", 2, AnyView(SettingsView())),
        ]
        for step in steps {
            let host = NSHostingView(rootView: step.view.environmentObject(state).frame(width: PanelMetrics.size.width, height: PanelMetrics.size.height).background(Color(nsColor: .windowBackgroundColor)))
            host.frame = NSRect(origin: .zero, size: PanelMetrics.size)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = host
            try? await Task.sleep(for: .seconds(step.wait))
            capture(host, named: step.name, in: directory)
        }
    }

    /// Libellé de la barre de menus : mesures réelles, puis une démonstration des quatre niveaux, sur barre sombre et claire.
    private static func captureMenuBar(state: AppState, directory: String) {
        guard let snap = state.snapshot else { return }
        let compact = !CommandLine.arguments.contains("--inline")
        let flagCode = MenuBarFlag.countryCode(lookupEnabled: state.publicIPEnabled, demo: DemoMode.isEnabled, info: state.publicIP, matchesNetwork: state.publicIPMatchesNetwork, now: Date())
        let real = MenuBarItem.items(for: snap, cpu: true, gpu: true, memory: true, disk: true, network: true, battery: true, publicIPCountryCode: flagCode)
        let demo: [MenuBarItem] = [
            .stacked(label: "CPU", value: "34%", level: .normal), .stacked(label: "GPU", value: "72%", level: .medium),
            .stacked(label: "RAM", value: "83%", level: .high), .stacked(label: "SSD", value: "97%", level: .critical),
            .pair(top: "↑ 6 KB/s", bottom: "↓ 8 KB/s"), .flag(countryCode: "FR"),
            .battery(percent: 18, charging: false, level: .medium),
        ]
        for (name, items, severity) in [("menubar", real, Severity?.none), ("menubar-demo", demo, Severity.warning)] {
            for dark in [true, false] {
                guard let image = MenuBarRenderer.image(severity: severity, compact: compact, items: items, darkBar: dark) else { continue }
                save(image, dark: dark, to: URL(fileURLWithPath: directory).appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
        }
    }

    private static func save(_ image: NSImage, dark: Bool, to url: URL) {
        let scale: CGFloat = 3
        let size = NSSize(width: (image.size.width + 20) * scale, height: (image.size.height + 8) * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: dark ? 0.16 : 0.9, alpha: 1).set()
        NSRect(origin: .zero, size: size).fill()
        let rect = NSRect(x: 10 * scale, y: 4 * scale, width: image.size.width * scale, height: image.size.height * scale)
        if image.isTemplate {
            // Simule la teinte appliquée par macOS à une image modèle : l'image est teinte seule (sur fond transparent), puis posée sur le fond.
            // (Teinter directement sur le fond opaque, avec `sourceAtop`, colorait tout le rectangle.)
            let tinted = NSImage(size: image.size)
            tinted.lockFocus()
            image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            (dark ? NSColor.white : NSColor.black).set()
            NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: rect)
        } else {
            image.draw(in: rect)
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// La fenêtre indépendante, sur trois sections.
    private static func captureWindow(state: AppState, directory: String, dark: Bool) async {
        let size = NSSize(width: 860, height: 680)
        for section in [WindowSection.machine, .tab(.overview), .tab(.performance)] {
            let host = NSHostingView(rootView: MainWindowView(initialSection: section).environmentObject(state))
            host.frame = NSRect(origin: .zero, size: size)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: size.width, height: size.height),
                                  styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.appearance = host.appearance
            window.contentView = host
            window.orderFrontRegardless()
            try? await Task.sleep(for: .seconds(4))
            capture(host, named: "window-\(section.id)", in: directory)
            window.orderOut(nil)
        }
    }

    private static func capture(_ host: NSView, named name: String, in directory: String) {
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }

    /// 36 h de données factices (cycle jour/nuit) pour juger les graphiques.
    /// In-memory history filled with 36 hours of made-up data, for demo mode.
    static func demoStore() -> HistoryStore? {
        let store = HistoryStore(path: ":memory:")
        seed(store)
        return store
    }

    private static func seed(_ store: HistoryStore?) {
        guard let store else { return }
        let now = Date()
        for i in stride(from: 0, to: 36 * 120, by: 1) {                  // un point toutes les 30 s
            let t = now.addingTimeInterval(-Double(i) * 30)
            let hour = Double(i) / 120
            let wave = (sin(hour / 3) + 1) / 2
            // Deterministic noise, so the charts look like real measurements and not like a sine wave.
            func noise(_ k: Double) -> Double { sin(Double(i) * 12.9898 * k) * 0.5 + sin(Double(i) * 0.37 * k) * 0.5 }
            let jitter = noise(1) * 0.07 + noise(2.3) * 0.04
            store.insert(HistoryRow(
                timestamp: t, cpu: max(0.02, 0.15 + 0.5 * wave + jitter), memory: 0.6 + 0.25 * wave + jitter * 0.2, gpu: max(0, 0.05 + 0.2 * wave + jitter * 0.5),
                netDown: max(0, 200_000 + 3_000_000 * wave * (1 + jitter * 3)), netUp: max(0, 50_000 + 400_000 * wave * (1 + jitter * 3)),
                diskRead: max(0, 1_000_000 * wave * (1 + jitter * 4)), diskWrite: max(0, 500_000 * wave * (1 + jitter * 4)),
                battery: 100 - 60 * (1 - wave), cpuTemp: 38 + 30 * wave + jitter * 20, power: max(3, 8 + 25 * wave + jitter * 15)
            ))
        }
    }
}
