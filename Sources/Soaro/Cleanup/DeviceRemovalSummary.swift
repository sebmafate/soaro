import Foundation

/// Bilan d'un lot MIXTE (simulateurs iOS et appareils Android) et texte du toast (SL11, R17, R8, R7) : tout est PUR (locale explicite).
/// Deux groupes, chacun avec son `SimulatorRemovalSummary` (les règles de SL9 y valent : « impossible de vérifier » arrête CE groupe,
/// un délai dépassé d'iOS arrête le reste d'iOS). Un échec ou un délai dépassé dans un groupe n'arrête JAMAIS l'autre (D4).
/// Les noms d'appareils ne sont jamais des clés de catalogue : ils sont insérés tels quels dans le texte.
struct DeviceRemovalSummary: Equatable {
    let ios: SimulatorRemovalSummary
    let android: SimulatorRemovalSummary

    /// Fait tourner le lot : les cibles iOS d'abord, puis les cibles Android, chacune dans l'ordre d'affichage, avec LE MÊME `isCancelled`.
    /// Le bouton Retour arrête tout : les cibles restantes des deux groupes comptent comme « jamais essayées ».
    /// - Parameters:
    ///   - removeIOS: supprime un simulateur (un UDID) ; synchrone, hors de l'acteur principal.
    ///   - removeAndroid: supprime un AVD (`AndroidEmulatorScanner.remove`) ; ne rend jamais `timedOut`.
    static func run(iosTargets: [String], androidTargets: [AndroidRemovalTarget], isCancelled: () -> Bool,
                    removeIOS: (String) -> SimulatorRemovalResult,
                    removeAndroid: (AndroidRemovalTarget) -> SimulatorRemovalResult) -> DeviceRemovalSummary {
        let ios = SimulatorRemovalSummary.run(targets: iosTargets, isCancelled: isCancelled, remove: removeIOS)
        let android = SimulatorRemovalSummary.run(targets: androidTargets, isCancelled: isCancelled, remove: removeAndroid)
        return DeviceRemovalSummary(ios: ios, android: android)
    }

    /// Texte du toast, morceaux joints par « · ». « Non supprimés » = échecs + cibles jamais essayées après un Retour, des deux groupes.
    /// - Chaîne VIDE quand Retour est arrivé avant la moindre tentative : il n'y a rien à dire.
    /// - L'espace libéré d'abord (la somme), quand au moins un appareil a été supprimé, ou quand rien n'est « non supprimé » et
    ///   qu'iOS n'a pas dépassé son délai ;
    /// - puis : iOS a dépassé son délai → « did not answer », plus le nombre d'appareils Android non supprimés s'il y en a ;
    ///   sinon un seul appareil non supprimé, en cours d'exécution → son nom ; sinon, s'il y en a → leur nombre.
    func toast(locale: Locale = .current) -> String {
        let untried = ios.untriedCount + android.untriedCount
        if ios.attemptedCount + android.attemptedCount == 0 && untried > 0 { return "" }
        let notRemoved = ios.failureCount + android.failureCount + untried
        let removed = ios.removedCount + android.removedCount
        let freed = ios.freed + android.freed
        let timedOut = ios.timedOut || android.timedOut
        let runningNames = ios.runningNames + android.runningNames

        var parts: [String] = []
        if removed > 0 || (notRemoved == 0 && !timedOut) {
            parts.append(String(localized: "\(Format.fileBytes(freed, locale: locale)) freed", locale: locale))
        }
        if timedOut {
            parts.append(String(localized: "Xcode’s simulator service did not answer. Try again in a moment.", locale: locale))
            let androidNotRemoved = android.failureCount + android.untriedCount
            if androidNotRemoved > 0 {
                parts.append(String(localized: "Devices that could not be removed: \(androidNotRemoved)", locale: locale))
            }
        } else if notRemoved == 1, let name = runningNames.first, runningNames.count == 1 {
            parts.append(String(localized: "“\(name)” is running: quit it first.", locale: locale))
        } else if notRemoved > 0 {
            parts.append(String(localized: "Devices that could not be removed: \(notRemoved)", locale: locale))
        }
        return parts.joined(separator: " · ")
    }
}
