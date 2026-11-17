import Foundation

/// Bilan d'un lot de suppressions de simulateurs et texte du toast (SL9, R4, R5, R7) : tout est PUR (locale explicite).
/// Les noms d'appareils ne sont jamais des clés de catalogue : ils sont insérés tels quels dans le texte.
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

    /// Fait tourner le lot, dans l'ordre d'affichage.
    /// - L'annulation (bouton Retour) est interrogée AVANT chaque cible : les cibles restantes ne sont ni essayées ni comptées.
    /// - « Délai dépassé » arrête le lot (les cibles restantes ne sont pas essayées) et lève `timedOut`.
    /// - « Impossible de vérifier » arrête le lot ; ce cas et toutes les cibles restantes comptent chacun comme un échec.
    /// - Parameter remove: supprime une cible (un UDID) ; synchrone, appelé hors de l'acteur principal.
    static func run(targets: [String], isCancelled: () -> Bool, remove: (String) -> SimulatorRemovalResult) -> SimulatorRemovalSummary {
        var summary = SimulatorRemovalSummary()
        for (index, target) in targets.enumerated() {
            if isCancelled() { break }
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

    /// Texte du toast, morceaux joints par « · » :
    /// - l'espace libéré d'abord, quand au moins un appareil a été supprimé, ou quand il n'y a ni échec ni délai dépassé ;
    /// - puis : délai dépassé → « did not answer » ; sinon un seul échec, qui est un appareil en cours d'exécution → son nom ;
    ///   sinon, s'il y a des échecs → leur nombre (les appareils en cours d'exécution inclus).
    func toast(locale: Locale = .current) -> String {
        var parts: [String] = []
        if removedCount > 0 || (failureCount == 0 && !timedOut) {
            parts.append(String(localized: "\(Format.fileBytes(freed, locale: locale)) freed", locale: locale))
        }
        if timedOut {
            parts.append(String(localized: "Xcode’s simulator service did not answer. Try again in a moment.", locale: locale))
        } else if failureCount == 1, let name = runningNames.first, runningNames.count == 1 {
            parts.append(String(localized: "“\(name)” is running: quit it first.", locale: locale))
        } else if failureCount > 0 {
            parts.append(String(localized: "Devices that could not be removed: \(failureCount)", locale: locale))
        }
        return parts.joined(separator: " · ")
    }
}
