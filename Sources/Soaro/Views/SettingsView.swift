import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var updater = Updater.shared
    @AppStorage(SettingsKey.notifications) private var notifications = true
    @AppStorage(SettingsKey.menuBarCPU) private var showCPU = true
    @AppStorage(SettingsKey.menuBarMemory) private var showMemory = false
    @AppStorage(SettingsKey.menuBarGPU) private var showGPU = false
    @AppStorage(SettingsKey.menuBarBattery) private var showBattery = false
    @AppStorage(SettingsKey.menuBarNetwork) private var showNetwork = false
    @AppStorage(SettingsKey.latency) private var latency = false
    @AppStorage(SettingsKey.menuBarDisk) private var showDisk = false
    @AppStorage(SettingsKey.menuBarCompact) private var compact = true
    /// L'ordre des mesures dans la barre de menus (SL22) : lu et écrit par la liste ci-dessous, lu par le libellé réel.
    @AppStorage(SettingsKey.menuBarOrder) private var orderSetting = MenuBarOrder.defaultSerialized
    @AppStorage(SettingsKey.publicIP) private var publicIP = false
    @StateObject private var launchAtLogin = LaunchAtLoginModel.live()
    @State private var thresholds = PressureThresholds.load()
    @State private var dropTarget: MenuBarMeasure?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Form {
            Section("In the menu bar") {
                Picker("Style", selection: $compact) {
                    Text("Compact (label above)").tag(true)
                    Text("Single line of text").tag(false)
                }
                MenuBarPreview(items: previewItems, compact: compact, severity: previewSeverity)
                Text("Drag the handles to change the order. The Soaro icon always comes first.")
                    .font(.caption).foregroundStyle(.supportingText)
                let rows = order.visible(hasBattery: state.hasBattery)
                ForEach(Array(rows.enumerated()), id: \.element) { index, measure in
                    measureRow(measure, index: index, count: rows.count, shown: Set(rows))
                }
            }
            Section("Value colors") {
                Text("In the menu bar, a value turns orange, then red, then scarlet when it crosses these thresholds.")
                    .font(.caption).foregroundStyle(.supportingText)
                // Valeurs actuelles : l'instantané d'`AppState` (en mode démo, celui de la démonstration).
                let live = ThresholdLiveValues(snapshot: state.snapshot)
                ThresholdEditor(title: "Processor and GPU (load)", thresholds: $thresholds.load, ascending: true, current: live.load)
                ThresholdEditor(title: "Disk (space used)", thresholds: $thresholds.disk, ascending: true, current: live.disk)
                if state.hasBattery {
                    ThresholdEditor(title: "Battery (level left, on battery power)", thresholds: $thresholds.battery, ascending: false, current: live.battery)
                }
                Text("Memory has no threshold: its color follows the real pressure measured by macOS (orange: high pressure; red: with swap of at least half the RAM; scarlet: critical pressure).")
                    .font(.caption).foregroundStyle(.supportingText)
                Button("Reset thresholds to defaults") { thresholds = .default }
                    .disabled(thresholds == .default)
            }
            .onChange(of: thresholds) { _, new in new.save() }
            Section("Settings tips") {
                Text("Soaro reads some macOS settings to suggest tips (battery, sleep, startup, storage, updates, backup). It never changes a setting: it opens the right System Settings pane.")
                    .font(.caption).foregroundStyle(.supportingText)
                Button(state.dismissedAdviceCount == 0 ? "No dismissed tips" : "Show dismissed tips again (\(state.dismissedAdviceCount))") {
                    state.restoreDismissedAdvice()
                }
                .disabled(state.dismissedAdviceCount == 0)
            }
            Section("Behavior") {
                Toggle("Notify on critical problems", isOn: $notifications)
                Toggle("Open at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { setLaunchAtLogin($0) }
                ))
            }
            Section("Network") {
                Toggle("Show public IP and country", isOn: $publicIP)
                    .onChange(of: publicIP) { _, enabled in
                        if enabled { state.refreshPublicIP(force: true) } else { state.forgetPublicIP() }
                    }
                Text("Off by default: asks a third-party service (ipwho.is, or ipapi.co as a backup), which then sees your public IP. It asks while the Network tab is open and while the country flag is shown in the menu bar: about every 5 minutes, and again when your network or VPN changes. Nothing is stored. VPN detection is entirely local.")
                    .font(.caption).foregroundStyle(.supportingText)
                Toggle("Measure latency (ping to 1.1.1.1)", isOn: $latency)
                Text("Off by default: this option sends a small packet to a Cloudflare server every 10 seconds, only while the Network tab is open.")
                    .font(.caption).foregroundStyle(.supportingText)
            }
            Section("Data") {
                Button("Clear history") { state.clearHistory() }
                Text("Soaro sends no data: history stays in ~/Library/Application Support/Soaro.")
                    .font(.caption).foregroundStyle(.supportingText)
            }
            if updater.isAvailable {
                Section("Updates") {
                    Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                    Button("Check for updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                    Text("Once a day, Soaro downloads a small public file from soaro.app to see if a new version exists. It sends no personal data.")
                        .font(.caption).foregroundStyle(.supportingText)
                }
            }
            Section("About") {
                Text("Soaro monitors CPU, GPU, memory, disk, network and battery. It only deletes caches, logs and rebuildable folders in your home folder, or moves items to the Trash (recoverable), always after confirmation.")
                    .font(.caption)
                    .foregroundStyle(.supportingText)
                // Opens the browser: the app itself sends nothing.
                WebsiteLinkRow(url: SupportLink.websiteURL(preferredLanguages: Bundle.main.preferredLocalizations))
                Link(destination: SupportLink.url) {
                    Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                }
                Text("Soaro is free and open source. Supporting it is optional.")
                    .font(.caption)
                    .foregroundStyle(.supportingText)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Ordre et aperçu de la barre de menus (SL22)

    private var order: MenuBarOrder { MenuBarOrder(parsing: orderSetting) }

    /// Les mêmes données que le libellé réel (`MenuBarLabel`) : mesure du moment (ou, sans mesure encore, les valeurs de démonstration),
    /// seuils de couleur, drapeau de l'IP publique, ordre enregistré. En mode démo, `state.snapshot` est déjà celui de la démonstration.
    private var previewItems: [MenuBarItem] {
        let flagCode = MenuBarFlag.countryCode(lookupEnabled: publicIP, demo: DemoMode.isEnabled, info: state.publicIP,
                                               matchesNetwork: state.publicIPMatchesNetwork, now: Date())
        return MenuBarItem.items(for: state.snapshot ?? DemoData.snapshot(), cpu: showCPU, gpu: showGPU, memory: showMemory, disk: showDisk,
                                 network: showNetwork, battery: showBattery, thresholds: thresholds, publicIPCountryCode: flagCode,
                                 order: MenuBarOrder(parsing: orderSetting))
    }

    /// Comme dans le vrai libellé : une simple suggestion ne mérite pas de badge.
    private var previewSeverity: Severity? { state.worstSeverity.flatMap { $0 >= .warning ? $0 : nil } }

    private func isOn(_ measure: MenuBarMeasure) -> Binding<Bool> {
        switch measure {
        case .cpu: $showCPU
        case .gpu: $showGPU
        case .memory: $showMemory
        case .disk: $showDisk
        case .network: $showNetwork
        case .battery: $showBattery
        }
    }

    /// Écrit le nouvel ordre dans la préférence ; la liste, l'aperçu et le vrai libellé la relisent. Sans animation si « Réduire les animations » est actif.
    private func change(_ edit: @escaping (inout MenuBarOrder) -> Void) {
        let new = MenuBarOrder.edit(stored: orderSetting, edit)
        guard new != orderSetting else { return }
        withAnimation(MenuBarOrder.reorderAnimation(reduceMotion: reduceMotion)) { orderSetting = new }
    }

    private func announceMove(_ measure: MenuBarMeasure) {
        let rows = order.visible(hasBattery: state.hasBattery)
        guard let index = rows.firstIndex(of: measure) else { return }
        AccessibilityNotification.Announcement(MenuBarOrder.announcement(title: measure.title, index: index, of: rows.count)).post()
    }

    /// Une ligne : la poignée à glisser, puis l'interrupteur de la mesure. On glisse la poignée seule : l'interrupteur garde son clic.
    /// Une `Form` groupée n'est pas une liste (`NSTableView`) : le déplacement de lignes des listes n'y a rien à quoi s'accrocher, d'où `.draggable` et `.dropDestination`.
    ///
    /// VoiceOver : la poignée est l'élément « réordonner » de la ligne (nom de la mesure, position en valeur, deux actions) ; l'interrupteur reste
    /// un élément à part, avec sa propre valeur (activé ou non), que l'on n'écrase pas.
    private func measureRow(_ measure: MenuBarMeasure, index: Int, count: Int, shown: Set<MenuBarMeasure>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.supportingText)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .help("Drag to change the order")
                .draggable(MenuBarMeasureDrag(measure: measure)) {
                    Text(measure.title)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel(Text(measure.title))
                .accessibilityValue(MenuBarOrder.positionText(index: index, of: count))
                .accessibilityHint(Text("Drag to change the order"))
                .accessibilityAction(named: "Move up") {
                    change { $0.moveUp(measure, among: shown) }
                    announceMove(measure)
                }
                .accessibilityAction(named: "Move down") {
                    change { $0.moveDown(measure, among: shown) }
                    announceMove(measure)
                }
            Toggle(isOn: isOn(measure)) { Text(measure.title) }
        }
        .padding(.horizontal, 4)
        .background(dropTarget == measure ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .dropDestination(for: MenuBarMeasureDrag.self) { items, _ in
            guard let dragged = items.first?.measure, dragged != measure else { return false }
            change { $0.move(dragged, onto: measure) }
            return true
        } isTargeted: { targeted in
            if targeted { dropTarget = measure } else if dropTarget == measure { dropTarget = nil }
        }
        .contextMenu {
            Button("Move up") { change { $0.moveUp(measure, among: shown) } }
                .disabled(!order.canMoveUp(measure, among: shown))
            Button("Move down") { change { $0.moveDown(measure, among: shown) } }
                .disabled(!order.canMoveDown(measure, among: shown))
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if !launchAtLogin.set(enabled) {
            state.showToast(String(localized: "Cannot open at login: put the app in Applications."))
        }
    }
}

/// Where the "Buy me a coffee" button and the website link lead. Both open the browser: the app itself sends nothing.
enum SupportLink {
    static let url = URL(string: "https://buymeacoffee.com/sebmafate")!

    /// The website (SL18). The text shown next to the logo is the domain.
    static let website = URL(string: "https://soaro.app")!
    static let websiteFrench = URL(string: "https://soaro.app/fr/")!
    static let websiteText = "soaro.app"

    /// Le site existe en anglais et en français : la première langue de l'app décide (« fr », « fr-CA », « fr_FR »…, pas « frisian »).
    static func websiteURL(preferredLanguages: [String]) -> URL {
        guard let first = preferredLanguages.first?.lowercased() else { return website }
        let code = first.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? first
        return code == "fr" ? websiteFrench : website
    }
}
