import Foundation

/// Pourquoi le réseau « a peut-être changé » (SL25, ADR 0012).
enum NetworkChangeReason: Equatable {
    /// Une clé de configuration réseau a bougé (interface principale, passerelle, DNS, service).
    case configuration
    /// Le Mac se réveille : le réseau a pu changer pendant le sommeil, même si rien n'a été notifié.
    case wake
}

/// D'où viennent les événements. Remplaçable par une fausse source dans les tests ; la vraie est `SystemNetworkEventSource`.
@MainActor protocol NetworkEventSource: AnyObject {
    /// Commence à livrer les événements. Faux si la source ne peut pas démarrer.
    func start(_ onEvent: @escaping @MainActor (NetworkChangeReason) -> Void) -> Bool
    func stop()
}

/// Un minuteur à usage unique, remplaçable pour que les tests décident de l'écoulement du temps. Rend la fonction d'annulation.
@MainActor protocol DebounceScheduler {
    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> () -> Void
}

/// Le minuteur réel : une tâche qui dort puis exécute.
struct TaskDebounceScheduler: DebounceScheduler {
    nonisolated init() {}

    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> () -> Void {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            work()
        }
        return { task.cancel() }
    }
}

/// Réveille la logique de recherche quand le réseau change, après une rafale d'événements (délai de calme de `quietPeriod`).
/// Il ne connaît ni le service d'IP publique ni aucune connexion : il rappelle seulement `onSettled`, et c'est la fonction de décision
/// existante qui juge s'il y a lieu de chercher. Il ne retient rien d'autre que sa source et son rappel (qui ne retient pas son propriétaire).
@MainActor final class NetworkChangeMonitor {
    private let source: NetworkEventSource
    private let scheduler: DebounceScheduler
    private let quiet: TimeInterval
    private let onSettled: @MainActor (NetworkChangeReason) -> Void
    private(set) var isRunning = false
    private var pending: NetworkChangeReason?
    private var cancelPending: (() -> Void)?

    init(source: NetworkEventSource, scheduler: DebounceScheduler = TaskDebounceScheduler(),
         quietPeriod: TimeInterval = PublicIPLookupPolicy.quietPeriod,
         onSettled: @escaping @MainActor (NetworkChangeReason) -> Void) {
        self.source = source
        self.scheduler = scheduler
        self.quiet = quietPeriod
        self.onSettled = onSettled
    }

    @discardableResult func start() -> Bool {
        if isRunning { return true }
        // La source ne retient pas le moniteur : un rappel faible.
        isRunning = source.start { [weak self] reason in self?.received(reason) }
        return isRunning
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        cancelPending?()
        cancelPending = nil
        pending = nil
        source.stop()
    }

    private func received(_ reason: NetworkChangeReason) {
        guard isRunning else { return }
        // Un réveil dans la rafale reste un réveil, quel que soit l'ordre.
        pending = (pending == .wake || reason == .wake) ? .wake : .configuration
        cancelPending?()
        cancelPending = scheduler.schedule(after: quiet) { [weak self] in self?.fire() }
    }

    private func fire() {
        guard isRunning, let reason = pending else { return }
        pending = nil
        cancelPending = nil
        onSettled(reason)
    }
}
