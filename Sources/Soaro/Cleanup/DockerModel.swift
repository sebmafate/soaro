import Combine
import Foundation

/// Modèle de l'outil « Docker » (R8, R10, R11, S4).
///
/// - Le listage (deux commandes en lecture seule) tourne dans une tâche détachée (priorité utilitaire), jamais sur l'acteur principal.
///   Un `CancelToken` annule le scan : le résultat d'un scan annulé n'est jamais appliqué.
/// - Le lanceur n'a PAS de valeur par défaut (ADR 0009), ni la confirmation, ni le relevé d'espace libre, ni l'attente : un test ne lance
///   jamais un vrai `docker`, ne montre jamais une vraie alerte et n'attend jamais 60 s. `CleanupTab` construit les vrais.
/// - Nettoyage : après confirmation (`ConfirmHandler`, Annuler par défaut), un lot tourne dans une tâche détachée : les nettoyages
///   cochés (`DockerCleanupFlow`), l'attente de 60 s, le second relevé ; puis le toast et un nouveau listage. Un seul lot à la fois dans
///   tout le processus (`DockerCleanupGate`). Le bouton Retour n'interrompt pas le lot (deux commandes bornées et une attente) : le toast arrive
///   quand même, et l'écran redevient « non scanné » (jamais une liste périmée).
/// - Soaro ne démarre jamais Docker : un moteur arrêté est un état, pas une action.
@MainActor
final class DockerModel: ObservableObject {
    enum Failure: Equatable {
        /// Le moteur ne répond pas (arrêté).
        case notRunning
        /// `docker` n'a pas répondu dans le délai.
        case notAnswering
        /// Outil impossible à lancer, ou sortie illisible : un seul message neutre.
        case couldNotRead
        /// SL16 : le moteur ou le constructeur courant n'est pas local (ou illisible) : « Soaro only cleans Docker on this Mac… ». Ni ligne, ni bouton.
        case notLocal
    }

    enum Phase: Equatable {
        case notScanned
        /// `docker` n'est pas sur ce Mac : l'outil n'apparaît pas dans la liste.
        case hidden
        case listing
        case failed(Failure)
        case listed
    }

    @Published private(set) var phase: Phase = .notScanned
    @Published private(set) var overview: DockerOverview?
    @Published private(set) var selected: Set<DockerPrune> = []
    /// Le moteur local sur lequel la liste a été lue (SL16) : nommé dans la confirmation et relu avant chaque nettoyage. `nil` hors de la liste.
    private(set) var engine: DockerEngine?
    /// Le texte du dernier résultat (le même que le toast, qui ne reste que 4 s), jusqu'au prochain lot ou jusqu'à Retour. Retour l'efface
    /// quand aucun lot ne tourne ; pendant un lot il le laisse venir (le toast et la ligne arrivent quand même).
    @Published private(set) var lastResult: String?

    /// La tâche du scan en cours ou du dernier scan : les tests l'attendent sans dormir.
    private(set) var scanTask: Task<Void, Never>?
    /// La tâche du lot en cours ou du dernier (nettoyages, attente, toast, nouveau listage) : les tests l'attendent sans dormir.
    private(set) var cleanTask: Task<Void, Never>?

    /// La porte de ce modèle (`DockerCleanupGate.shared` sauf si un test en donne une).
    let gate: DockerCleanupGate
    private var gateObservation: AnyCancellable?
    private var pendingScan = false
    private var token: CancelToken?
    private let runner: CommandRunner
    private let locate: () -> String?
    private let home: URL
    private let freeSpace: @Sendable () -> UInt64?
    private let wait: @Sendable (TimeInterval) async -> Void
    let demo: Bool
    private var notify: (String) -> Void
    private let confirm: ConfirmHandler

    /// - Parameters:
    ///   - runner: sans valeur par défaut (ADR 0009).
    ///   - locate: trouve `docker` par chemin absolu (`ToolLocator.dockerPath`), appelé hors de l'acteur principal ; `nil` : l'outil est caché.
    ///   - home: dossier personnel : le volume dont on relève l'espace libre.
    ///   - freeSpace: espace libre du volume du dossier personnel ; sans valeur par défaut.
    ///   - wait: l'attente de 60 s avant le second relevé ; sans valeur par défaut (un test ne dort jamais).
    ///   - demo: mode démo : lignes inventées, ni lanceur, ni recherche, ni relevé, ni attente, rien d'écrit.
    ///   - confirm: demande de confirmation avant de nettoyer ; sans valeur par défaut.
    ///   - gate: le lot en cours du processus (`nil` : la porte commune de l'application).
    init(runner: CommandRunner,
         locate: @escaping () -> String?,
         home: URL,
         freeSpace: @escaping @Sendable () -> UInt64?,
         wait: @escaping @Sendable (TimeInterval) async -> Void,
         demo: Bool = DemoMode.isEnabled,
         confirm: @escaping ConfirmHandler,
         gate: DockerCleanupGate? = nil,
         notify: @escaping (String) -> Void) {
        self.runner = runner
        self.locate = locate
        self.home = home
        self.freeSpace = freeSpace
        self.wait = wait
        self.demo = demo
        self.confirm = confirm
        self.notify = notify
        self.gate = gate ?? .shared
        self.gate.register(self)
        // Les vues voient la porte comme une propriété de ce modèle.
        gateObservation = self.gate.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    func setNotify(_ notify: @escaping (String) -> Void) { self.notify = notify }

    /// La vraie attente : une pause qui s'arrête quand la tâche est annulée.
    static let realWait: @Sendable (TimeInterval) async -> Void = { seconds in
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// La vraie lecture de l'espace libre : le volume du dossier personnel (celui des données).
    static func realFreeSpace(home: URL) -> @Sendable () -> UInt64? {
        { DockerFreeSpace.available(at: home) }
    }

    // MARK: État

    /// Un lot tourne, dans ce modèle OU dans un autre (porte commune du processus).
    var isBusy: Bool { gate.isBusy }
    var stage: DockerCleanupGate.Stage { gate.stage }

    /// « Scan again » est inutilisable pendant le listage et pendant un lot.
    var canScanAgain: Bool { phase != .listing && !isBusy }

    /// Lignes cochables (cache de build, images sans étiquette).
    var cleanables: [DockerCleanable] { overview?.cleanables ?? [] }

    var selectedCleanables: [DockerCleanable] { cleanables.filter { selected.contains($0.prune) } }
    var selectedCount: Int { selectedCleanables.count }
    /// Taille des lignes cochées (tailles connues seulement).
    var selectedSize: UInt64 { DockerSize.saturatingSum(selectedCleanables.map { $0.size ?? 0 }) }

    /// « Clean » est disponible : la liste est affichée, au moins une ligne est cochée, aucun lot ne tourne.
    var canClean: Bool { phase == .listed && selectedCount > 0 && !isBusy }

    /// Rien à nettoyer : la liste est là mais aucune ligne n'est cochable.
    var showsNothingToClean: Bool { phase == .listed && cleanables.isEmpty }

    /// Message neutre de l'état courant (jamais de code de sortie, de sortie d'erreur ni de chemin), `nil` sinon.
    var message: String? {
        switch phase {
        case .hidden: DockerPresentation.notFoundMessage
        case .listing: DockerPresentation.listingMessage
        case .failed(.notRunning): DockerPresentation.notRunningMessage
        case .failed(.notAnswering): DockerPresentation.notAnsweringMessage
        case .failed(.couldNotRead): DockerPresentation.couldNotReadMessage
        case .failed(.notLocal): DockerPresentation.notLocalMessage
        case .notScanned, .listed: nil
        }
    }

    /// Texte de l'attente de l'écran : celui du lot quand il tourne, même ailleurs (écran rouvert pendant un lot).
    var progressMessage: String {
        switch gate.stage {
        case .cleaning: DockerPresentation.cleaningMessage
        case .measuring: DockerPresentation.measuringMessage
        case .idle: DockerPresentation.listingMessage
        }
    }

    // MARK: Sélection

    func toggle(_ prune: DockerPrune) {
        guard !isBusy, cleanables.contains(where: { $0.prune == prune }) else { return }
        if selected.contains(prune) { selected.remove(prune) } else { selected.insert(prune) }
    }

    var selectAllState: SelectAllState {
        SelectAll.state(selectable: cleanables.count, selected: selectedCount)
    }

    var canSelectAll: Bool { SelectAll.isEnabled(selectable: cleanables.count, locked: isBusy) }

    func toggleAll() {
        guard canSelectAll else { return }
        selected = SelectAll.turnsOn(from: selectAllState) ? Set(cleanables.map(\.prune)) : []
    }

    // MARK: Scan

    /// Lance le listage, hors de l'acteur principal. Pendant le listage un nouveau déclenchement est ignoré ; pendant un lot aussi (un écran
    /// qui vient de s'ouvrir est relancé à la fin du lot).
    func scan() {
        if isBusy {
            if phase == .notScanned { pendingScan = true }
            return
        }
        guard canScanAgain else { return }
        token?.cancel()
        let token = CancelToken()
        self.token = token

        // Mode démo : lignes inventées, tout de suite, sans lanceur, sans recherche de `docker`, sans relevé, sans fichier.
        if demo {
            apply(DemoData.docker())
            scanTask = nil
            return
        }

        phase = .listing
        reset()
        let runner = runner, locate = locate
        scanTask = Task { [weak self] in
            let (found, scan) = await Task.detached(priority: .utility) { () -> (Bool, DockerScan?) in
                guard let path = locate() else { return (false, nil) }
                return (true, DockerScanner.list(runner: runner, dockerPath: path))
            }.value
            guard let self, !token.isCancelled else { return }
            guard found, let scan else {
                self.phase = .hidden
                return
            }
            self.apply(scan)
        }
    }

    private func apply(_ scan: DockerScan) {
        switch scan.status {
        case .ok:
            let overview = DockerOverview.make(scan)
            self.overview = overview
            engine = scan.engine
            selected = Set(overview.cleanables.map(\.prune))
            phase = .listed
        case .engineNotRunning: phase = .failed(.notRunning)
        case .timedOut: phase = .failed(.notAnswering)
        case .toolNotFound, .outputNotReadable: phase = .failed(.couldNotRead)
        case .notLocal: phase = .failed(.notLocal)
        }
    }

    private func reset() {
        overview = nil
        engine = nil
        selected = []
    }

    // MARK: Nettoyage

    /// Bouton « Clean » : demande la confirmation (ce qui est retiré, sa taille, la compilation plus lente, Annuler par défaut), puis lance
    /// les nettoyages cochés, le cache de build d'abord. Sans effet quand `canClean` est faux. Annuler : aucun appel, la sélection reste, pas de toast.
    func cleanSelected() {
        guard canClean, let engine else { return }
        let targets = selectedCleanables
        guard confirm(DockerPresentation.confirmationTitle(count: targets.count),
                      DockerPresentation.confirmationMessage(targets: targets, engine: engine, home: home),
                      String(localized: "Clean"), true) else { return }

        // Mode démo : la même confirmation, puis les lignes cochées quittent la liste tout de suite, avec un toast inventé. Ni lanceur, ni
        // recherche de `docker`, ni relevé d'espace libre, ni attente, ni fichier, ni nouveau listage.
        if demo {
            let announced = DockerSize.saturatingSum(targets.map { $0.size ?? 0 })
            let gone = Set(targets.map(\.prune))
            if let current = overview {
                overview = DockerOverview(cleanables: current.cleanables.filter { !gone.contains($0.prune) },
                                          buildCacheSizeUnknown: current.buildCacheSizeUnknown,
                                          containers: current.containers, volumes: current.volumes, otherUnusedImages: current.otherUnusedImages)
            }
            selected.subtract(gone)
            let text = DockerCleanupResult(succeededCount: targets.count, failedCount: 0, timedOut: false,
                                           dockerBytes: announced, returnedBytes: announced / 10 * 9).toast()
            lastResult = text
            notify(text)
            cleanTask = Task {}
            return
        }

        // La porte est commune au processus : un seul lot à la fois, tous modèles confondus.
        guard gate.begin() else { return }
        lastResult = nil
        let token = self.token ?? CancelToken()
        let runner = runner, locate = locate, freeSpace = freeSpace, wait = wait
        // Le toast et la porte ne dépendent PAS du modèle : si l'écran disparaît (changement d'onglet), le lot va quand même
        // jusqu'à son toast et libère la porte. Seul le nouveau listage, qui ne sert qu'à un écran encore là, passe par `self` (faible).
        let notify = notify, gate = gate
        let cleanTargets = targets.map { DockerCleanupTarget(prune: $0.prune, announcedBytes: $0.size) }
        cleanTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> DockerCleanupResult in
                await DockerCleanupFlow.run(targets: cleanTargets, runner: runner, dockerPath: locate(), expectedEngine: engine, freeSpace: freeSpace,
                                            beforeWait: { await MainActor.run { gate.markMeasuring() } }, wait: wait)
            }.value
            let text = result.toast()
            if !text.isEmpty { notify(text) }
            self?.lastResult = text.isEmpty ? nil : text
            gate.end()
            // Retour pendant le lot : pas de nouveau listage ; l'écran est déjà « non scanné » et se relancera à l'ouverture.
            guard let self, !token.isCancelled else { return }
            self.scan()
            await self.scanTask?.value
        }
    }

    /// Un lot vient de finir (porte libre) : le listage demandé pendant ce temps part maintenant.
    func gateDidBecomeIdle() {
        guard pendingScan else { return }
        pendingScan = false
        scan()
    }

    /// Bouton Retour : annule le listage en cours ; un listage inachevé n'est pas conservé (la prochaine ouverture relance). Pendant un lot, le
    /// lot continue jusqu'à son toast, mais l'écran redevient « non scanné » : jamais une liste périmée.
    func cancel() {
        token?.cancel()
        scanTask?.cancel()
        pendingScan = false
        if !isBusy { lastResult = nil }
        if phase == .listing || isBusy {
            phase = .notScanned
            reset()
        }
    }
}

/// Un lot de nettoyages Docker en cours, vu par TOUS les modèles du processus (le panneau et la fenêtre ont chacun le leur, et un modèle
/// disparaît quand on change d'onglet). Tant qu'un lot tourne : aucun autre lot, aucun listage, sur aucun modèle.
/// Les tests donnent leur propre porte à chaque modèle (`gate:`) ; l'application utilise `shared`.
@MainActor
final class DockerCleanupGate: ObservableObject {
    static let shared = DockerCleanupGate()

    enum Stage: Equatable {
        case idle
        /// Les nettoyages tournent.
        case cleaning
        /// Les nettoyages sont finis, l'attente de 60 s puis le second relevé d'espace libre.
        case measuring
    }

    @Published private(set) var stage: Stage = .idle
    var isBusy: Bool { stage != .idle }

    private struct Observer { weak var model: DockerModel? }
    private var observers: [Observer] = []

    func register(_ model: DockerModel) {
        observers.removeAll { $0.model == nil }
        observers.append(Observer(model: model))
    }

    /// - Returns: `false` quand un lot tourne déjà (rien n'est alors commencé).
    func begin() -> Bool {
        guard !isBusy else { return false }
        stage = .cleaning
        return true
    }

    func markMeasuring() {
        if stage == .cleaning { stage = .measuring }
    }

    /// Fin du lot (réussi, échoué, délai dépassé) : la porte se libère TOUJOURS, puis les modèles qui attendaient la fin sont prévenus.
    func end() {
        stage = .idle
        observers.removeAll { $0.model == nil }
        for observer in observers { observer.model?.gateDidBecomeIdle() }
    }
}
