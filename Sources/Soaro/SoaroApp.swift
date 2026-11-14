import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pas d'icône dans le Dock, même en lançant via `swift run`.
        NSApp.setActivationPolicy(.accessory)
        // Démarre Sparkle (vérification planifiée des mises à jour) dès le lancement.
        MainActor.assumeIsolated { Updater.shared.start() }
    }

    /// Relancer l'app alors qu'elle tourne déjà (Finder, Spotlight, `open`) ouvre la fenêtre indépendante.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            let requested = ProcessInfo.processInfo.environment["SOARO_SECTION"]
            let section: WindowSection = requested == "machine" ? .machine : (requested.flatMap(AppTab.init(rawValue:)).map(WindowSection.tab) ?? .tab(.overview))
            MainWindowController.shared.show(state: .shared, section: section)
            if let path = ProcessInfo.processInfo.environment["SOARO_CAPTURE"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { MainWindowController.shared.captureForDebugging(to: path) }
            }
        }
        return false
    }
}

@main
struct SoaroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared

    init() {
        if Diagnostics.isRequested { Diagnostics.run() }
        if Diagnostics.isScanRequested { Diagnostics.scan() }
        if Diagnostics.isAdviceRequested { Diagnostics.advice() }
        if let directory = Snapshot.outputDirectory { MainActor.assumeIsolated { Snapshot.run(into: directory) } }
        // Reprise des données de l'ancienne version, avant tout accès aux préférences ou à l'historique.
        if Snapshot.outputDirectory == nil { LegacyMigration.run() }
        UserDefaults.standard.register(defaults: SettingsKey.defaults)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(state)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var state: AppState
    @AppStorage(SettingsKey.menuBarCPU) private var showCPU = true
    @AppStorage(SettingsKey.menuBarMemory) private var showMemory = false
    @AppStorage(SettingsKey.menuBarGPU) private var showGPU = false
    @AppStorage(SettingsKey.menuBarDisk) private var showDisk = false
    @AppStorage(SettingsKey.menuBarBattery) private var showBattery = false
    @AppStorage(SettingsKey.menuBarNetwork) private var showNetwork = false
    @AppStorage(SettingsKey.menuBarCompact) private var compact = true

    private var items: [MenuBarItem] {
        guard let s = state.snapshot else { return [] }
        return MenuBarItem.items(for: s, cpu: showCPU, gpu: showGPU, memory: showMemory, disk: showDisk, network: showNetwork, battery: showBattery,
                                  thresholds: .load())
    }

    var body: some View {
        Group {
            // `.info` (simples suggestions) ne mérite pas de badge permanent dans la barre de menus.
            let severity = state.worstSeverity.flatMap { $0 >= .warning ? $0 : nil }
            if let image = MenuBarRenderer.image(severity: severity, compact: compact, items: items) {
                Image(nsImage: image)
            } else {
                Image(systemName: "water.waves")
            }
        }
        .task { state.start() }
        // Réappliquée à chaque mesure : SwiftUI peut recréer le bouton de barre de menus.
        .onChange(of: state.snapshot?.date, initial: true) {
            let text = MenuBarTooltip.text(recommendations: state.recommendations, snapshot: state.snapshot, items: items)
            let count = MenuBarRenderer.setToolTip(text)
            if ProcessInfo.processInfo.environment["SOARO_DEBUG"] != nil {
                FileHandle.standardError.write(Data("infobulle : \(count) vue(s) mises à jour\n\(MenuBarRenderer.debugHierarchy())---\n".utf8))
            }
        }
    }
}
