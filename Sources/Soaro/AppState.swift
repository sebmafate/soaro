import AppKit
import Foundation
import UserNotifications

enum SettingsKey {
    static let notifications = "notificationsEnabled"
    static let menuBarCPU = "menuBarCPU"
    static let menuBarMemory = "menuBarMemory"
    static let menuBarGPU = "menuBarGPU"
    static let menuBarBattery = "menuBarBattery"
    static let menuBarNetwork = "menuBarNetwork"
    static let latency = "latencyEnabled"
    static let publicIP = "publicIPEnabled"
    static let menuBarDisk = "menuBarDisk"
    static let menuBarCompact = "menuBarCompact"
    /// L'ordre des mesures dans la barre de menus (SL22) : « cpu,gpu,memory,disk,network,battery », voir `MenuBarOrder`.
    static let menuBarOrder = "menuBarOrder"

    static let defaults: [String: Any] = [
        notifications: true, menuBarCPU: true, menuBarMemory: false, menuBarGPU: false,
        menuBarBattery: false, menuBarNetwork: false, latency: false, publicIP: false, menuBarDisk: false, menuBarCompact: true,
        menuBarOrder: MenuBarOrder.defaultSerialized,
    ]
}

enum AppTab: String, CaseIterable, Identifiable {
    case overview, performance, battery, network, history, cleanup
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .performance: String(localized: "Performance")
        case .battery: String(localized: "Battery")
        case .network: String(localized: "Network")
        case .history: String(localized: "History")
        case .cleanup: String(localized: "Cleanup")
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "gauge.with.dots.needle.50percent"
        case .performance: "cpu"
        case .battery: "battery.75percent"
        case .network: "network"
        case .history: "chart.xyaxis.line"
        case .cleanup: "sparkles"
        }
    }
}

enum PublicIPState: Equatable {
    case idle
    case loading
    case failed(String)
}

struct DailyTraffic: Equatable {
    var down: UInt64 = 0
    var up: UInt64 = 0
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var snapshot: SystemSnapshot?
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryHistory: [Double] = []
    @Published private(set) var gpuHistory: [Double] = []
    @Published private(set) var netDownHistory: [Double] = []
    @Published private(set) var netUpHistory: [Double] = []
    @Published private(set) var batteryHistory: [Double] = []
    @Published private(set) var processes: [ProcessGroup] = []
    @Published private(set) var networkProcesses: [NetworkProcess] = []
    @Published private(set) var energyEntries: [EnergyEntry] = []
    @Published private(set) var leaks: [LeakSuspect] = []
    @Published private(set) var cleanupSizes: [CleanupKind: UInt64?] = [:]
    @Published private(set) var recommendations: [Recommendation] = []
    @Published private(set) var busyKinds: Set<CleanupKind> = []
    @Published private(set) var toast: String?
    @Published private(set) var smartStatus: String?
    @Published private(set) var latencyMs: Double?
    @Published private(set) var todayTraffic = DailyTraffic()
    @Published private(set) var vpn: VPNStatus?
    /// Conseils de réglage visibles (ceux que l'utilisateur a ignorés sont retirés).
    @Published private(set) var advice: [Advice] = []
    @Published private(set) var systemFacts = SystemFacts()
    @Published private(set) var dismissedAdviceCount = 0
    /// Demande d'ouverture d'un outil de l'onglet Nettoyage (consommée par l'interface).
    @Published var requestedCleanupRoute: CleanupRoute?
    @Published private(set) var publicIP: PublicIPInfo?
    @Published private(set) var publicIPState: PublicIPState = .idle

    @Published var activeTab: AppTab = .overview {
        didSet { if activeTab != oldValue { refreshForActiveTabs() } }
    }

    /// Le panneau de la barre de menus est-il affiché ?
    var isPopoverVisible = false {
        didSet { if isPopoverVisible, !oldValue { becameVisible() } }
    }

    /// La fenêtre indépendante est-elle affichée (et non masquée par d'autres fenêtres) ?
    var isWindowVisible = false {
        didSet { if isWindowVisible, !oldValue { becameVisible() } }
    }

    /// Section affichée dans la fenêtre (`nil` : une section sans mesures, comme « Ce Mac » ou les réglages).
    var windowTab: AppTab? {
        didSet { if windowTab != oldValue { refreshForActiveTabs() } }
    }

    var isUIVisible: Bool { isPopoverVisible || isWindowVisible }

    /// Onglets réellement à l'écran : ce sont eux qui décident quelles mesures coûteuses tournent.
    var activeTabs: Set<AppTab> {
        var tabs: Set<AppTab> = []
        if isPopoverVisible { tabs.insert(activeTab) }
        if isWindowVisible, let windowTab { tabs.insert(windowTab) }
        return tabs
    }

    private func becameVisible() {
        refreshProcesses()
        if Date().timeIntervalSince(lastFactsRefresh) > 30 { refreshSystemFacts() }
        refreshForActiveTabs()
    }

    var hasBattery: Bool { snapshot?.battery != nil }
    let history: HistoryStore?

    /// Instance de l'app (créée au premier accès, donc après la migration des anciennes données).
    static let shared = AppState(history: DemoMode.isEnabled ? Snapshot.demoStore() : HistoryStore())

    /// Mode démo, et les actions qui touchent au vrai système : remplaçables pour que les tests vérifient
    /// qu'en démo rien n'est nettoyé et aucune vraie app n'est quittée. Par défaut, le comportement réel.
    /// Ce drapeau ne couvre que les actions qui touchent au système (`cleanup`, `scanCleanup`, `quitApp`) ;
    /// les autres vérifications du mode démo lisent encore `DemoMode.isEnabled` directement.
    private let demo: Bool
    private let confirm: ConfirmHandler
    private let cleanAction: @Sendable (CleanupKind) -> CleanupResult
    private let terminateApp: @MainActor (String) -> Bool
    /// Annonce vocale des toasts (VoiceOver) : remplaçable pour que les tests n'envoient aucune vraie notification.
    private let announce: @MainActor (String) -> Void
    /// Recherche d'IP publique, réglages qu'elle lit et condition d'affichage du drapeau : remplaçables pour que les tests n'ouvrent aucune
    /// connexion et ne touchent pas aux vraies préférences. Par défaut, le comportement réel.
    private let publicIPFetch: @Sendable () async throws -> PublicIPInfo
    private let publicIPSetting: () -> Bool
    private let networkItemShown: (SystemSnapshot?) -> Bool
    /// Suivi des changements de réseau (SL25) : source d'événements, minuteur, signaux, VPN, heure, journal. Par défaut, le comportement réel.
    private let watching: NetworkWatching

    init(history: HistoryStore? = HistoryStore(),
         demo: Bool = DemoMode.isEnabled,
         confirm: @escaping ConfirmHandler = SystemConfirmation.ask,
         clean: @escaping @Sendable (CleanupKind) -> CleanupResult = { CleanupService.clean($0) },
         terminateApp: @escaping @MainActor (String) -> Bool = { path in
             NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == path }?.terminate() == true
         },
         publicIPFetch: @escaping @Sendable () async throws -> PublicIPInfo = { try await PublicIPService.fetch() },
         publicIPSetting: @escaping () -> Bool = { UserDefaults.standard.bool(forKey: SettingsKey.publicIP) },
         // Le bloc réseau est dans la barre de menus : réglage coché ET débit mesuré (la condition d'affichage du drapeau).
         networkItemShown: @escaping (SystemSnapshot?) -> Bool = { UserDefaults.standard.bool(forKey: SettingsKey.menuBarNetwork) && $0?.network != nil },
         networkWatching: NetworkWatching = NetworkWatching(),
         announce: @escaping @MainActor (String) -> Void = ToastAnnouncer.announce) {
        self.history = history
        self.demo = demo
        self.confirm = confirm
        self.cleanAction = clean
        self.terminateApp = terminateApp
        self.announce = announce
        self.publicIPFetch = publicIPFetch
        self.publicIPSetting = publicIPSetting
        self.networkItemShown = networkItemShown
        self.watching = networkWatching
    }

    // Mesures
    private let sampler = SystemSampler()
    private let networkSampler = NetworkSampler()
    private let diskIOSampler = DiskIOSampler()
    private let sensorSampler = SensorSampler()
    private var lastSensors: SensorStats?
    private var lastBattery: BatteryStats?

    // Planification
    private let historyLength = 60
    private var timer: Timer?
    private var tickCount = 0
    private var lastTick = Date()
    private var lastProcessRefresh = Date.distantPast
    private var lastCleanupScan = Date.distantPast
    private var lastNetworkProcessRefresh = Date.distantPast
    private var lastEnergyRefresh = Date.distantPast
    private var lastLatency = Date.distantPast
    private var lastVPNRefresh = Date.distantPast
    private var lastFactsRefresh = Date.distantPast
    private var factsRefreshInFlight = false
    private static let dismissedAdviceKey = "dismissedAdvice"
    private static let osVersion: String = {
        if DemoMode.isEnabled { return DemoMode.osVersion }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
    }()
    private var lastPublicIPAttempt = Date.distantPast
    private var publicIPFingerprint = ""
    /// Empreinte de la connexion au moment de la recherche dont vient `publicIP` : si elle a changé depuis, la réponse n'est plus celle d'ici.
    private var publicIPInfoFingerprint = ""
    /// SL25 : l'empreinte de la dernière recherche était-elle complète (détection du VPN rendue, signaux lus) ? Sinon, la première empreinte complète
    /// la remplace sans recherche : passer d'incomplet à complet n'est pas un changement.
    private var publicIPBaselineComplete = false
    /// SL25 : détections du VPN en cours, et début de l'attente de la première recherche (voir `firstLookupWaitCap`).
    private var vpnDetectionsInFlight = 0
    private var firstLookupWaitStart: Date?
    private var lastPublicIPFailure: Date?
    /// SL25 : l'empreinte doit rester la même quelques secondes avant de compter comme un changement (rafales d'événements).
    private var settler = FingerprintSettler()
    /// SL25 : un réveil a eu lieu et aucune recherche n'a encore été lancée depuis (le réseau a pu changer pendant le sommeil).
    private var forcedChange = false
    /// SL25 : date de la dernière recherche déclenchée par un changement, tant que sa confirmation n'a pas eu lieu.
    private var lastChangeTriggeredLookup: Date?
    /// SL25 : le moniteur de changements de réseau : il n'existe que tant que le drapeau ou l'onglet Réseau en a besoin.
    private var networkMonitor: NetworkChangeMonitor?
    var isNetworkMonitorRunning: Bool { networkMonitor?.isRunning == true }
    /// La détection du VPN en cours (lue par les tests pour l'attendre).
    private(set) var vpnRefreshTask: Task<Void, Never>?
    /// Incrémenté à chaque départ et à chaque oubli : une réponse d'une recherche périmée est jetée.
    private var publicIPGeneration = 0
    /// La recherche en cours (lue par les tests pour l'attendre).
    private(set) var publicIPLookupTask: Task<Void, Never>?
    private var lastSensorRead = Date.distantPast
    private var lastTrafficSave = Date()
    private var processRefreshInFlight = false
    private var networkRefreshInFlight = false
    private var energyRefreshInFlight = false
    private var smartInFlight = false

    // Données dérivées
    private var accumulator = HistoryAccumulator()
    private var trendTracker = MemoryTrendTracker()
    private var previousIO: (date: Date, counters: [Int32: ProcessIOSampler.Counters])?
    private var trafficDay = AppState.dayKey()
    private var trafficDown = 0.0
    private var trafficUp = 0.0

    private var toastTask: Task<Void, Never>?
    private var lastNotified: [String: Date] = [:]

    // MARK: Cycle de vie

    func start() {
        guard timer == nil else { return }
        if DemoMode.isEnabled { startDemo(); return }
        restoreTraffic()
        history?.prune()
        requestNotificationPermission()
        refreshSystemFacts()
        tick()
        scanCleanup()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        tickCount += 1
        let now = Date()
        let dt = min(10, max(0.5, now.timeIntervalSince(lastTick)))
        lastTick = now

        var snap = sampler.snapshot()
        snap.gpu = GPUSampler.sample()
        // La batterie varie lentement et son dictionnaire IOKit est volumineux : 9 s suffisent panneau fermé.
        if isUIVisible || tickCount % 3 == 1 || lastBattery == nil { lastBattery = BatterySampler.sample() }
        snap.battery = lastBattery
        var net = networkSampler.sample()
        net.latencyMs = latencyMs
        snap.network = net
        snap.diskIO = diskIOSampler.sample()

        // Les capteurs coûtent plus cher : toutes les 9 s, ou toutes les 3 s si l'onglet qui les affiche est ouvert.
        let sensorsVisible = !activeTabs.isDisjoint(with: [.performance, .battery])
        if now.timeIntervalSince(lastSensorRead) >= (sensorsVisible ? 2.5 : 9) {
            lastSensors = sensorSampler.sample()
            lastSensorRead = now
        }
        snap.sensors = lastSensors
        snapshot = snap
        refreshPublicIPWhileFlagShown(now: now)

        append(\.cpuHistory, snap.cpu.total)
        append(\.memoryHistory, snap.memory.usedFraction)
        if let gpu = snap.gpu { append(\.gpuHistory, gpu.utilization) }
        append(\.netDownHistory, net.downRate)
        append(\.netUpHistory, net.upRate)
        if let battery = snap.battery { append(\.batteryHistory, battery.percent / 100) }

        accumulateTraffic(net, dt: dt)
        record(snap)

        if now.timeIntervalSince(lastProcessRefresh) >= (isUIVisible ? 3 : 15) { refreshProcesses() }
        if now.timeIntervalSince(lastCleanupScan) > 1_800 { scanCleanup() }
        // Réglages du système : toutes les 10 min, ou toutes les 2 min si l'interface est ouverte.
        if now.timeIntervalSince(lastFactsRefresh) > (isUIVisible ? 120 : 600) { refreshSystemFacts() }
        if isUIVisible { refreshForActiveTabs(periodic: true) }
        updateRecommendations()
    }

    private func append(_ keyPath: ReferenceWritableKeyPath<AppState, [Double]>, _ value: Double) {
        self[keyPath: keyPath] = Array((self[keyPath: keyPath] + [value]).suffix(historyLength))
    }

    // MARK: Historique

    private func record(_ snap: SystemSnapshot) {
        let row = HistoryRow(
            timestamp: snap.date,
            cpu: snap.cpu.total, memory: snap.memory.usedFraction, gpu: snap.gpu?.utilization,
            netDown: snap.network?.downRate, netUp: snap.network?.upRate,
            diskRead: snap.diskIO?.readRate, diskWrite: snap.diskIO?.writeRate,
            battery: snap.battery?.percent, cpuTemp: snap.sensors?.cpu,
            power: snap.battery?.systemPower ?? snap.sensors?.systemPower
        )
        if let aggregated = accumulator.add(row) { history?.insert(aggregated) }
    }

    func clearHistory() {
        history?.clear()
        showToast(String(localized: "History cleared"))
    }

    // MARK: Trafic quotidien

    private static func dayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func restoreTraffic() {
        let d = UserDefaults.standard
        if d.string(forKey: "traffic.day") == trafficDay {
            trafficDown = d.double(forKey: "traffic.down")
            trafficUp = d.double(forKey: "traffic.up")
            todayTraffic = DailyTraffic(down: UInt64(trafficDown), up: UInt64(trafficUp))
        }
    }

    private func accumulateTraffic(_ net: NetworkStats, dt: TimeInterval) {
        let today = Self.dayKey()
        if today != trafficDay { trafficDay = today; trafficDown = 0; trafficUp = 0 }
        trafficDown += net.downRate * dt
        trafficUp += net.upRate * dt
        todayTraffic = DailyTraffic(down: UInt64(trafficDown), up: UInt64(trafficUp))

        if Date().timeIntervalSince(lastTrafficSave) > 60 {
            lastTrafficSave = Date()
            let d = UserDefaults.standard
            d.set(trafficDay, forKey: "traffic.day")
            d.set(trafficDown, forKey: "traffic.down")
            d.set(trafficUp, forKey: "traffic.up")
        }
    }

    // MARK: Rafraîchissements liés à l'onglet visible

    private func refreshForActiveTabs(periodic: Bool = false) {
        guard !DemoMode.isEnabled else { return }
        for tab in activeTabs { refresh(tab, periodic: periodic) }
    }

    private func refresh(_ tab: AppTab, periodic: Bool) {
        let now = Date()
        switch tab {
        case .overview, .cleanup:
            if !periodic, now.timeIntervalSince(lastCleanupScan) > 300 { scanCleanup() }
        case .performance:
            if smartStatus == nil { refreshSMART() }
        case .network:
            if now.timeIntervalSince(lastNetworkProcessRefresh) >= (periodic ? 6 : 0) { refreshNetworkProcesses() }
            if UserDefaults.standard.bool(forKey: SettingsKey.latency), now.timeIntervalSince(lastLatency) >= 10 { refreshLatency() }
            if now.timeIntervalSince(lastVPNRefresh) >= (periodic ? 10 : 2) { refreshVPN() }
            refreshPublicIP()
        case .battery:
            if hasBattery, now.timeIntervalSince(lastEnergyRefresh) >= (periodic ? 15 : 0) { refreshEnergy() }
        case .history:
            break
        }
    }

    private func refreshSMART() {
        guard !smartInFlight else { return }
        smartInFlight = true
        Task { [weak self] in
            let status = await Task.detached(priority: .utility) { DiskIOSampler.smartStatus() }.value
            self?.smartInFlight = false
            self?.smartStatus = status ?? "Unavailable"
        }
    }

    private func refreshLatency() {
        lastLatency = Date()
        Task { [weak self] in
            let ms = await Task.detached(priority: .utility) { NetworkSampler.ping(host: "1.1.1.1") }.value
            self?.latencyMs = ms
        }
    }

    // MARK: VPN et IP publique

    /// Détection locale (route par défaut, services VPN de macOS, interfaces de tunnel) : aucune requête réseau.
    /// `acceptingSettled` : l'appel vient du moniteur, qui a déjà attendu le délai de calme ; l'empreinte relue ensuite compte comme stable.
    private func refreshVPN(acceptingSettled: Bool = false) {
        lastVPNRefresh = watching.clock()
        let names = processes.map(\.name)
        let detect = watching.detectVPN
        vpnDetectionsInFlight += 1
        vpnRefreshTask = Task { [weak self] in
            let status = await Task.detached(priority: .utility) { detect(names) }.value
            guard let self else { return }
            self.vpnDetectionsInFlight -= 1
            self.vpn = status
            if acceptingSettled { self.settler.accept(self.fingerprintNow().text) }
            self.refreshPublicIP(now: self.watching.clock())       // un VPN qui se connecte ou se coupe change l'IP : on la relit
        }
    }

    var publicIPEnabled: Bool { publicIPSetting() }

    /// Interroge le service tiers seulement si l'utilisateur l'a activé, et seulement quand c'est utile : onglet Réseau ouvert,
    /// ou drapeau affiché dans la barre de menus (ADR 0011). Au plus toutes les 5 min, ou quand la connexion change
    /// (autre réseau, VPN allumé/éteint). `force` = bouton « Actualiser » ou interrupteur des réglages.
    /// La décision tient entière dans `PublicIPLookupPolicy.shouldLookUp` (pure, temps injecté).
    func refreshPublicIP(force: Bool = false, now: Date = Date()) {
        updateNetworkMonitor()
        let (fingerprint, complete) = fingerprintNow()
        adoptCompleteBaseline(fingerprint, complete: complete)
        let hadFingerprint = !publicIPFingerprint.isEmpty
        let settled = settler.observe(fingerprint, now: now)
        let changed = PublicIPLookupPolicy.fingerprintChanged(fingerprint, publicIPFingerprint, settled, forcedChange, activeTabs.contains(.network))
        let inputs = PublicIPLookupPolicy.Inputs(
            settingOn: publicIPSetting(), networkItemShown: networkItemShown(snapshot), networkTabOpen: activeTabs.contains(.network),
            demo: DemoMode.isEnabled || demo, state: publicIPState, force: force, fingerprintChanged: changed,
            lastSuccess: publicIP?.fetchedAt, lastAttempt: lastPublicIPAttempt, lastFailure: lastPublicIPFailure,
            lastChangeTriggeredLookup: lastChangeTriggeredLookup, now: now)
        guard PublicIPLookupPolicy.shouldLookUp(inputs) else { return }

        // La toute première recherche du drapeau attend la fin de la détection du VPN (plafonnée), pour partir avec l'empreinte complète.
        if PublicIPLookupPolicy.mustWaitForFirstFingerprint(
            hadBaseline: hadFingerprint, vpnDetectionPending: vpn == nil && vpnDetectionsInFlight > 0, tabOpen: inputs.networkTabOpen,
            force: force, waitingSince: firstLookupWaitStart, now: now) {
            if firstLookupWaitStart == nil { firstLookupWaitStart = now; watching.log("baseline: waiting for the VPN detection") }
            return
        }
        firstLookupWaitStart = nil
        let reason = PublicIPLookupPolicy.reason(inputs, wake: forcedChange, hadFingerprint: hadFingerprint)
        watching.log("lookup: \(reason.rawValue)")
        // Une recherche déclenchée par un changement attend sa confirmation ; toute autre efface l'attente (une seule confirmation, jamais deux).
        lastChangeTriggeredLookup = reason.isChangeTriggered ? now : nil
        forcedChange = false
        lastPublicIPAttempt = now
        publicIPFingerprint = fingerprint
        publicIPBaselineComplete = complete
        publicIPState = .loading
        publicIPGeneration += 1
        let generation = publicIPGeneration
        let fetch = publicIPFetch
        publicIPLookupTask = Task { [weak self] in
            do {
                let info = try await fetch()
                guard let self else { return }
                // Réglage coupé (ou oubli) pendant la recherche : la réponse est jetée, rien n'est gardé, même en mémoire.
                guard generation == self.publicIPGeneration, self.publicIPSetting() else { return }
                self.publicIP = info
                // Si l'empreinte complète a remplacé la base pendant la recherche, la réponse lui est rattachée.
                self.publicIPInfoFingerprint = (!complete && self.publicIPBaselineComplete) ? self.publicIPFingerprint : fingerprint
                self.lastPublicIPFailure = nil
                self.publicIPState = .idle
            } catch {
                guard let self, generation == self.publicIPGeneration, self.publicIPSetting() else { return }
                self.lastPublicIPFailure = now
                self.lastChangeTriggeredLookup = nil              // pas de réponse à confirmer
                self.publicIPState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Moniteur de changements de réseau (SL25)

    /// Crée le moniteur quand le drapeau ou l'onglet Réseau en a besoin, l'arrête sinon (réglage coupé, bloc masqué, démo) et oublie
    /// ce qu'il avait en attente. Appelé à chaque mesure, à chaque décision et quand on coupe le réglage.
    func updateNetworkMonitor() {
        let wanted = PublicIPLookupPolicy.monitorWanted(
            settingOn: publicIPSetting(), demo: DemoMode.isEnabled || demo,
            networkItemShown: networkItemShown(snapshot), networkTabOpen: activeTabs.contains(.network))
        if wanted {
            guard networkMonitor == nil else { return }
            // Le moniteur appartient à AppState ; son rappel ne retient pas AppState.
            let monitor = NetworkChangeMonitor(source: watching.makeSource(), scheduler: watching.scheduler) { [weak self] reason in
                self?.networkEventSettled(reason)
            }
            if monitor.start() { networkMonitor = monitor }
        } else {
            networkMonitor?.stop()
            networkMonitor = nil
            forcedChange = false
            lastChangeTriggeredLookup = nil
        }
    }

    /// Le moniteur a vu une rafale d'événements puis le calme. On relit d'abord le VPN (local), puis la décision habituelle juge ;
    /// un réveil force un changement. Le moniteur n'appelle jamais le service lui-même.
    private func networkEventSettled(_ reason: NetworkChangeReason) {
        updateNetworkMonitor()
        guard networkMonitor != nil else { return }
        watching.log("network event: \(reason == .wake ? "wake" : "configuration")")
        if reason == .wake { forcedChange = true }
        refreshVPN(acceptingSettled: true)
    }

    /// Chaque mesure (3 s) : tant que le drapeau est affiché, la recherche reste à jour même onglet Réseau fermé.
    /// Le minuteur de la mesure est le seul : aucun autre fil, aucune autre horloge.
    func refreshPublicIPWhileFlagShown(now: Date) {
        updateNetworkMonitor()
        guard !(DemoMode.isEnabled || demo), publicIPSetting(), networkItemShown(snapshot) else { return }
        // La détection du VPN est locale (aucune requête) ; sans elle, un VPN qui change ne serait vu qu'onglet Réseau ouvert.
        if now.timeIntervalSince(lastVPNRefresh) >= 10 { refreshVPN() }
        refreshPublicIP(now: now)
    }

    /// L'empreinte de la connexion maintenant : adresse locale, VPN, et (SL25) les signaux locaux. En démo, aucun signal n'est lu.
    /// Elle est **complète** quand la détection du VPN a rendu au moins une fois et que des signaux ont été lus ; sinon c'est une première
    /// ébauche (au démarrage, `vpn` est encore nil quand la première recherche est décidée), et le passage à la complète n'est pas un changement.
    private func fingerprintNow() -> (text: String, complete: Bool) {
        let signals = (DemoMode.isEnabled || demo) ? NetworkSignals.empty : watching.readSignals()
        let text = PublicIPLookupPolicy.fingerprint(localIP: snapshot?.network?.localIP, vpn: vpn, signals: signals)
        return (text, vpn != nil && !signals.isEmpty)
    }

    /// Une base prise incomplète devient la complète, sans recherche : la réponse reçue vient de la vraie route, seule son étiquette change.
    private func adoptCompleteBaseline(_ fingerprint: String, complete: Bool) {
        guard complete, !publicIPBaselineComplete, !publicIPFingerprint.isEmpty else { return }
        if publicIP != nil, publicIPInfoFingerprint == publicIPFingerprint { publicIPInfoFingerprint = fingerprint }
        publicIPFingerprint = fingerprint
        publicIPBaselineComplete = true
        watching.log("baseline: complete fingerprint adopted, no lookup")
    }

    /// La réponse connue vient-elle de la connexion actuelle ? (Sinon le drapeau ne s'affiche pas, en attendant la nouvelle.)
    var publicIPMatchesNetwork: Bool { publicIP != nil && publicIPInfoFingerprint == fingerprintNow().text }

    /// Appelé quand l'utilisateur coupe l'option : on n'en garde aucune trace, même en mémoire.
    func forgetPublicIP() {
        guard !DemoMode.isEnabled else { return }
        publicIPGeneration += 1                  // une recherche en cours est abandonnée : sa réponse sera jetée
        publicIP = nil
        publicIPState = .idle
        publicIPFingerprint = ""
        publicIPInfoFingerprint = ""
        publicIPBaselineComplete = false
        firstLookupWaitStart = nil
        lastPublicIPFailure = nil
        settler = FingerprintSettler()
        updateNetworkMonitor()                   // le réglage est coupé : le moniteur s'arrête tout de suite et ses attentes sont oubliées
    }

    private func refreshNetworkProcesses() {
        guard !networkRefreshInFlight else { return }
        networkRefreshInFlight = true
        lastNetworkProcessRefresh = Date()
        Task { [weak self] in
            let rows = await Task.detached(priority: .utility) { NetworkSampler.processTraffic() }.value
            guard let self else { return }
            self.networkRefreshInFlight = false
            self.networkProcesses = self.aggregate(rows.map { ($0.pid, $0.name, $0.down, $0.up) })
        }
    }

    private func refreshEnergy() {
        guard !energyRefreshInFlight else { return }
        energyRefreshInFlight = true
        lastEnergyRefresh = Date()
        Task { [weak self] in
            let impacts = await Task.detached(priority: .utility) { EnergySampler.impactByPID() }.value
            guard let self else { return }
            self.energyRefreshInFlight = false
            let byPID = Dictionary(uniqueKeysWithValues: self.processes.flatMap { g in g.pids.map { ($0, g) } })
            var totals: [String: EnergyEntry] = [:]
            for (pid, impact) in impacts {
                let group = byPID[pid]
                let name = group?.name ?? String(localized: "Process \(pid)")
                var entry = totals[name] ?? EnergyEntry(name: name, appPath: group?.appPath, impact: 0)
                entry.impact += impact
                totals[name] = entry
            }
            self.energyEntries = totals.values.filter { $0.impact >= 1 }.sorted { $0.impact > $1.impact }.prefix(6).map { $0 }
        }
    }

    /// Regroupe des lignes par processus sous le nom de leur application (les helpers rejoignent leur app).
    private func aggregate(_ rows: [(pid: Int32, name: String, down: Double, up: Double)]) -> [NetworkProcess] {
        let byPID = Dictionary(uniqueKeysWithValues: processes.flatMap { g in g.pids.map { ($0, g) } })
        var totals: [String: NetworkProcess] = [:]
        for row in rows {
            let group = byPID[row.pid]
            let name = group?.name ?? row.name
            var entry = totals[name] ?? NetworkProcess(name: name, appPath: group?.appPath, down: 0, up: 0)
            entry.down += row.down
            entry.up += row.up
            totals[name] = entry
        }
        return totals.values.sorted { $0.total > $1.total }.prefix(8).map { $0 }
    }

    // MARK: Processus

    func refreshProcesses() {
        guard !DemoMode.isEnabled, !processRefreshInFlight else { return }
        processRefreshInFlight = true
        lastProcessRefresh = Date()
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { () -> ([ProcessGroup], [Int32: ProcessIOSampler.Counters]) in
                let groups = SystemSampler.processGroups()
                return (groups, ProcessIOSampler.counters(for: groups.flatMap(\.pids)))
            }.value
            guard let self else { return }
            self.processRefreshInFlight = false

            var groups = Self.markQuittable(result.0)
            self.applyIORates(&groups, counters: result.1)
            self.processes = groups
            self.trendTracker.record(groups)
            self.leaks = self.trendTracker.suspects(among: groups)
            self.updateRecommendations()
        }
    }

    private func applyIORates(_ groups: inout [ProcessGroup], counters: [Int32: ProcessIOSampler.Counters]) {
        let now = Date()
        defer { previousIO = (now, counters) }
        guard let previous = previousIO else { return }
        let dt = now.timeIntervalSince(previous.date)
        guard dt > 0.5 else { return }
        for i in groups.indices {
            var read = 0.0, written = 0.0
            for pid in groups[i].pids {
                guard let c = counters[pid], let p = previous.counters[pid], c.read >= p.read, c.written >= p.written else { continue }
                read += Double(c.read - p.read)
                written += Double(c.written - p.written)
            }
            groups[i].ioReadRate = read / dt
            groups[i].ioWriteRate = written / dt
        }
    }

    private static func markQuittable(_ groups: [ProcessGroup]) -> [ProcessGroup] {
        let selfPath = Bundle.main.bundleURL.path
        let quittable = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != "com.apple.finder" }
                .compactMap { $0.bundleURL?.path }
                .filter { $0 != selfPath }
        )
        return groups.map { group in
            var g = group
            if let path = g.appPath { g.canQuit = quittable.contains(path) }
            return g
        }
    }

    func top(by sort: ProcessSort, count: Int = 6) -> [ProcessGroup] {
        let key: (ProcessGroup) -> Double = {
            switch sort {
            case .cpu: $0.cpu
            case .memory: Double($0.memory)
            case .disk: $0.ioWriteRate + $0.ioReadRate
            }
        }
        return Array(processes.sorted { key($0) > key($1) }.prefix(count))
    }

    // MARK: Recommandations

    private func updateRecommendations() {
        guard let snapshot else { return }
        let recent = cpuHistory.suffix(10)
        let input = EngineInput(
            snapshot: snapshot,
            processes: processes,
            recentCPUAverage: recent.isEmpty ? 0 : recent.reduce(0, +) / Double(recent.count),
            recentCPUSamples: recent.count,
            cleanupSizes: cleanupSizes,
            leaks: leaks
        )
        let new = RecommendationEngine.evaluate(input)
        if new != recommendations { recommendations = new }
        notifyIfNeeded(new)
        updateAdvice()
    }

    // MARK: Conseils de réglage

    private func refreshSystemFacts() {
        guard !DemoMode.isEnabled, !factsRefreshInFlight else { return }
        factsRefreshInFlight = true
        lastFactsRefresh = Date()
        Task { [weak self] in
            let facts = await Task.detached(priority: .utility) { AdviceProbe.collect() }.value
            guard let self else { return }
            self.factsRefreshInFlight = false
            if facts != self.systemFacts { self.systemFacts = facts }
            self.updateAdvice()
        }
    }

    /// Version de macOS en attente d'installation, si elle est plus récente que celle du Mac.
    var pendingMacOSUpdate: String? {
        guard let pending = systemFacts.pendingUpdateVersion, AdviceEngine.isVersion(pending, newerThan: Self.osVersion) else { return nil }
        return pending
    }

    private var dismissedAdvice: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.dismissedAdviceKey) ?? [])
    }

    private func updateAdvice() {
        let all = AdviceEngine.evaluate(AdviceInput(
            facts: systemFacts, battery: snapshot?.battery, disk: snapshot?.disk,
            processes: processes, osVersion: Self.osVersion
        ))
        let dismissed = dismissedAdvice
        let visible = all.filter { !dismissed.contains($0.id) }
        if visible != advice { advice = visible }
        if dismissed.count != dismissedAdviceCount { dismissedAdviceCount = dismissed.count }
    }

    /// « Ignorer » : le conseil ne reviendra plus (jusqu'à « Réafficher les conseils ignorés » dans les réglages).
    func dismissAdvice(_ item: Advice) {
        var dismissed = dismissedAdvice
        dismissed.insert(item.id)
        UserDefaults.standard.set(Array(dismissed).sorted(), forKey: Self.dismissedAdviceKey)
        updateAdvice()
    }

    func restoreDismissedAdvice() {
        UserDefaults.standard.removeObject(forKey: Self.dismissedAdviceKey)
        updateAdvice()
        showToast(String(localized: "Tips shown again"))
    }

    func perform(_ action: Advice.Action) {
        switch action {
        case .openSettings(let url):
            if let url = URL(string: url) { NSWorkspace.shared.open(url) }
        case .showStartupItems:
            activeTab = .cleanup
            requestedCleanupRoute = .startup
        case .openActivityMonitor:
            perform(RecommendedAction.openActivityMonitor)
        }
    }

    var worstSeverity: Severity? { recommendations.map(\.severity).max() }

    // MARK: Actions

    func perform(_ action: RecommendedAction) {
        switch action {
        case .cleanup(let kind): cleanup([kind])
        case .quickCleanup: cleanup(CleanupKind.allCases.filter(\.includedInQuickClean))
        case .quitApp(let path, let name): quitApp(path: path, name: name)
        case .openActivityMonitor:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        case .openStorageSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func quitApp(path: String, name: String) {
        if demo {
            // Démo : les chemins (Safari, Xcode…) sont ceux de vraies apps qui tournent peut-être : on n'en quitte aucune.
            showToast(String(localized: "Quit request sent to \(name)"))
            return
        }
        if terminateApp(path) {
            showToast(String(localized: "Quit request sent to \(name)"))
            Task { try? await Task.sleep(for: .seconds(2)); refreshProcesses() }
        } else {
            showToast(String(localized: "Could not quit \(name)"))
        }
    }

    // MARK: Nettoyage

    func scanCleanup() {
        guard !demo else { return }
        lastCleanupScan = Date()
        Task { [weak self] in
            let sizes = await Task.detached(priority: .utility) { () -> [CleanupKind: UInt64?] in
                var sizes: [CleanupKind: UInt64?] = [:]
                for kind in CleanupKind.allCases { sizes[kind] = .some(CleanupService.size(of: kind)) }
                return sizes
            }.value
            self?.cleanupSizes = sizes
            self?.updateRecommendations()
        }
    }

    /// Octets récupérables par le nettoyage rapide.
    var quickCleanReclaimable: UInt64 {
        CleanupKind.quickCleanTotal(sizes: cleanupSizes)
    }

    /// Demande confirmation puis nettoie (le déroulé est dans `CacheCleanupFlow`, rien n'est supprimé en mode démo).
    func cleanup(_ kinds: [CleanupKind]) {
        guard !kinds.isEmpty, busyKinds.isDisjoint(with: kinds) else { return }

        guard let outcome = CacheCleanupFlow.run(
            kinds: kinds, sizes: cleanupSizes, demo: demo,
            confirm: confirm,
            clean: cleanAction,
            willStart: { [weak self] in self?.busyKinds.formUnion(kinds) }
        ) else { return }

        Task { [weak self] in
            let message = await outcome.value
            guard let self else { return }
            self.busyKinds.subtract(kinds)
            self.showToast(message)
            self.scanCleanup()
        }
    }

    /// Boîte de confirmation partagée par toutes les actions destructrices.
    /// Retour annule, Échap aussi : le bouton destructeur n'a aucun raccourci clavier (R8).
    static func confirm(title: String, message: String, button: String, critical: Bool = false) -> Bool {
        let alert = makeConfirmationAlert(title: title, message: message, button: button, critical: critical)
        NSApp.activate(ignoringOtherApps: true)
        return confirmationResult(for: alert.runModal())
    }

    /// Construit l'alerte sans l'afficher (testable). « Cancel » est en premier : c'est le bouton par défaut (Retour).
    /// AppKit lie Échap au bouton intitulé « Cancel ». `critical` ne change que le style de l'alerte.
    static func makeConfirmationAlert(title: String, message: String, button: String, critical: Bool) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let cancel = alert.addButton(withTitle: String(localized: "Cancel"))
        cancel.keyEquivalent = "\r"
        let destructive = alert.addButton(withTitle: button)
        destructive.keyEquivalent = ""
        alert.alertStyle = critical ? .warning : .informational
        return alert
    }

    /// Seul le second bouton (l'action destructrice) confirme ; toute autre réponse annule.
    static func confirmationResult(for response: NSApplication.ModalResponse) -> Bool {
        response == .alertSecondButtonReturn
    }

    // MARK: Toast

    func showToast(_ message: String) {
        toast = message
        // Une seule annonce par toast, ici et non dans les vues : le panneau et la fenêtre peuvent être ouverts ensemble.
        if let text = ToastPresentation.announcement(for: message) { announce(text) }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: ToastPresentation.visibleDuration)
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    // MARK: Notifications

    private var canUseNotifications: Bool {
        !DemoMode.isEnabled && Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    private func requestNotificationPermission() {
        guard canUseNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyIfNeeded(_ recs: [Recommendation]) {
        guard canUseNotifications,
              UserDefaults.standard.bool(forKey: SettingsKey.notifications) else { return }
        for rec in recs where rec.severity == .critical {
            // Au plus une notification par type de problème toutes les 2 h.
            if let last = lastNotified[rec.id], Date().timeIntervalSince(last) < 7_200 { continue }
            lastNotified[rec.id] = Date()
            let content = UNMutableNotificationContent()
            content.title = rec.title
            content.body = rec.detail
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: rec.id, content: content, trigger: nil)
            )
        }
    }
}

enum ProcessSort: String, CaseIterable, Identifiable {
    case cpu = "CPU", memory = "Memory", disk = "Disk"
    var id: String { rawValue }

    /// Libellé affiché (traduit) ; `rawValue` ne sert que d'identifiant.
    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: String(localized: "Memory")
        case .disk: String(localized: "Disk")
        }
    }
}

// MARK: - Demo mode

extension AppState {
    /// Fills the state with made-up values (see `DemoMode`). No timer, no measurement: the numbers stay still.
    func startDemo() {
        let snap = DemoData.snapshot()
        snapshot = snap
        cpuHistory = DemoData.curve(last: snap.cpu.total, spread: 0.12)
        memoryHistory = DemoData.curve(last: snap.memory.usedFraction, spread: 0.03, phase: 1)
        gpuHistory = DemoData.curve(last: snap.gpu?.utilization ?? 0, spread: 0.1, phase: 2)
        netDownHistory = DemoData.curve(last: 2_000_000, spread: 1_400_000, phase: 3)
        netUpHistory = DemoData.curve(last: 300_000, spread: 220_000, phase: 4)
        batteryHistory = DemoData.curve(last: 0.62, spread: 0.02, phase: 5)
        processes = DemoData.processes
        networkProcesses = DemoData.networkProcesses
        energyEntries = DemoData.energyEntries
        leaks = DemoData.leaks
        cleanupSizes = DemoData.cleanupSizes
        smartStatus = "Verified"
        latencyMs = 12
        todayTraffic = DemoData.traffic
        vpn = DemoData.vpn
        publicIP = DemoData.publicIP()
        systemFacts = DemoData.facts()
        recommendations = RecommendationEngine.evaluate(EngineInput(
            snapshot: snap, processes: processes, recentCPUAverage: snap.cpu.total, recentCPUSamples: 10,
            cleanupSizes: cleanupSizes, leaks: leaks
        ))
        updateAdvice()
    }
}
