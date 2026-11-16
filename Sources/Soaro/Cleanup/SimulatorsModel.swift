import Foundation

/// Modèle de l'outil « Simulators and emulators » (R3, R6) : LECTURE SEULE, rien ne peut être supprimé ici (SL9).
///
/// - Le listage (une commande) tourne dans une tâche détachée (priorité utilitaire), jamais sur l'acteur principal,
///   jamais dans le tick de 3 secondes. Un `CancelToken` annule le scan : le résultat d'un scan annulé n'est jamais appliqué.
/// - Le lanceur n'a PAS de valeur par défaut (ADR 0009) : il est construit par `CleanupTab`, et nulle part ailleurs.
/// - La détection de l'outil ne lance rien ; le lanceur n'est appelé que si `simctl` est sur le disque ET `xcrun` présent.
@MainActor
final class SimulatorsModel: ObservableObject {
    enum Failure: Equatable {
        /// Outil absent, commande refusée ou en échec, sortie illisible : un seul message neutre.
        case couldNotRead
        /// `simctl` n'a pas répondu dans le délai.
        case notAnswering
    }

    enum Phase: Equatable {
        case notScanned
        /// Lecture de la liste en cours.
        case listing
        case failed(Failure)
        /// Le scan a réussi mais il n'y a aucun appareil du tout.
        case empty
        /// Des appareils sont listés (couvre la mesure des tailles puis la fin).
        case listed
    }

    @Published private(set) var phase: Phase = .notScanned
    /// Lignes affichées (appareils d'au moins 100 Mo, ou de taille encore inconnue). Tant que les tailles arrivent : ordre du
    /// listage (nom, puis système, puis UDID) ; une fois la dernière arrivée : par taille décroissante (égalité : nom, UDID).
    @Published private(set) var rows: [DeviceSuggestions.Row] = []
    /// Les tailles sont en cours de mesure (un dossier à la fois).
    @Published private(set) var isMeasuring = false
    /// Appareils mesurés à moins de 100 Mo : comptés, pas listés.
    @Published private(set) var hiddenSmallCount = 0
    @Published private(set) var hiddenSmallSize: UInt64 = 0
    /// Limite d'inactivité choisie (menu) : provisoire (`DeviceSuggestions.defaultLimitDays`), JAMAIS mémorisée entre deux sessions.
    @Published private(set) var limitDays = DeviceSuggestions.defaultLimitDays
    /// Appareils cochés (UDID).
    @Published private(set) var selected: Set<String> = []
    /// Le dernier calcul n'a rien pré-sélectionné.
    @Published private var nothingPreSelected = true
    /// Tailles déjà mesurées, par UDID.
    @Published private var sizes: [String: UInt64] = [:]
    /// Tous les appareils du listage, sans taille.
    private var devices: [SimulatorDevice] = []

    /// La tâche du scan en cours ou du dernier scan : les tests l'attendent (`await model.scanTask?.value`) sans dormir.
    private(set) var scanTask: Task<Void, Never>?

    private var token: CancelToken?
    private let runner: CommandRunner
    private let detect: () -> SimulatorToolDetection
    private let locateXcrun: ([String]) -> String?
    let home: URL
    private let now: () -> Date
    private let measure: (URL) -> UInt64
    let demo: Bool
    private var notify: (String) -> Void

    /// - Parameters:
    ///   - runner: sans valeur par défaut (ADR 0009).
    ///   - detect: détection de l'outil sur le disque (ne lance rien), appelée hors de l'acteur principal à chaque scan.
    ///   - locateXcrun: trouve `xcrun` par chemin absolu (`ToolLocator`).
    ///   - measure: taille allouée d'un dossier.
    init(runner: CommandRunner,
         detect: @escaping () -> SimulatorToolDetection = { SimulatorToolDetector.detect(home: URL(fileURLWithPath: NSHomeDirectory())) },
         locateXcrun: @escaping ([String]) -> String? = { ToolLocator.firstExecutable(in: $0) },
         home: URL = URL(fileURLWithPath: NSHomeDirectory()),
         now: @escaping () -> Date = Date.init,
         measure: @escaping (URL) -> UInt64 = { CleanupService.allocatedSize(of: $0) },
         demo: Bool = DemoMode.isEnabled,
         notify: @escaping (String) -> Void) {
        self.runner = runner
        self.detect = detect
        self.locateXcrun = locateXcrun
        self.home = home
        self.now = now
        self.measure = measure
        self.demo = demo
        self.notify = notify
    }

    func setNotify(_ notify: @escaping (String) -> Void) { self.notify = notify }

    /// Taille mesurée d'une ligne, `nil` tant qu'elle ne l'est pas (la vue affiche « … »).
    func size(of row: DeviceSuggestions.Row) -> UInt64? { sizes[row.device.device.udid] }

    /// Valeurs du menu de limite : 30, 60, 90, 180 jours ; la limite par défaut y est ajoutée (en ordre) si elle n'y est pas.
    static func limitChoices(defaultDays: Int = DeviceSuggestions.defaultLimitDays) -> [Int] {
        Set([30, 60, 90, 180, defaultDays]).sorted()
    }

    /// Bandeau « Nothing to suggest… » : au moins une ligne listée, rien de pré-sélectionné, et les tailles sont toutes arrivées.
    var showsNothingToSuggest: Bool { !isMeasuring && !rows.isEmpty && nothingPreSelected }

    var selectedCount: Int { rows.filter { selected.contains($0.device.device.udid) }.count }
    /// Taille des appareils cochés (tailles connues seulement).
    var selectedSize: UInt64 {
        rows.reduce(0) { $0 + (selected.contains($1.device.device.udid) ? (sizes[$1.device.device.udid] ?? 0) : 0) }
    }

    /// Coche ou décoche une ligne ; un appareil en cours d'exécution ne se coche jamais.
    func toggle(_ row: DeviceSuggestions.Row) {
        guard !row.isRunning else { return }
        let udid = row.device.device.udid
        if selected.contains(udid) { selected.remove(udid) } else { selected.insert(udid) }
    }

    /// Change la limite : la sélection devient TOUT DE SUITE la suggestion de cette limite (les choix manuels sont remplacés),
    /// sans nouveau scan ni appel au lanceur.
    func setLimit(_ days: Int) {
        limitDays = days
        recompute(selection: .replace)
    }

    /// Somme des tailles mesurées des appareils listés.
    var measuredSizeTotal: UInt64 { rows.reduce(0) { $0 + (sizes[$1.device.device.udid] ?? 0) } }

    /// Message neutre de l'état courant (jamais de code de sortie, de sortie d'erreur ni de chemin), `nil` sinon.
    var message: String? {
        switch phase {
        case .listing: String(localized: "Looking for simulators and emulators…")
        case .failed(.couldNotRead): String(localized: "Could not read the iOS Simulators.")
        case .failed(.notAnswering): String(localized: "Xcode’s simulator service did not answer. Try again in a moment.")
        case .empty: String(localized: "No simulator or emulator found.")
        case .notScanned, .listed: nil
        }
    }

    // MARK: Scan

    /// Lance (ou relance : annule le scan en cours) la lecture de la liste, hors de l'acteur principal.
    func scan() {
        token?.cancel()
        let token = CancelToken()
        self.token = token

        phase = .listing
        reset()

        let runner = runner, detect = detect, locateXcrun = locateXcrun, measure = measure, home = home
        scanTask = Task { [weak self] in
            let listing = await Task.detached(priority: .utility) { () -> SimulatorListing in
                let detection = detect()
                let xcrun = ToolLocator.simulatorXcrunPath(detection: detection, locate: locateXcrun)
                return SimulatorScanner.list(runner: runner, xcrunPath: xcrun)
            }.value
            guard let self, !token.isCancelled else { return }
            guard self.apply(listing) else { return }

            // Les tailles arrivent une à une (un dossier à la fois, hors de l'acteur principal), comme dans le désinstalleur.
            // Dans l'ordre d'affichage (haut en bas).
            for device in self.rows.map(\.device.device) {
                if token.isCancelled { return }
                // `parse` a validé l'UDID : `deviceFolder` ne peut pas rendre `nil` ici.
                let folder = SimulatorScanner.deviceFolder(udid: device.udid, home: home)
                let size = await Task.detached(priority: .utility) { folder.map(measure) ?? 0 }.value
                if token.isCancelled { return }
                self.sizes[device.udid] = size
                self.recompute(selection: .prune)
            }
            if token.isCancelled { return }
            self.isMeasuring = false
            self.recompute(selection: .prune)
        }
    }

    /// Bouton Retour : annule le scan en cours ; un scan inachevé n'est pas conservé (la prochaine ouverture relance).
    func cancel() {
        token?.cancel()
        scanTask?.cancel()
        if phase == .listing || isMeasuring { phase = .notScanned; reset() }
    }

    private func reset() {
        rows = []
        devices = []
        sizes = [:]
        selected = []
        nothingPreSelected = true
        isMeasuring = false
        hiddenSmallCount = 0
        hiddenSmallSize = 0
    }

    /// Recalcule les lignes et le pied de page : un appareil dont la taille n'est pas connue compte comme « assez gros »
    /// (il reste listé), les autres suivent `DeviceSuggestions.suggest`.
    private enum SelectionUpdate {
        /// La sélection devient la pré-sélection du calcul (arrivée de la liste, changement de limite).
        case replace
        /// Les choix de l'utilisateur sont gardés ; seuls sortent les appareils qui ne sont plus listés (mesurés petits).
        case prune
    }

    private func recompute(selection: SelectionUpdate) {
        let sized = devices.map { SizedSimulator(device: $0, size: sizes[$0.udid] ?? DeviceSuggestions.smallDeviceThreshold) }
        let result = DeviceSuggestions.suggest(sized, now: now(), limitDays: limitDays)
        rows = isMeasuring ? result.rows.sorted(by: Self.listingOrder) : result.rows
        nothingPreSelected = result.preSelectedCount == 0
        switch selection {
        case .replace: selected = Set(result.rows.filter(\.isPreSelected).map(\.device.device.udid))
        case .prune: selected.formIntersection(result.rows.filter { !$0.isRunning }.map(\.device.device.udid))
        }
        hiddenSmallCount = result.hiddenSmallCount
        hiddenSmallSize = result.hiddenSmallSize
    }

    /// Ordre du listage : nom, puis système, puis UDID.
    private static func listingOrder(_ a: DeviceSuggestions.Row, _ b: DeviceSuggestions.Row) -> Bool {
        let (x, y) = (a.device.device, b.device.device)
        let (nx, ny) = (x.name.lowercased(), y.name.lowercased())
        if nx != ny { return nx < ny }
        let (sx, sy) = (SimulatorPresentation.systemLabel(runtimeIdentifier: x.runtimeIdentifier),
                        SimulatorPresentation.systemLabel(runtimeIdentifier: y.runtimeIdentifier))
        if sx != sy { return sx < sy }
        return x.udid < y.udid
    }

    /// - Returns: `true` quand des appareils sont listés (les tailles peuvent alors être mesurées).
    private func apply(_ listing: SimulatorListing) -> Bool {
        switch listing.status {
        case .ok:
            if listing.devices.isEmpty {
                phase = .empty
                return false
            }
            devices = listing.devices
            phase = .listed
            isMeasuring = true
            recompute(selection: .replace)
            return true
        case .timedOut:
            phase = .failed(.notAnswering)
        case .toolNotFound, .commandFailed, .outputNotReadable:
            phase = .failed(.couldNotRead)
        }
        return false
    }
}
