import Foundation

/// Modèle de l'outil « Simulators and emulators » (R3, R4, R5, R6, R8).
///
/// - Le listage (une commande) tourne dans une tâche détachée (priorité utilitaire), jamais sur l'acteur principal,
///   jamais dans le tick de 3 secondes. Un `CancelToken` annule le scan : le résultat d'un scan annulé n'est jamais appliqué.
/// - Le lanceur n'a PAS de valeur par défaut (ADR 0009) : il est construit par `CleanupTab`, et nulle part ailleurs.
/// - La détection de l'outil ne lance rien ; le lanceur n'est appelé que si `simctl` est sur le disque ET `xcrun` présent.
/// - Suppression (SL9) : après confirmation (`ConfirmHandler` injecté, sans valeur par défaut), un lot tourne dans une tâche
///   détachée (priorité utilisateur) : pour chaque appareil, `SimulatorScanner.remove` (revérification de l'état, portée, mesure
///   avant et après, `xcrun simctl delete`). Le toast dit l'espace réellement libéré ; la liste est relue ensuite.
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
    /// Limite d'inactivité choisie (menu) : `DeviceSuggestions.defaultLimitDays` au départ, JAMAIS mémorisée entre deux sessions.
    @Published private(set) var limitDays = DeviceSuggestions.defaultLimitDays
    /// Appareils cochés (UDID).
    @Published private(set) var selected: Set<String> = []
    /// Le dernier calcul n'a rien pré-sélectionné.
    @Published private var nothingPreSelected = true
    /// Tailles déjà mesurées, par UDID.
    @Published private var sizes: [String: UInt64] = [:]
    /// Tous les appareils du listage, sans taille.
    private var devices: [SimulatorDevice] = []
    /// Une suppression est en cours (le lot tourne, ou la liste est relue juste après).
    @Published private(set) var isDeleting = false

    /// La tâche du scan en cours ou du dernier scan : les tests l'attendent (`await model.scanTask?.value`) sans dormir.
    private(set) var scanTask: Task<Void, Never>?
    /// La tâche de la suppression en cours ou de la dernière (lot, toast, puis nouveau scan) : les tests l'attendent sans dormir.
    private(set) var deleteTask: Task<Void, Never>?
    private var deleteToken: CancelToken?

    private var token: CancelToken?
    private let runner: CommandRunner
    private let detect: () -> SimulatorToolDetection
    private let locateXcrun: ([String]) -> String?
    let home: URL
    private let now: () -> Date
    private let measure: (URL) -> UInt64
    let demo: Bool
    private var notify: (String) -> Void
    private let confirm: ConfirmHandler

    /// - Parameters:
    ///   - runner: sans valeur par défaut (ADR 0009).
    ///   - detect: détection de l'outil sur le disque (ne lance rien), appelée hors de l'acteur principal à chaque scan.
    ///   - locateXcrun: trouve `xcrun` par chemin absolu (`ToolLocator`).
    ///   - measure: taille allouée d'un dossier.
    ///   - confirm: demande de confirmation avant de supprimer ; sans valeur par défaut (un test ne peut jamais afficher une vraie alerte).
    init(runner: CommandRunner,
         detect: @escaping () -> SimulatorToolDetection = { SimulatorToolDetector.detect(home: URL(fileURLWithPath: NSHomeDirectory())) },
         locateXcrun: @escaping ([String]) -> String? = { ToolLocator.firstExecutable(in: $0) },
         home: URL = URL(fileURLWithPath: NSHomeDirectory()),
         now: @escaping () -> Date = Date.init,
         measure: @escaping (URL) -> UInt64 = { CleanupService.allocatedSize(of: $0) },
         demo: Bool = DemoMode.isEnabled,
         confirm: @escaping ConfirmHandler,
         notify: @escaping (String) -> Void) {
        self.runner = runner
        self.detect = detect
        self.locateXcrun = locateXcrun
        self.home = home
        self.now = now
        self.measure = measure
        self.demo = demo
        self.notify = notify
        self.confirm = confirm
    }

    func setNotify(_ notify: @escaping (String) -> Void) { self.notify = notify }

    /// Taille gardée par le modèle pour un appareil, `nil` tant qu'elle n'est pas appliquée.
    func measuredSize(udid: String) -> UInt64? { sizes[udid] }
    var measuredSizes: [String: UInt64] { sizes }

    /// « Scan again » est inutilisable pendant le listage (une seule commande `simctl list` à la fois) et pendant une suppression.
    var canScanAgain: Bool { phase != .listing && !isDeleting }

    /// « Delete » est disponible : liste affichée, tailles toutes mesurées, au moins un appareil coché, aucune suppression en cours.
    var canDelete: Bool {
        Self.canDelete(phase: phase, isMeasuring: isMeasuring, selectedCount: selectedCount, isDeleting: isDeleting)
    }

    /// La règle, pure (testable sans modèle).
    static func canDelete(phase: Phase, isMeasuring: Bool, selectedCount: Int, isDeleting: Bool) -> Bool {
        phase == .listed && !isMeasuring && selectedCount > 0 && !isDeleting
    }

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
        guard !row.isRunning, !isDeleting else { return }
        let udid = row.device.device.udid
        if selected.contains(udid) { selected.remove(udid) } else { selected.insert(udid) }
    }

    /// Change la limite : la sélection devient TOUT DE SUITE la suggestion de cette limite (les choix manuels sont remplacés),
    /// sans nouveau scan ni appel au lanceur.
    func setLimit(_ days: Int) {
        guard !isDeleting else { return }
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

    /// Lance la lecture de la liste, hors de l'acteur principal. Pendant le listage un nouveau déclenchement est ignoré
    /// (jamais deux `simctl list` en même temps) ; pendant la mesure des tailles il annule la mesure et recommence.
    func scan() {
        guard canScanAgain else { return }
        token?.cancel()
        let token = CancelToken()
        self.token = token

        // Mode démo : appareils inventés, tout de suite, sans lanceur, sans détection, sans mesure, sans lire ni écrire de fichier.
        if demo {
            reset()
            let demoDevices = DemoData.simulators(now: now())
            devices = demoDevices.map(\.device)
            sizes = Dictionary(uniqueKeysWithValues: demoDevices.map { ($0.device.udid, $0.size) })
            phase = .listed
            recompute(selection: .replace)
            scanTask = nil
            return
        }

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

    // MARK: Suppression

    /// Bouton « Delete » : demande la confirmation (nombre, taille, ce qui est perdu ; « Delete » est le bouton destructif, `critical`),
    /// puis supprime les appareils cochés, dans l'ordre d'affichage. Sans effet quand `canDelete` est faux.
    /// Annuler la confirmation : aucun appel, la sélection reste, pas de toast.
    func deleteSelected() {
        guard canDelete else { return }
        let targets = rows.map(\.device.device.udid).filter { selected.contains($0) }
        guard confirm(
            String(localized: "Delete the selected devices? (\(targets.count))"),
            String(localized: "\(Format.fileBytes(selectedSize)) will be freed. The devices, the apps and data on them, and their snapshots will be deleted. You can create new devices from Xcode or Android Studio."),
            String(localized: "Delete"), true
        ) else { return }

        // Mode démo : la même confirmation (pour l'écran S3), puis les lignes cochées quittent la liste tout de suite, avec
        // l'espace inventé de ces appareils. Ni lanceur, ni mesure, ni détection, ni lecture ou écriture de fichier, ni nouveau scan.
        if demo {
            let gone = Set(targets)
            let freed = targets.reduce(UInt64(0)) { $0 + (sizes[$1] ?? 0) }
            devices.removeAll { gone.contains($0.udid) }
            for udid in gone { sizes[udid] = nil }
            selected.subtract(gone)
            recompute(selection: .prune)
            notify(String(localized: "\(Format.fileBytes(freed)) freed"))
            return
        }

        isDeleting = true
        let token = CancelToken()
        deleteToken = token
        let runner = runner, detect = detect, locateXcrun = locateXcrun, measure = measure, home = home
        deleteTask = Task { [weak self] in
            // Hors de l'acteur principal. La détection et la porte de `xcrun` sont réévaluées MAINTENANT : si l'outil a disparu,
            // rien n'est lancé et chaque cible compte comme un échec (`remove` rend « impossible de vérifier »).
            let summary = await Task.detached(priority: .userInitiated) { () -> SimulatorRemovalSummary in
                let xcrun = ToolLocator.simulatorXcrunPath(detection: detect(), locate: locateXcrun)
                return SimulatorRemovalSummary.run(targets: targets, isCancelled: { token.isCancelled }) { udid in
                    SimulatorScanner.remove(runner: runner, xcrunPath: xcrun, home: home, measure: measure, udid: udid)
                }
            }.value
            guard let self else { return }
            self.notify(summary.toast())
            self.isDeleting = false
            // Retour pendant la suppression : pas de nouveau scan ; l'écran est déjà « non scanné » et se relancera à l'ouverture.
            guard !token.isCancelled else { return }
            self.scan()
            await self.scanTask?.value
        }
    }

    /// Bouton Retour : annule le scan en cours ; un scan inachevé n'est pas conservé (la prochaine ouverture relance).
    /// Pendant une suppression : aucun nouvel appareil n'est commencé (celui en cours se termine, jamais interrompu), le toast
    /// dit ce qui a été fait, il n'y a pas de nouveau scan, et l'écran redevient « non scanné » (jamais de liste périmée).
    func cancel() {
        token?.cancel()
        scanTask?.cancel()
        if isDeleting {
            deleteToken?.cancel()
            phase = .notScanned
            reset()
        } else if phase == .listing || isMeasuring {
            phase = .notScanned
            reset()
        }
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
