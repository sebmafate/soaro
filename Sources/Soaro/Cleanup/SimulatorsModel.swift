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
    /// Lignes affichées (appareils d'au moins 100 Mo, ou de taille encore inconnue).
    @Published private(set) var rows: [DeviceSuggestions.Row] = []

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
        rows = []

        let runner = runner, detect = detect, locateXcrun = locateXcrun
        scanTask = Task { [weak self] in
            let listing = await Task.detached(priority: .utility) { () -> SimulatorListing in
                let detection = detect()
                let xcrun = ToolLocator.simulatorXcrunPath(detection: detection, locate: locateXcrun)
                return SimulatorScanner.list(runner: runner, xcrunPath: xcrun)
            }.value
            guard let self, !token.isCancelled else { return }
            self.apply(listing)
        }
    }

    /// Bouton Retour : annule le scan en cours ; un scan inachevé n'est pas conservé (la prochaine ouverture relance).
    func cancel() {
        token?.cancel()
        scanTask?.cancel()
        if phase == .listing { phase = .notScanned; rows = [] }
    }

    private func apply(_ listing: SimulatorListing) {
        switch listing.status {
        case .ok:
            if listing.devices.isEmpty {
                phase = .empty
                return
            }
            phase = .listed
            let sized = listing.devices.map { SizedSimulator(device: $0, size: DeviceSuggestions.smallDeviceThreshold) }
            rows = DeviceSuggestions.suggest(sized, now: now(), limitDays: DeviceSuggestions.defaultLimitDays).rows
        case .timedOut:
            phase = .failed(.notAnswering)
        case .toolNotFound, .commandFailed, .outputNotReadable:
            phase = .failed(.couldNotRead)
        }
    }
}
