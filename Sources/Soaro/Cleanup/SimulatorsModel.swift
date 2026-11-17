import Combine
import Foundation

/// Modèle de l'outil « Simulators and emulators » (R3, R4, R5, R6, R8, R16, R18).
///
/// Deux groupes côte à côte : les simulateurs iOS (UDID) et, SL10, les émulateurs Android (nom d'AVD). Chacun a son état, ses
/// lignes, ses tailles et sa sélection ; les parties communes (limite, totaux, pied de page, « Scan again », « Delete ») les
/// additionnent. Un échec d'un groupe n'abîme jamais l'autre. SL11 : « Delete » agit sur les deux groupes (un lot mixte : iOS d'abord, puis Android).
///
/// - Le listage (une commande) tourne dans une tâche détachée (priorité utilitaire), jamais sur l'acteur principal,
///   jamais dans le tick de 3 secondes. Un `CancelToken` annule le scan : le résultat d'un scan annulé n'est jamais appliqué.
/// - Le lanceur n'a PAS de valeur par défaut (ADR 0009) : il est construit par `CleanupTab`, et nulle part ailleurs.
/// - La détection de l'outil ne lance rien ; le lanceur n'est appelé que si `simctl` est sur le disque ET `xcrun` présent.
/// - Suppression (SL9, SL11) : après confirmation (`ConfirmHandler` injecté, sans valeur par défaut), un lot tourne dans une tâche
///   détachée (priorité utilisateur) : pour chaque simulateur, `SimulatorScanner.remove` (revérification de l'état, portée, mesure
///   avant et après, `xcrun simctl delete`) ; puis pour chaque AVD, `AndroidEmulatorScanner.remove` (plan : listage frais et portée ;
///   mesure avant ; `ps` frais ; suppression du dossier puis des `.ini` ; mesure après). Le toast dit l'espace réellement libéré ; la liste est relue ensuite.
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
        /// Le groupe n'existe pas sur ce Mac : pas d'outil iOS (ni dossier d'appareils ni `simctl`), ou pas de SDK Android (R18).
        case hidden
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
    /// Les tailles iOS sont en cours de mesure (un dossier à la fois).
    @Published private var iosMeasuring = false
    /// Les tailles sont en cours de mesure, dans l'un ou l'autre groupe.
    var isMeasuring: Bool { iosMeasuring || androidMeasuring }
    /// Appareils iOS mesurés à moins de 100 Mo : comptés, pas listés.
    @Published private var iosHiddenSmallCount = 0
    @Published private var iosHiddenSmallSize: UInt64 = 0
    /// Appareils mesurés à moins de 100 Mo, des deux groupes : comptés, pas listés (pied de page).
    var hiddenSmallCount: Int { iosHiddenSmallCount + androidHiddenSmallCount }
    var hiddenSmallSize: UInt64 { iosHiddenSmallSize + androidHiddenSmallSize }

    // Groupe Android (SL10) : état, lignes, sélection (nom d'AVD) et tailles, séparés des UDID.
    @Published private(set) var androidPhase: Phase = .notScanned
    @Published private(set) var androidRows: [DeviceSuggestions.AndroidRow] = []
    @Published private(set) var androidSelected: Set<String> = []
    @Published private var androidMeasuring = false
    @Published private var androidHiddenSmallCount = 0
    @Published private var androidHiddenSmallSize: UInt64 = 0
    @Published private var androidSizes: [String: UInt64] = [:]
    private var androidNothingPreSelected = true
    /// Tous les appareils Android du listage, sans taille.
    private var androidDevices: [AndroidDevice] = []
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
    /// Une suppression est en cours, dans ce modèle OU dans un autre (porte commune du processus).
    var isDeleting: Bool { gate.isBusy }
    /// Un scan a été demandé alors que l'écran n'était pas scanné et qu'une suppression tournait : il part à la fin du lot.
    private var pendingScan = false
    /// La porte de suppression de ce modèle (lecture seule ; `SimulatorDeletionGate.shared` sauf si un test en donne une).
    let gate: SimulatorDeletionGate
    private var gateObservation: AnyCancellable?

    /// La tâche du scan en cours ou du dernier scan : les tests l'attendent (`await model.scanTask?.value`) sans dormir.
    private(set) var scanTask: Task<Void, Never>?
    /// La tâche de la suppression en cours ou de la dernière (lot, toast, puis nouveau scan) : les tests l'attendent sans dormir.
    private(set) var deleteTask: Task<Void, Never>?
    /// Jeton du lot lancé PAR ce modèle, tant qu'il tourne.
    private var deleteToken: CancelToken?

    private var token: CancelToken?
    private let runner: CommandRunner
    private let detect: () -> SimulatorToolDetection
    private let locateTool: ([String]) -> String?
    /// Variables d'environnement du processus, injectées (SDK Android) : AUCUNE valeur par défaut, pour qu'un test ne dépende
    /// jamais de la machine (la CI définit `ANDROID_HOME`).
    private let environment: [String: String]
    let home: URL
    private let now: () -> Date
    private let measure: (URL) -> UInt64
    /// Supprime un fichier ou un dossier d'un AVD (SL11) : `AndroidEmulatorRemover.removeFile` dans l'application, un faux dans les tests.
    private let removeFile: (URL) throws -> Void
    let demo: Bool
    private var notify: (String) -> Void
    private let confirm: ConfirmHandler
    /// Le groupe Android est-il pré-sélectionné ? `DeviceSuggestions.androidPreselectionEnabled` (faux : le signal « dernière utilisation » n'est pas réglé) ; un test peut l'activer.
    private let androidPreselects: Bool

    /// - Parameters:
    ///   - runner: sans valeur par défaut (ADR 0009).
    ///   - detect: détection de l'outil sur le disque (ne lance rien), appelée hors de l'acteur principal à chaque scan.
    ///   - locateTool: trouve un outil par chemin absolu parmi des candidats (`ToolLocator`) : `xcrun`, et `ps` pour Android.
    ///   - environment: variables d'environnement (`ANDROID_SDK_ROOT`, `ANDROID_HOME`) ; sans valeur par défaut.
    ///   - measure: taille allouée d'un dossier.
    ///   - removeFile: suppression d'un fichier ou d'un dossier d'un AVD (le suppresseur réel par défaut ; jamais appelé en démo).
    ///   - confirm: demande de confirmation avant de supprimer ; sans valeur par défaut (un test ne peut jamais afficher une vraie alerte).
    ///   - deletionGate: la suppression en cours du processus (`nil` : la porte commune de l'application).
    init(runner: CommandRunner,
         detect: @escaping () -> SimulatorToolDetection = { SimulatorToolDetector.detect(home: URL(fileURLWithPath: NSHomeDirectory())) },
         locateTool: @escaping ([String]) -> String? = { ToolLocator.firstExecutable(in: $0) },
         environment: [String: String],
         home: URL = URL(fileURLWithPath: NSHomeDirectory()),
         now: @escaping () -> Date = Date.init,
         measure: @escaping (URL) -> UInt64 = { CleanupService.allocatedSize(of: $0) },
         removeFile: @escaping (URL) throws -> Void = AndroidEmulatorRemover.removeFile,
         demo: Bool = DemoMode.isEnabled,
         confirm: @escaping ConfirmHandler,
         deletionGate: SimulatorDeletionGate? = nil,
         androidPreselects: Bool = DeviceSuggestions.androidPreselectionEnabled,
         notify: @escaping (String) -> Void) {
        self.runner = runner
        self.detect = detect
        self.locateTool = locateTool
        self.environment = environment
        self.home = home
        self.now = now
        self.measure = measure
        self.removeFile = removeFile
        self.demo = demo
        self.notify = notify
        self.confirm = confirm
        self.androidPreselects = androidPreselects
        self.gate = deletionGate ?? .shared
        gate.register(self)
        // Les vues voient la porte comme une propriété de ce modèle.
        gateObservation = gate.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    func setNotify(_ notify: @escaping (String) -> Void) { self.notify = notify }

    /// Taille gardée par le modèle pour un appareil, `nil` tant qu'elle n'est pas appliquée.
    func measuredSize(udid: String) -> UInt64? { sizes[udid] }
    var measuredSizes: [String: UInt64] { sizes }

    /// « Scan again » est inutilisable pendant le listage (une seule commande à la fois, un seul outil à la fois) dans l'un ou
    /// l'autre groupe, et pendant une suppression.
    var canScanAgain: Bool { phase != .listing && androidPhase != .listing && !isDeleting }

    /// « Delete » est disponible : aucune taille en cours de mesure, aucune suppression en cours, et au moins un appareil coché dans un
    /// groupe affiché (iOS listé avec une ligne iOS cochée, ou Android listé avec une ligne Android cochée). SL11 : une ligne Android
    /// cochée ne désactive plus Delete.
    var canDelete: Bool {
        Self.canDelete(phase: phase, androidPhase: androidPhase, isMeasuring: isMeasuring, selectedCount: iosSelectedCount,
                       androidSelectedCount: androidSelectedCount, isDeleting: isDeleting)
    }

    /// La règle, pure (testable sans modèle).
    static func canDelete(phase: Phase, androidPhase: Phase, isMeasuring: Bool, selectedCount: Int, androidSelectedCount: Int,
                          isDeleting: Bool) -> Bool {
        guard !isMeasuring, !isDeleting else { return false }
        return (phase == .listed && selectedCount > 0) || (androidPhase == .listed && androidSelectedCount > 0)
    }

    /// Taille mesurée d'une ligne, `nil` tant qu'elle ne l'est pas (la vue affiche « … »).
    func size(of row: DeviceSuggestions.Row) -> UInt64? { sizes[row.device.device.udid] }
    func size(of row: DeviceSuggestions.AndroidRow) -> UInt64? { androidSizes[row.device.device.name] }
    func measuredSize(avd name: String) -> UInt64? { androidSizes[name] }

    /// Valeurs du menu de limite : 30, 60, 90, 180 jours ; la limite par défaut y est ajoutée (en ordre) si elle n'y est pas.
    static func limitChoices(defaultDays: Int = DeviceSuggestions.defaultLimitDays) -> [Int] {
        Set([30, 60, 90, 180, defaultDays]).sorted()
    }

    /// Bandeau « Nothing to suggest… » : au moins une ligne listée (dans l'un ou l'autre groupe), rien de pré-sélectionné nulle part,
    /// et les tailles sont toutes arrivées.
    /// Un groupe dont la pré-sélection est coupée (Android, tant que le réglage est éteint) ne compte pas : « rien à suggérer » serait faux (par conception),
    /// et « baisser la limite » n'y changerait rien.
    var showsNothingToSuggest: Bool {
        let suggested = rows.count + (androidPreselects ? androidRows.count : 0)
        return !isMeasuring && suggested > 0 && nothingPreSelected && (!androidPreselects || androidNothingPreSelected)
    }

    /// Appareils listés, des deux groupes.
    var listedCount: Int { rows.count + androidRows.count }

    var iosSelectedCount: Int { rows.filter { selected.contains($0.device.device.udid) }.count }
    var androidSelectedCount: Int { androidRows.filter { androidSelected.contains($0.device.device.name) }.count }
    /// Appareils cochés, des deux groupes.
    var selectedCount: Int { iosSelectedCount + androidSelectedCount }
    /// Taille des appareils iOS cochés (tailles connues seulement).
    private var iosSelectedSize: UInt64 {
        rows.reduce(0) { $0 + (selected.contains($1.device.device.udid) ? (sizes[$1.device.device.udid] ?? 0) : 0) }
    }
    /// Taille des appareils cochés, des deux groupes (tailles connues seulement).
    var selectedSize: UInt64 {
        iosSelectedSize + androidRows.reduce(0) { $0 + (androidSelected.contains($1.device.device.name) ? (androidSizes[$1.device.device.name] ?? 0) : 0) }
    }

    /// Coche ou décoche une ligne ; un appareil en cours d'exécution ne se coche jamais.
    func toggle(_ row: DeviceSuggestions.Row) {
        guard !row.isRunning, !isDeleting else { return }
        let udid = row.device.device.udid
        if selected.contains(udid) { selected.remove(udid) } else { selected.insert(udid) }
    }

    /// Même chose pour une ligne Android (clé : nom d'AVD).
    func toggle(_ row: DeviceSuggestions.AndroidRow) {
        guard !row.isRunning, !isDeleting else { return }
        let name = row.device.device.name
        if androidSelected.contains(name) { androidSelected.remove(name) } else { androidSelected.insert(name) }
    }

    /// Change la limite : la sélection devient TOUT DE SUITE la suggestion de cette limite (les choix manuels sont remplacés),
    /// sans nouveau scan ni appel au lanceur.
    func setLimit(_ days: Int) {
        guard !isDeleting else { return }
        limitDays = days
        recompute(selection: .replace)
    }

    /// Somme des tailles mesurées des appareils listés, des deux groupes.
    var measuredSizeTotal: UInt64 {
        rows.reduce(0) { $0 + (sizes[$1.device.device.udid] ?? 0) } + androidRows.reduce(0) { $0 + (androidSizes[$1.device.device.name] ?? 0) }
    }

    /// Message neutre de l'état courant (jamais de code de sortie, de sortie d'erreur ni de chemin), `nil` sinon.
    var message: String? {
        switch phase {
        case .listing: String(localized: "Looking for simulators and emulators…")
        case .failed(.couldNotRead): String(localized: "Could not read the iOS Simulators.")
        case .failed(.notAnswering): String(localized: "Xcode’s simulator service did not answer. Try again in a moment.")
        case .empty: String(localized: "No simulator or emulator found.")
        case .notScanned, .hidden, .listed: nil
        }
    }

    /// Message du groupe Android quand sa lecture a échoué, `nil` sinon.
    var androidMessage: String? {
        if case .failed = androidPhase { return AndroidEmulatorPresentation.couldNotReadMessage }
        return nil
    }

    /// Texte de l'attente de l'écran (« non scanné » ou en cours de listage) : « Deleting… » quand une suppression tourne,
    /// même ailleurs (écran rouvert pendant un lot), sinon « Looking for… ».
    var progressMessage: String {
        isDeleting ? String(localized: "Deleting…") : String(localized: "Looking for simulators and emulators…")
    }

    // MARK: Scan

    /// Lance la lecture de la liste, hors de l'acteur principal. Pendant le listage un nouveau déclenchement est ignoré
    /// (jamais deux `simctl list` en même temps) ; pendant la mesure des tailles il annule la mesure et recommence.
    func scan() {
        // Une suppression tourne (ici ou ailleurs) : jamais de liste pendant ce temps. Un écran qui vient de s'ouvrir
        // (jamais scanné) est relancé à la fin du lot.
        if isDeleting {
            if phase == .notScanned { pendingScan = true }
            return
        }
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
            let demoAndroid = DemoData.androidEmulators(now: now())
            androidDevices = demoAndroid.map(\.device)
            androidSizes = Dictionary(uniqueKeysWithValues: demoAndroid.map { ($0.device.name, $0.size) })
            androidPhase = .listed
            recompute(selection: .replace)
            scanTask = nil
            return
        }

        phase = .listing
        androidPhase = .listing
        reset()

        let runner = runner, detect = detect, locateTool = locateTool, measure = measure, home = home, environment = environment
        scanTask = Task { [weak self] in
            // UNE seule tâche, UN outil à la fois (le faux lanceur des tests n'est pas sûr entre fils) : `simctl list` d'abord,
            // puis `ps` pour Android. Aucun outil iOS sur ce Mac (ni dossier d'appareils ni `simctl`) : le groupe iOS est caché.
            let (iosListing, androidListing) = await Task.detached(priority: .utility) { () -> (SimulatorListing?, AndroidListing) in
                let detection = detect()
                var ios: SimulatorListing?
                if detection.isToolPresent {
                    let xcrun = ToolLocator.simulatorXcrunPath(detection: detection, locate: locateTool)
                    ios = SimulatorScanner.list(runner: runner, xcrunPath: xcrun)
                }
                // `ps` n'est cherché que si un SDK existe : sans SDK, rien d'Android n'est lu ni lancé (R18).
                let psPath = ToolLocator.androidSDK(environment: environment, home: home) == nil
                    ? nil : locateTool(ToolLocator.processListCandidates)
                let android = AndroidEmulatorScanner.list(runner: runner, psPath: psPath, environment: environment, home: home)
                return (ios, android)
            }.value
            guard let self, !token.isCancelled else { return }
            let iosListed = self.apply(iosListing)
            let androidListed = self.apply(androidListing)

            // Les tailles arrivent une à une (un dossier à la fois, hors de l'acteur principal), comme dans le désinstalleur.
            // Dans l'ordre d'affichage (haut en bas) : les lignes iOS d'abord, puis les lignes Android.
            if iosListed {
                for device in self.rows.map(\.device.device) {
                    if token.isCancelled { return }
                    // `parse` a validé l'UDID : `deviceFolder` ne peut pas rendre `nil` ici.
                    let folder = SimulatorScanner.deviceFolder(udid: device.udid, home: home)
                    let size = await Task.detached(priority: .utility) { folder.map(measure) ?? 0 }.value
                    if token.isCancelled { return }
                    self.sizes[device.udid] = size
                    self.recomputeIOS(selection: .prune)
                }
                if token.isCancelled { return }
                self.iosMeasuring = false
                self.recomputeIOS(selection: .prune)
            }
            if androidListed {
                for device in self.androidRows.map(\.device.device) {
                    if token.isCancelled { return }
                    let folder = device.folder
                    let size = await Task.detached(priority: .utility) { measure(folder) }.value
                    if token.isCancelled { return }
                    self.androidSizes[device.name] = size
                    self.recomputeAndroid(selection: .prune)
                }
                if token.isCancelled { return }
                self.androidMeasuring = false
                self.recomputeAndroid(selection: .prune)
            }
        }
    }

    // MARK: Suppression

    /// Bouton « Delete » : demande la confirmation (nombre et taille des DEUX groupes, ce qui est perdu ; « Delete » est le bouton
    /// destructif, `critical`), puis supprime les appareils cochés : les simulateurs iOS d'abord, puis les AVD Android, chaque groupe dans
    /// l'ordre d'affichage. Sans effet quand `canDelete` est faux.
    /// Annuler la confirmation : aucun appel, aucune suppression, la sélection reste, pas de toast.
    func deleteSelected() {
        guard canDelete else { return }
        // Cibles : les appareils iOS cochés (UDID), puis les AVD cochés (nom et dossier vus au scan).
        let iosTargets = rows.map(\.device.device.udid).filter { selected.contains($0) }
        let androidTargets = androidRows.map(\.device.device).filter { androidSelected.contains($0.name) }
            .map { AndroidRemovalTarget(name: $0.name, folder: $0.folder) }
        // La confirmation nomme les appareils (ADR 0009, règle 2) : leurs noms, tels quels, après le texte localisé (aucune clé nouvelle).
        let names = rows.filter { selected.contains($0.device.device.udid) }.map(\.device.device.name)
            + androidRows.filter { androidSelected.contains($0.device.device.name) }.map(\.device.device.displayName)
        guard confirm(
            String(localized: "Delete the selected devices? (\(iosTargets.count + androidTargets.count))"),
            String(localized: "\(Format.fileBytes(selectedSize)) will be freed. The devices, the apps and data on them, and their snapshots will be deleted. You can create new devices from Xcode or Android Studio.")
                + SimulatorPresentation.confirmationNames(names),
            String(localized: "Delete"), true
        ) else { return }

        // Mode démo : la même confirmation (pour l'écran S3), puis les lignes cochées (iOS et Android) quittent la liste tout de suite,
        // avec l'espace inventé de ces appareils. Ni lanceur, ni mesure, ni détection, ni recherche d'outil, ni suppression de fichier,
        // ni lecture ou écriture de fichier, ni nouveau scan.
        if demo {
            let goneIOS = Set(iosTargets)
            let goneAndroid = Set(androidTargets.map(\.name))
            let freed = iosTargets.reduce(UInt64(0)) { $0 + (sizes[$1] ?? 0) } + goneAndroid.reduce(UInt64(0)) { $0 + (androidSizes[$1] ?? 0) }
            devices.removeAll { goneIOS.contains($0.udid) }
            for udid in goneIOS { sizes[udid] = nil }
            selected.subtract(goneIOS)
            recomputeIOS(selection: .prune)
            androidDevices.removeAll { goneAndroid.contains($0.name) }
            for name in goneAndroid { androidSizes[name] = nil }
            androidSelected.subtract(goneAndroid)
            recomputeAndroid(selection: .prune)
            notify(String(localized: "\(Format.fileBytes(freed)) freed"))
            return
        }

        // La porte est commune au processus : un seul lot à la fois, tous modèles confondus.
        guard gate.begin() else { return }
        let token = CancelToken()
        deleteToken = token
        let runner = runner, detect = detect, locateTool = locateTool, measure = measure, home = home, removeFile = removeFile
        // Le toast et la porte ne dépendent PAS du modèle : si l'écran disparaît (changement d'onglet), le lot va quand même
        // jusqu'à son toast et libère la porte. Seul le nouveau scan, qui ne sert qu'à un écran encore là, passe par `self` (faible).
        let notify = notify, gate = gate
        deleteTask = Task { [weak self] in
            // Hors de l'acteur principal. Chaque outil n'est cherché que s'il sert : la détection et la porte de `xcrun` seulement
            // quand il y a une cible iOS (si l'outil a disparu, rien n'est lancé et chaque cible compte comme un échec), le chemin de
            // `ps` seulement quand il y a une cible Android (absent : chaque cible Android compte comme un échec, rien n'est supprimé).
            let summary = await Task.detached(priority: .userInitiated) { () -> DeviceRemovalSummary in
                let xcrun = iosTargets.isEmpty ? nil : ToolLocator.simulatorXcrunPath(detection: detect(), locate: locateTool)
                let psPath = androidTargets.isEmpty ? nil : locateTool(ToolLocator.processListCandidates)
                return DeviceRemovalSummary.run(
                    iosTargets: iosTargets, androidTargets: androidTargets, isCancelled: { token.isCancelled },
                    removeIOS: { udid in
                        SimulatorScanner.remove(runner: runner, xcrunPath: xcrun, home: home, measure: measure, udid: udid)
                    },
                    removeAndroid: { target in
                        AndroidEmulatorScanner.remove(runner: runner, psPath: psPath, home: home, measure: measure,
                                                      removeFile: removeFile, target: target)
                    })
            }.value
            // Retour avant la moindre tentative : rien à dire (texte vide).
            let text = summary.toast()
            if !text.isEmpty { notify(text) }
            self?.deleteToken = nil
            gate.end()
            // Retour pendant la suppression : pas de nouveau scan ; l'écran est déjà « non scanné » et se relancera à l'ouverture.
            guard let self, !token.isCancelled else { return }
            self.scan()
            await self.scanTask?.value
        }
    }

    /// Un lot vient de finir (porte libre) : le scan demandé pendant ce temps part maintenant.
    func gateDidBecomeIdle() {
        guard pendingScan else { return }
        pendingScan = false
        scan()
    }

    /// Bouton Retour : annule le scan en cours ; un scan inachevé n'est pas conservé (la prochaine ouverture relance).
    /// Pendant une suppression : aucun nouvel appareil n'est commencé (celui en cours se termine, jamais interrompu), le toast
    /// dit ce qui a été fait, il n'y a pas de nouveau scan, et l'écran redevient « non scanné » (jamais de liste périmée).
    func cancel() {
        token?.cancel()
        scanTask?.cancel()
        pendingScan = false
        if let deleteToken {
            deleteToken.cancel()
            phase = .notScanned
            androidPhase = .notScanned
            reset()
        } else if phase == .listing || androidPhase == .listing || isMeasuring {
            phase = .notScanned
            androidPhase = .notScanned
            reset()
        }
    }

    private func reset() {
        rows = []
        devices = []
        sizes = [:]
        selected = []
        nothingPreSelected = true
        iosMeasuring = false
        iosHiddenSmallCount = 0
        iosHiddenSmallSize = 0
        androidRows = []
        androidDevices = []
        androidSizes = [:]
        androidSelected = []
        androidNothingPreSelected = true
        androidMeasuring = false
        androidHiddenSmallCount = 0
        androidHiddenSmallSize = 0
    }

    /// Recalcule les lignes et le pied de page : un appareil dont la taille n'est pas connue compte comme « assez gros »
    /// (il reste listé), les autres suivent `DeviceSuggestions.suggest`.
    private enum SelectionUpdate {
        /// La sélection devient la pré-sélection du calcul (arrivée de la liste, changement de limite).
        case replace
        /// Les choix de l'utilisateur sont gardés ; seuls sortent les appareils qui ne sont plus listés (mesurés petits).
        case prune
    }

    /// Les deux groupes : la limite est commune.
    private func recompute(selection: SelectionUpdate) {
        recomputeIOS(selection: selection)
        recomputeAndroid(selection: selection)
    }

    private func recomputeAndroid(selection: SelectionUpdate) {
        let sized = androidDevices.map { SizedAndroidDevice(device: $0, size: androidSizes[$0.name] ?? DeviceSuggestions.smallDeviceThreshold) }
        let result = DeviceSuggestions.suggestAndroid(sized, now: now(), limitDays: limitDays)
        androidRows = androidMeasuring ? result.rows.sorted { AndroidDevice.isOrderedBefore($0.device.device, $1.device.device) } : result.rows
        androidNothingPreSelected = result.preSelectedCount == 0
        switch selection {
        // Réglage coupé : la règle est calculée (raison « inactive for N d », `--scan`) mais rien n'est coché d'office.
        case .replace: androidSelected = androidPreselects ? Set(result.rows.filter(\.isPreSelected).map(\.device.device.name)) : []
        case .prune: androidSelected.formIntersection(result.rows.filter { !$0.isRunning }.map(\.device.device.name))
        }
        androidHiddenSmallCount = result.hiddenSmallCount
        androidHiddenSmallSize = result.hiddenSmallSize
    }

    private func recomputeIOS(selection: SelectionUpdate) {
        let sized = devices.map { SizedSimulator(device: $0, size: sizes[$0.udid] ?? DeviceSuggestions.smallDeviceThreshold) }
        let result = DeviceSuggestions.suggest(sized, now: now(), limitDays: limitDays)
        rows = iosMeasuring ? result.rows.sorted(by: Self.listingOrder) : result.rows
        nothingPreSelected = result.preSelectedCount == 0
        switch selection {
        case .replace: selected = Set(result.rows.filter(\.isPreSelected).map(\.device.device.udid))
        case .prune: selected.formIntersection(result.rows.filter { !$0.isRunning }.map(\.device.device.udid))
        }
        iosHiddenSmallCount = result.hiddenSmallCount
        iosHiddenSmallSize = result.hiddenSmallSize
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

    /// - Parameter listing: `nil` : aucun outil iOS sur ce Mac, le groupe est caché (R6 : pas de message d'échec sans Xcode).
    /// - Returns: `true` quand des appareils sont listés (les tailles peuvent alors être mesurées).
    private func apply(_ listing: SimulatorListing?) -> Bool {
        guard let listing else {
            phase = .hidden
            return false
        }
        switch listing.status {
        case .ok:
            if listing.devices.isEmpty {
                phase = .empty
                return false
            }
            devices = listing.devices
            phase = .listed
            iosMeasuring = true
            recomputeIOS(selection: .replace)
            return true
        case .timedOut:
            phase = .failed(.notAnswering)
        case .toolNotFound, .commandFailed, .outputNotReadable:
            phase = .failed(.couldNotRead)
        }
        return false
    }

    /// - Returns: `true` quand des appareils Android sont listés (leurs tailles peuvent alors être mesurées).
    private func apply(_ listing: AndroidListing) -> Bool {
        switch listing.status {
        case .sdkNotFound:
            androidPhase = .hidden
        case .couldNotRead:
            androidPhase = .failed(.couldNotRead)
        case .ok:
            if listing.devices.isEmpty {
                androidPhase = .empty
                return false
            }
            androidDevices = listing.devices
            androidPhase = .listed
            androidMeasuring = true
            recomputeAndroid(selection: .replace)
            return true
        }
        return false
    }
}

/// Une suppression de simulateurs en cours, vue par TOUS les modèles du processus (le panneau et la fenêtre ont chacun le leur,
/// et un modèle disparaît quand on change d'onglet). Tant qu'un lot tourne : aucun autre lot, aucun scan, sur aucun modèle,
/// pour ne jamais voir (ni supprimer deux fois) des appareils en cours de suppression.
/// Les tests donnent leur propre porte à chaque modèle (`deletionGate:`) ; l'application utilise `shared`.
@MainActor
final class SimulatorDeletionGate: ObservableObject {
    static let shared = SimulatorDeletionGate()

    @Published private(set) var isBusy = false

    private struct Observer { weak var model: SimulatorsModel? }
    private var observers: [Observer] = []

    func register(_ model: SimulatorsModel) {
        observers.removeAll { $0.model == nil }
        observers.append(Observer(model: model))
    }

    /// - Returns: `false` quand un lot tourne déjà (rien n'est alors commencé).
    func begin() -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        return true
    }

    /// Fin du lot (réussi, échoué, délai dépassé, annulé) : la porte se libère TOUJOURS, puis les modèles qui attendaient la fin
    /// (un scan demandé pendant le lot) sont prévenus.
    func end() {
        isBusy = false
        observers.removeAll { $0.model == nil }
        for observer in observers { observer.model?.gateDidBecomeIdle() }
    }
}
