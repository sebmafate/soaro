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

// MARK: - Scan (lecture seule)

/// Un simulateur avec la taille réelle (espace alloué) de son dossier.
struct SizedSimulator: Equatable {
    let device: SimulatorDevice
    let size: UInt64
}

/// Résultat d'un scan. Un état autre que `.ok` donne une liste vide : la section se cache, rien d'autre ne casse.
struct SimulatorScan: Equatable {
    enum Status: Equatable {
        case ok
        /// `xcrun` absent, ou impossible à lancer.
        case toolNotFound
        /// Code de sortie non nul (`nil` : commande refusée par le lanceur avant tout lancement).
        case commandFailed(exitCode: Int32?)
        case timedOut
        /// JSON illisible, ou sortie tronquée (jamais d'analyse partielle).
        case outputNotReadable
    }

    let status: Status
    let devices: [SizedSimulator]
    /// Le scan a été annulé pendant la mesure des tailles : `devices` ne contient que les appareils déjà mesurés.
    let cancelled: Bool

    init(status: Status, devices: [SizedSimulator] = [], cancelled: Bool = false) {
        self.status = status
        self.devices = devices
        self.cancelled = cancelled
    }
}

/// Résultat de la lecture de la liste : l'état, et les appareils SANS taille.
struct SimulatorListing: Equatable {
    let status: SimulatorScan.Status
    let devices: [SimulatorDevice]

    init(status: SimulatorScan.Status, devices: [SimulatorDevice] = []) {
        self.status = status
        self.devices = devices
    }
}

extension SimulatorScanner {
    /// Arguments de la commande : `xcrun simctl list devices -j` (liste seule, jamais de modification).
    static let listArguments = ["simctl", "list", "devices", "-j"]
    /// Délai de `simctl list` (A8).
    static let listTimeLimit: TimeInterval = 60
    /// Borne de la sortie : 8 Mio (A8).
    static let outputLimit = 8 * 1024 * 1024

    /// Lecture seule de la liste, SANS tailles : une commande, synchrone. Mêmes états que `scan`.
    /// - Parameters:
    ///   - runner: sans valeur par défaut (ADR 0006) : un test ne lance jamais le vrai outil par mégarde.
    ///   - xcrunPath: chemin absolu de `xcrun` ; `nil` quand l'outil est absent (rien n'est alors lancé).
    static func list(runner: CommandRunner, xcrunPath: String?) -> SimulatorListing {
        guard let xcrunPath else { return SimulatorListing(status: .toolNotFound) }

        let outcome = runner.run(executable: xcrunPath, arguments: listArguments, timeLimit: listTimeLimit, outputLimit: outputLimit)
        let output: CommandOutput
        switch outcome {
        case .failedToLaunch: return SimulatorListing(status: .toolNotFound)
        case .refused: return SimulatorListing(status: .commandFailed(exitCode: nil))
        case .timedOut: return SimulatorListing(status: .timedOut)
        case .completed(let value): output = value
        }
        // La sortie d'erreur n'est ni analysée ni conservée (elle peut contenir des chemins personnels).
        // Une sortie tronquée est toujours « illisible », quel que soit le code : le lanceur a tué le processus (signal 9),
        // ce n'est pas un échec de la commande.
        if output.truncated { return SimulatorListing(status: .outputNotReadable) }
        // Fin par un signal sans que le lanceur y soit pour rien (plantage) : pas de code de sortie à montrer.
        if output.termination == .signaled { return SimulatorListing(status: .commandFailed(exitCode: nil)) }
        if output.exitCode != 0 { return SimulatorListing(status: .commandFailed(exitCode: output.exitCode)) }
        guard let devices = parse(output.stdout) else { return SimulatorListing(status: .outputNotReadable) }
        return SimulatorListing(status: .ok, devices: devices)
    }

    /// Dossier d'un appareil : `<home>/Library/Developer/CoreSimulator/Devices/<udid>`, et seulement pour un UDID valide
    /// (forme UUID) : il ne peut donc pas sortir du dossier des appareils. `nil` sinon.
    static func deviceFolder(udid: String, home: URL) -> URL? {
        guard isValidUDID(udid) else { return nil }
        return home.appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true)
            .appendingPathComponent(udid, isDirectory: true)
    }

    /// Liste les simulateurs et mesure leur dossier. LECTURE SEULE, synchrone, une seule commande.
    /// - Parameters:
    ///   - runner: sans valeur par défaut (ADR 0006) : un test ne lance jamais le vrai outil par mégarde.
    ///   - xcrunPath: chemin absolu trouvé par `ToolLocator`, `nil` s'il est absent.
    ///   - home: dossier personnel ; les tailles ne sont lues que sous `Library/Developer/CoreSimulator/Devices/<udid>`.
    ///   - isCancelled: interrogé avant chaque dossier mesuré.
    static func scan(runner: CommandRunner,
                     xcrunPath: String?,
                     home: URL = URL(fileURLWithPath: NSHomeDirectory()),
                     isCancelled: () -> Bool = { false }) -> SimulatorScan {
        let listing = list(runner: runner, xcrunPath: xcrunPath)
        guard listing.status == .ok else { return SimulatorScan(status: listing.status) }

        var sized: [SizedSimulator] = []
        for device in listing.devices {
            if isCancelled() { return SimulatorScan(status: .ok, devices: sized, cancelled: true) }
            // `parse` a validé l'UDID : `deviceFolder` ne peut pas rendre `nil` ici.
            let size = deviceFolder(udid: device.udid, home: home).map { CleanupService.allocatedSize(of: $0) } ?? 0
            sized.append(SizedSimulator(device: device, size: size))
        }
        return SimulatorScan(status: .ok, devices: sized)
    }
}
