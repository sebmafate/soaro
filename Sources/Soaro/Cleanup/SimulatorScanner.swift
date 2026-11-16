import Foundation

/// Un simulateur Apple tel que `xcrun simctl list devices -j` le décrit.
/// On ne lit jamais `dataPath` ni `dataPathSize` : la taille vient du disque (espace alloué), le chemin est reconstruit
/// à partir de l'UDID validé.
struct SimulatorDevice: Equatable {
    /// Identifiant (forme UUID, validé : il sert à construire un chemin).
    let udid: String
    let name: String
    /// `deviceTypeIdentifier` (le modèle), absent si l'outil ne le donne pas.
    let modelIdentifier: String?
    /// Identifiant de l'environnement d'exécution, p. ex. `com.apple.CoreSimulator.SimRuntime.iOS-26-2`.
    let runtimeIdentifier: String
    /// Nom lisible, p. ex. `iOS 26.2` (sinon l'identifiant brut).
    let runtimeName: String
    /// État brut (`Shutdown`, `Booted`, `Booting`, `Shutting Down`…). Absent : `Unknown`.
    let state: String
    let isAvailable: Bool
    /// Dernière utilisation (clé `lastUsedAt`), `nil` si absente ou illisible.
    let lastUsed: Date?
}

enum SimulatorScanner {
    // MARK: Lecture de la sortie de simctl

    /// Lit la sortie JSON de `simctl list devices -j`.
    /// - Returns: `nil` si la sortie est illisible (JSON cassé, racine qui n'est pas un objet, clé `devices` absente) ;
    ///   une liste (éventuellement vide) sinon. Une entrée sans UDID valide est ignorée, les autres sont gardées.
    ///   Triée par environnement puis UDID, pour un résultat stable.
    static func parse(_ data: Data) -> [SimulatorDevice]? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let runtimes = root["devices"] as? [String: Any] else { return nil }

        var result: [SimulatorDevice] = []
        var seen = Set<String>()
        for runtimeID in runtimes.keys.sorted() {
            guard let entries = runtimes[runtimeID] as? [Any] else { continue }
            var batch: [SimulatorDevice] = []
            for case let entry as [String: Any] in entries {
                guard let udid = entry["udid"] as? String, isValidUDID(udid) else { continue }
                let availabilityError = entry["availabilityError"]
                batch.append(SimulatorDevice(
                    udid: udid,
                    name: entry["name"] as? String ?? "",
                    modelIdentifier: entry["deviceTypeIdentifier"] as? String,
                    runtimeIdentifier: runtimeID,
                    runtimeName: runtimeName(runtimeID),
                    state: entry["state"] as? String ?? "Unknown",
                    isAvailable: entry["isAvailable"] as? Bool ?? (availabilityError == nil),
                    lastUsed: lastUsed(in: entry)))
            }
            for device in batch.sorted(by: { $0.udid < $1.udid }) where seen.insert(device.udid.lowercased()).inserted {
                result.append(device)
            }
        }
        return result
    }

    /// Un UDID est valide s'il a la forme d'un UUID : c'est la seule chose qui sert ensuite à construire un chemin.
    static func isValidUDID(_ text: String) -> Bool {
        text.range(of: "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$", options: .regularExpression) != nil
    }

    /// `com.apple.CoreSimulator.SimRuntime.iOS-26-2` devient `iOS 26.2` ; tout autre format reste tel quel.
    static func runtimeName(_ identifier: String) -> String {
        let prefix = "com.apple.CoreSimulator.SimRuntime."
        guard identifier.hasPrefix(prefix) else { return identifier }
        let rest = String(identifier.dropFirst(prefix.count))
        guard rest.range(of: "^[A-Za-z]+-[0-9]+(-[0-9]+)*$", options: .regularExpression) != nil,
              let dash = rest.firstIndex(of: "-") else { return identifier }
        let platform = rest[..<dash]
        let version = rest[rest.index(after: dash)...].replacingOccurrences(of: "-", with: ".")
        return "\(platform) \(version)"
    }

    /// `lastUsedAt` d'abord ; `lastBootedAt` seulement si `lastUsedAt` est ABSENT. Aucune autre source (pas de date de fichier).
    private static func lastUsed(in entry: [String: Any]) -> Date? {
        if let raw = entry["lastUsedAt"] { return (raw as? String).flatMap(parseDate) }
        if let raw = entry["lastBootedAt"] { return (raw as? String).flatMap(parseDate) }
        return nil
    }

    /// Dates ISO 8601, avec ou sans fractions de seconde.
    private static func parseDate(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}
