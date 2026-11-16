import Foundation

/// Suggestions de simulateurs à présélectionner (R3). Fonction PURE : ni horloge, ni accès aux fichiers.
/// Deux règles, indépendantes, qui peuvent s'additionner :
/// - inactif : nombre de jours entiers depuis la dernière utilisation STRICTEMENT supérieur à la limite ;
/// - ancienne copie : même modèle et même environnement qu'un appareil plus récemment utilisé.
/// Jamais présélectionné : un appareil en cours d'exécution, un appareil sans date, un petit appareil (non listé).
enum DeviceSuggestions {
    /// Limite d'inactivité par défaut, en jours.
    /// provisoire, à confirmer par le contrôle de l'auteur sur 5 appareils
    static let defaultLimitDays = 60

    /// Sous ce seuil (strictement), un appareil est compté mais pas listé : 100 Mo (100 000 000 octets).
    static let smallDeviceThreshold: UInt64 = 100_000_000

    struct Row: Equatable {
        let device: SizedSimulator
        /// Jours entiers depuis la dernière utilisation (jamais négatif), `nil` si inconnue.
        let daysSinceLastUse: Int?
        /// Raison « inactif » : jours depuis la dernière utilisation > limite.
        let isInactive: Bool
        /// Raison « ancienne copie » : un appareil du même modèle et du même environnement est plus récent.
        let isOlderCopy: Bool
        /// État différent de `Shutdown` (Booted, Booting, Shutting Down, inconnu).
        let isRunning: Bool
        let isPreSelected: Bool
        /// Pour une « ancienne copie » : l'appareil gardé du groupe (le premier du classement : le plus récent, même petit,
        /// non listé ou en cours d'exécution). `nil` sinon.
        let keptDevice: SizedSimulator?
    }

    struct Result: Equatable {
        /// Appareils listés (≥ 100 Mo), du plus gros au plus petit (égalité : nom, puis UDID).
        let rows: [Row]
        let hiddenSmallCount: Int
        let hiddenSmallSize: UInt64
        let preSelectedCount: Int
        let preSelectedSize: UInt64
        let limitDays: Int
    }

    /// Jours entiers entre une date et `now`, jamais négatif (une date future vaut 0). Partagé avec le texte des lignes.
    static func wholeDays(from date: Date, to now: Date) -> Int { max(0, Int(now.timeIntervalSince(date) / 86_400)) }

    /// - Parameters:
    ///   - devices: tous les appareils avec leur taille (les petits servent aussi à repérer les copies).
    ///   - now: instant de référence (explicite : pas d'horloge ici).
    ///   - limitDays: limite d'inactivité, un PARAMÈTRE ; l'appelant choisit (`defaultLimitDays` tant que l'auteur n'a pas tranché).
    static func suggest(_ devices: [SizedSimulator], now: Date, limitDays: Int) -> Result {
        let limit = max(0, limitDays)

        func isRunning(_ d: SizedSimulator) -> Bool { d.device.state != "Shutdown" }
        func wholeDays(since date: Date) -> Int { Self.wholeDays(from: date, to: now) }
        /// Un appareil en cours d'exécution compte comme utilisé maintenant ; sinon sa dernière utilisation (peut manquer).
        func effectiveUse(_ d: SizedSimulator) -> Date? { isRunning(d) ? now : d.device.lastUsed }
        func groupKey(_ d: SizedSimulator) -> String {
            "\(d.device.modelIdentifier ?? d.device.name)\u{1F}\(d.device.runtimeIdentifier)"
        }

        // Anciennes copies : on regroupe TOUS les appareils (petits compris) ; le gardé est le plus récent
        // (égalité : plus gros, puis plus petit UDID).
        var olderCopies: [String: SizedSimulator] = [:]   // UDID de la copie → appareil gardé
        for (_, members) in Dictionary(grouping: devices, by: groupKey) {
            let dated = members.filter { effectiveUse($0) != nil }
            let ranked = dated.sorted { a, b in
                let da = effectiveUse(a)!, db = effectiveUse(b)!
                if da != db { return da > db }
                if a.size != b.size { return a.size > b.size }
                return a.device.udid < b.device.udid
            }
            guard let kept = ranked.first else { continue }
            for copy in ranked.dropFirst() where !isRunning(copy) { olderCopies[copy.device.udid] = kept }
        }

        var rows: [Row] = []
        var hiddenCount = 0
        var hiddenSize: UInt64 = 0
        for d in devices {
            if d.size < smallDeviceThreshold {
                hiddenCount += 1
                hiddenSize += d.size
                continue
            }
            let days = d.device.lastUsed.map(wholeDays)
            let running = isRunning(d)
            let inactive = !running && (days.map { $0 > limit } ?? false)
            let kept = olderCopies[d.device.udid]
            let older = kept != nil
            rows.append(Row(device: d, daysSinceLastUse: days, isInactive: inactive, isOlderCopy: older,
                            isRunning: running, isPreSelected: !running && (inactive || older), keptDevice: kept))
        }
        rows.sort { a, b in
            if a.device.size != b.device.size { return a.device.size > b.device.size }
            if a.device.device.name != b.device.device.name { return a.device.device.name < b.device.device.name }
            return a.device.device.udid < b.device.device.udid
        }
        let selected = rows.filter(\.isPreSelected)
        return Result(rows: rows, hiddenSmallCount: hiddenCount, hiddenSmallSize: hiddenSize,
                      preSelectedCount: selected.count, preSelectedSize: selected.reduce(0) { $0 + $1.device.size },
                      limitDays: limit)
    }
}
