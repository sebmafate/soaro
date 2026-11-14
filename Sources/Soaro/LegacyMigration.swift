import Foundation

/// Reprend les données des versions précédentes de l'app, qui portaient d'autres noms ou un autre identifiant
/// (`local.soaro`, « Accalmie », puis « MyCleaner ») : historique des mesures et préférences.
/// Sans cela, chaque changement ferait repartir de zéro.
enum LegacyMigration {
    /// Une ancienne version : son identifiant (domaine de préférences) et son dossier dans Application Support.
    struct Source: Equatable {
        let bundleID: String
        let folderName: String
        /// Clés de position de fenêtre dont le nom contenait l'ancien nom : (ancienne clé, nouvelle clé).
        var renamedKeys: [(String, String)] = []

        static func == (l: Source, r: Source) -> Bool { l.bundleID == r.bundleID && l.folderName == r.folderName }
    }

    /// Du plus récent au plus ancien : en cas de conflit, la version la plus récente l'emporte.
    static let sources: [Source] = [
        // Identifiant provisoire de Soaro, avant l'achat du domaine soaro.app : même dossier de données, autres préférences.
        Source(bundleID: "local.soaro", folderName: "Soaro"),
        Source(bundleID: "local.accalmie", folderName: "Accalmie",
               renamedKeys: [("NSWindow Frame AccalmieMainWindow", "NSWindow Frame SoaroMainWindow")]),
        Source(bundleID: "com.mycleaner.app", folderName: "MyCleaner"),
    ]

    static let currentFolderName = "Soaro"
    static let doneFlag = "legacyMigrationDone"

    /// Préférences reprises (les seules clés que l'app écrit) : réglages, trafic du jour, épingle de la fenêtre,
    /// conseils ignorés, seuils de couleur et position de la fenêtre.
    static var migratedKeys: [String] {
        var keys = Array(SettingsKey.defaults.keys) + ["traffic.day", "traffic.down", "traffic.up", "windowPinned", "dismissedAdvice", "NSWindow Frame SoaroMainWindow"]
        for measure in ["load", "disk", "battery"] {
            for level in ["medium", "high", "critical"] { keys.append("threshold.\(measure).\(level)") }
        }
        return keys
    }

    static var defaultSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// À appeler au tout début du lancement, AVANT `register(defaults:)` (sinon les valeurs par défaut
    /// masqueraient les « clés absentes ») et avant l'ouverture de la base d'historique.
    static func run(
        supportDirectory: URL = defaultSupportDirectory,
        defaults: UserDefaults = .standard,
        legacyPreferences: (String) -> [String: Any]? = { UserDefaults.standard.persistentDomain(forName: $0) }
    ) {
        guard !defaults.bool(forKey: doneFlag) else { return }
        for source in sources {
            // Même dossier que l'actuel : rien à déplacer (et surtout pas de risque de le vider).
            if source.folderName != currentFolderName {
                moveFolder(
                    from: supportDirectory.appendingPathComponent(source.folderName, isDirectory: true),
                    to: supportDirectory.appendingPathComponent(currentFolderName, isDirectory: true)
                )
            }
            if let legacy = legacyPreferences(source.bundleID) {
                copyPreferences(legacy, into: defaults)
                for (old, new) in source.renamedKeys where defaults.object(forKey: new) == nil {
                    if let value = legacy[old] { defaults.set(value, forKey: new) }
                }
            }
        }
        defaults.set(true, forKey: doneFlag)
    }

    /// Déplace chaque fichier de l'ancien dossier vers le nouveau, sans jamais écraser un fichier déjà présent.
    /// (La base SQLite est déplacée avec ses fichiers `-wal` et `-shm`, ensemble.)
    @discardableResult
    static func moveFolder(from old: URL, to new: URL, fileManager: FileManager = .default) -> Int {
        guard let items = try? fileManager.contentsOfDirectory(atPath: old.path), !items.isEmpty else { return 0 }
        try? fileManager.createDirectory(at: new, withIntermediateDirectories: true)

        var moved = 0
        for name in items {
            let source = old.appendingPathComponent(name)
            let target = new.appendingPathComponent(name)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            if (try? fileManager.moveItem(at: source, to: target)) != nil { moved += 1 }
        }
        // L'ancien dossier ne disparaît que s'il est vide : on ne supprime rien d'autre.
        if (try? fileManager.contentsOfDirectory(atPath: old.path))?.isEmpty == true {
            try? fileManager.removeItem(at: old)
        }
        return moved
    }

    /// Copie les seules clés connues, et seulement si l'utilisateur n'a pas déjà une valeur dans la nouvelle version.
    static func copyPreferences(_ legacy: [String: Any], into defaults: UserDefaults) {
        for key in migratedKeys {
            guard let value = legacy[key], defaults.object(forKey: key) == nil else { continue }
            defaults.set(value, forKey: key)
        }
        migrateMenuBarMode(legacy["menuBarMode"] as? String, into: defaults)
    }

    /// La toute première version avait un seul choix (`menuBarMode`) ; il est devenu une case par mesure.
    /// On le traduit pour que la barre de menus garde l'affichage choisi, sans écraser un choix plus récent.
    static func migrateMenuBarMode(_ mode: String?, into defaults: UserDefaults) {
        let flags: (cpu: Bool, memory: Bool)?
        switch mode {
        case "iconOnly": flags = (false, false)
        case "cpu": flags = (true, false)
        case "memory": flags = (false, true)
        case "cpuAndMemory": flags = (true, true)
        default: flags = nil
        }
        guard let flags else { return }
        if defaults.object(forKey: SettingsKey.menuBarCPU) == nil { defaults.set(flags.cpu, forKey: SettingsKey.menuBarCPU) }
        if defaults.object(forKey: SettingsKey.menuBarMemory) == nil { defaults.set(flags.memory, forKey: SettingsKey.menuBarMemory) }
    }
}
