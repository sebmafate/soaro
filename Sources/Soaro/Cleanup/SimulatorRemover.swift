import Foundation

/// Résultat de la suppression d'UN appareil (SL9). Un seul cas à la fois ; le lot (`SimulatorRemovalSummary`) les additionne.
enum SimulatorRemovalResult: Equatable {
    /// Supprimé par `simctl` ; `freed` = taille du dossier avant moins taille après, 0 si l'après est plus gros (plancher à zéro).
    case removed(freed: UInt64)
    /// Absent de la liste fraîche : quelqu'un l'a déjà supprimé. Ce n'est pas un échec.
    case alreadyGone
    /// État autre que `Shutdown` à la revérification : jamais touché (R5). Le nom est celui de la liste fraîche, tel quel.
    case running(name: String)
    /// La commande a échoué (code non nul, signal, sortie tronquée, lancement impossible). Le dossier n'est pas touché.
    case failed
    /// Le dossier de l'appareil n'est pas strictement sous le dossier personnel (ADR 0006) : aucune commande lancée.
    case refused
    /// La liste fraîche n'a pas pu être lue (hors délai : `timedOut`) : aucune suppression.
    case couldNotCheck
    /// Délai dépassé (relecture ou suppression) : le lot s'arrête.
    case timedOut
}

extension SimulatorScanner {
    /// Supprime UN appareil, dans cet ordre, synchrone (jamais sur l'acteur principal) :
    /// 1. relecture de la liste, juste avant (R5) : absent → `alreadyGone`, état autre que `Shutdown` → `running(nom)` ;
    /// 2. portée : le dossier de l'appareil doit être strictement sous le dossier personnel (ADR 0006), sinon `refused` ;
    /// 3. taille du dossier avant ;
    /// 4. `xcrun simctl delete <udid>` ; si, et seulement si, elle réussit : taille après, `freed` = avant moins après (R7).
    /// Aucun repli : si l'outil échoue, le dossier n'est jamais supprimé à la main.
    /// - Parameters:
    ///   - runner: sans valeur par défaut (ADR 0009).
    ///   - xcrunPath: chemin absolu de la porte `ToolLocator.simulatorXcrunPath`, `nil` si l'outil est absent.
    ///   - home: dossier personnel (le vrai, sauf dans les tests).
    ///   - measure: taille allouée d'un dossier.
    static func remove(runner: CommandRunner,
                       xcrunPath: String?,
                       home: URL,
                       measure: (URL) -> UInt64,
                       udid: String) -> SimulatorRemovalResult {
        // 1. Revérification de l'état.
        let listing = list(runner: runner, xcrunPath: xcrunPath)
        switch listing.status {
        case .ok: break
        case .timedOut: return .timedOut
        case .toolNotFound, .commandFailed, .outputNotReadable: return .couldNotCheck
        }
        guard let device = listing.devices.first(where: { $0.udid.caseInsensitiveCompare(udid) == .orderedSame }) else {
            return .alreadyGone
        }
        // Tout état autre que « Shutdown » (Booted, Booting, Shutting Down, inconnu…) compte comme en cours d'exécution.
        guard device.state == "Shutdown" else { return .running(name: device.name) }

        // 2. Portée : strictement sous le vrai dossier personnel.
        guard let folder = deviceFolder(udid: udid, home: home), CleanupService.isSafeToDelete(folder) else { return .refused }

        // 3 et 4. Mesure avant, suppression par l'outil, mesure après.
        let before = measure(folder)
        switch delete(runner: runner, xcrunPath: xcrunPath, udid: udid) {
        case .removed:
            let after = measure(folder)
            return .removed(freed: before > after ? before - after : 0)
        case .timedOut: return .timedOut
        case .failed, .toolNotFound: return .failed
        }
    }
}
