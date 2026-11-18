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
            // For screenshots: "overview", "machine", "settings", or "cleanup:largeFiles" (a cleanup tool).
            let requested = ProcessInfo.processInfo.environment["SOARO_SECTION"] ?? ""
            let parts = requested.split(separator: ":").map(String.init)
            let section: WindowSection
            switch parts.first {
            case "machine": section = .machine
            case "settings": section = .settings
            case .some(let name): section = .tab(AppTab(rawValue: name) ?? .overview)
            case nil: section = .tab(.overview)
            }
            if parts.count > 1, let route = CleanupRoute(rawValue: parts[1]) { AppState.shared.requestedCleanupRoute = route }
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
        if Snapshot.outputDirectory == nil, !DemoMode.isEnabled { LegacyMigration.run() }
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
    /// L'ordre des mesures (SL22) : relit la préférence comme les interrupteurs ; une valeur abîmée donne l'ordre de toujours.
    @AppStorage(SettingsKey.menuBarOrder) private var orderSetting = MenuBarOrder.defaultSerialized
    /// Le réglage facultatif qui existe déjà : le drapeau ne lit que son résultat, il ne demande rien.
    @AppStorage(SettingsKey.publicIP) private var publicIPLookup = false

    private var items: [MenuBarItem] {
        guard let s = state.snapshot else { return [] }
        let flagCode = MenuBarFlag.countryCode(lookupEnabled: publicIPLookup, demo: DemoMode.isEnabled, info: state.publicIP,
                                               matchesNetwork: state.publicIPMatchesNetwork, now: Date())
        return MenuBarItem.items(for: s, cpu: showCPU, gpu: showGPU, memory: showMemory, disk: showDisk, network: showNetwork, battery: showBattery,
                                  thresholds: .load(), publicIPCountryCode: flagCode,
                                  order: MenuBarOrder(parsing: orderSetting))
    }

    /// L'image du libellé : la même instance tant que rien ne change (`MenuBarRenderer` la garde), à toutes les échelles.
    private var labelImage: NSImage? {
        // `.info` (simples suggestions) ne mérite pas de badge permanent dans la barre de menus.
        let severity = state.worstSeverity.flatMap { $0 >= .warning ? $0 : nil }
        return MenuBarRenderer.image(severity: severity, compact: compact, items: items)
    }

    var body: some View {
        let image = labelImage
        Group {
            if let image {
                Image(nsImage: image)
            } else {
                Image(systemName: "water.waves")
            }
        }
        .task { state.start() }
        // Réappliquée à chaque mesure : SwiftUI peut recréer le bouton de barre de menus (et y reposer sa propre copie de l'image).
        .onChange(of: state.snapshot?.date, initial: true) {
            let text = MenuBarTooltip.text(recommendations: state.recommendations, snapshot: state.snapshot, items: items)
            let count = MenuBarRenderer.setToolTip(text)
            installLabelImage()
            if ProcessInfo.processInfo.environment["SOARO_DEBUG"] != nil {
                FileHandle.standardError.write(Data("tooltip: \(count) view(s) updated\n\(MenuBarRenderer.debugHierarchy())\(MenuBarRenderer.describeButtons(comparedTo: labelImage))\n---\n".utf8))
            }
        }
        // Quand l'image change (une valeur, l'ordre, un réglage), on la repose aussitôt, puis au tour suivant de la boucle d'événements :
        // SwiftUI applique son propre libellé après le calcul de `body`.
        .onChange(of: image.map(ObjectIdentifier.init), initial: true) { installLabelImage() }
    }

    private func installLabelImage() {
        guard let image = labelImage else { return }
        MenuBarRenderer.installOnStatusBarButtons(image)
        DispatchQueue.main.async { MenuBarRenderer.installOnStatusBarButtons(image) }
    }
}
