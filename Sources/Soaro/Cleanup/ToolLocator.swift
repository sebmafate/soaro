import Foundation

/// Trouve un outil externe par chemin ABSOLU (ADR 0009) : jamais de PATH, jamais de shell, jamais `which`.
/// Volontairement minimal : un seul outil pour l'instant (`xcrun`). Les candidats d'Android (SL10) et de Docker (SL13)
/// seront ajoutés avec leurs tranches.
enum ToolLocator {
    /// Candidats pour les simulateurs iOS : exactement `/usr/bin/xcrun` (le relais installé par macOS).
    static let simulatorCandidates = ["/usr/bin/xcrun"]

    /// Le premier candidat qui est un fichier ordinaire exécutable, sinon `nil`.
    /// Un chemin relatif ou vide est ignoré. Ne lance rien.
    static func firstExecutable(in candidates: [String], fileManager: FileManager = .default) -> String? {
        for path in candidates where path.hasPrefix("/") {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  fileManager.isExecutableFile(atPath: path) else { continue }
            return path
        }
        return nil
    }

    /// Porte du lanceur pour les simulateurs : `/usr/bin/xcrun` n'est donné QUE si `simctl` est sur le disque
    /// (détection sans lancement) ET si `xcrun` lui-même est présent. Sinon `nil` : rien n'est lancé.
    static func simulatorXcrunPath(detection: SimulatorToolDetection,
                                   locate: ([String]) -> String? = { firstExecutable(in: $0) }) -> String? {
        guard detection.simctlPath != nil else { return nil }
        return locate(simulatorCandidates)
    }
}
