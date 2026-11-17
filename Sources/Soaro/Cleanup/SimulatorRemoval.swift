import Foundation

/// Bilan d'un lot de suppressions d'un groupe d'appareils (SL9, R4, R5, R7) : tout est PUR. Le texte du toast, lui, est UN seul : celui de
/// `DeviceRemovalSummary.toast` (un lot iOS seul est un lot mixte sans Android).
struct SimulatorRemovalSummary: Equatable {
    /// Appareils réellement supprimés.
    private(set) var removedCount = 0
    /// Espace libéré, somme des « avant moins après » (R7).
    private(set) var freed: UInt64 = 0
    /// Appareils non supprimés : en cours d'exécution, échec, refus, état illisible (et ceux jamais essayés après ce dernier cas).
    /// « Déjà disparu » n'en fait pas partie.
    private(set) var failureCount = 0
    /// Noms (listage frais) des appareils refusés parce qu'ils tournaient.
    private(set) var runningNames: [String] = []
    /// Un délai dépassé a arrêté le lot.
    private(set) var timedOut = false
    /// Cibles dont le résultat est connu (tout sauf les cibles jamais essayées).
    private(set) var attemptedCount = 0
    /// Cibles jamais essayées parce que le bouton Retour a arrêté le lot : elles ne sont pas supprimées, et le toast ne doit pas
    /// laisser croire le contraire. Ce ne sont pas des échecs. (Après un délai dépassé le toast ne donne aucun compte : non utilisé.)
    private(set) var untriedCount = 0

    /// Fait tourner le lot, dans l'ordre d'affichage.
    /// - L'annulation (bouton Retour) est interrogée AVANT chaque cible : les cibles restantes ne sont pas essayées ; elles sont
    ///   comptées à part (`untriedCount`), ni supprimées ni échouées.
    /// - « Délai dépassé » arrête le lot (les cibles restantes ne sont pas essayées) et lève `timedOut`.
    /// - « Impossible de vérifier » arrête le lot ; ce cas et toutes les cibles restantes comptent chacun comme un échec.
    /// - Parameter remove: supprime une cible (un UDID, ou un AVD pour `DeviceRemovalSummary`) ; synchrone, appelé hors de l'acteur principal.
    static func run<Target>(targets: [Target], isCancelled: () -> Bool, remove: (Target) -> SimulatorRemovalResult) -> SimulatorRemovalSummary {
        var summary = SimulatorRemovalSummary()
        for (index, target) in targets.enumerated() {
            if isCancelled() {
                summary.untriedCount = targets.count - index
                break
            }
            let result = remove(target)
            summary.add(result)
            if result == .timedOut { break }
            if result == .couldNotCheck {
                summary.failureCount += targets.count - index - 1
                break
            }
        }
        return summary
    }

    /// Ajoute le résultat d'une cible.
    mutating func add(_ result: SimulatorRemovalResult) {
        attemptedCount += 1
        switch result {
        case .removed(let amount):
            removedCount += 1
            freed += amount
        case .alreadyGone:
            break
        case .running(let name):
            failureCount += 1
            runningNames.append(name)
        case .failed, .refused, .couldNotCheck:
            failureCount += 1
        case .timedOut:
            timedOut = true
        }
    }
}
