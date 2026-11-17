import Foundation

/// Trouve un outil externe par chemin ABSOLU (ADR 0009) : jamais de PATH, jamais de shell, jamais `which`.
/// Volontairement minimal : `xcrun` (simulateurs), `ps` (émulateurs Android en cours d'exécution) et la recherche du SDK Android.
/// Les candidats de Docker (SL13) seront ajoutés avec leur tranche.
enum ToolLocator {
    /// Candidats pour les simulateurs iOS : exactement `/usr/bin/xcrun` (le relais installé par macOS).
    static let simulatorCandidates = ["/usr/bin/xcrun"]

    /// Candidats pour la liste des processus (émulateurs Android en cours d'exécution) : exactement `/bin/ps`.
    static let processListCandidates = ["/bin/ps"]

    /// Cherche le SDK Android (R18). Fonction PURE : ne lance rien, ne lit jamais le PATH ni aucune autre variable.
    /// 1. De `ANDROID_SDK_ROOT` puis `ANDROID_HOME`, la PREMIÈRE variable définie et non vide décide : si sa valeur est un chemin
    ///    absolu vers un dossier existant, c'est le SDK ; sinon (dossier absent, fichier, chemin relatif) le résultat est `nil`,
    ///    SANS repli (un `ANDROID_SDK_ROOT` vers un dossier absent cache le groupe Android).
    /// 2. Seulement quand aucune des deux n'est définie : `<home>/Library/Android/sdk` s'il existe, sinon `nil`.
    /// - Parameters:
    ///   - environment: l'environnement, TOUJOURS injecté (jamais `ProcessInfo` ici).
    ///   - isDirectory: « ce chemin est un dossier » ; le vrai disque par défaut, un faux dans les tests.
    static func androidSDK(environment: [String: String],
                           home: URL,
                           isDirectory: (String) -> Bool = { DiskToolFileSystem().isDirectory($0) }) -> AndroidSDKLocation? {
        let variables: [(name: String, source: AndroidSDKLocation.Source)] = [
            ("ANDROID_SDK_ROOT", .androidSDKRoot), ("ANDROID_HOME", .androidHome)]
        for variable in variables {
            guard let value = environment[variable.name], !value.isEmpty else { continue }
            guard value.hasPrefix("/"), isDirectory(value) else { return nil }
            return AndroidSDKLocation(path: value, source: variable.source)
        }
        let fallback = home.appendingPathComponent("Library/Android/sdk", isDirectory: true).path
        return isDirectory(fallback) ? AndroidSDKLocation(path: fallback, source: .defaultLocation) : nil
    }

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

/// Le SDK Android trouvé : son chemin et d'où il vient (affiché par `--scan`).
struct AndroidSDKLocation: Equatable {
    enum Source: String, Equatable {
        case androidSDKRoot = "ANDROID_SDK_ROOT"
        case androidHome = "ANDROID_HOME"
        /// `<home>/Library/Android/sdk`, le dossier par défaut d'Android Studio.
        case defaultLocation = "default"
    }

    let path: String
    let source: Source
}
