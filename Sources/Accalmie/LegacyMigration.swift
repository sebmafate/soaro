import Foundation

/// Reprend les données de la version précédente de l'app (qui s'appelait « MyCleaner ») :
/// l'historique des mesures et les préférences. Sans cela, le changement de nom ferait repartir de zéro.
enum LegacyMigration {
    static let legacyBundleID = "com.mycleaner.app"
    static let legacyFolderName = "MyCleaner"
    static let currentFolderName = "Accalmie"
    static let doneFlag = "migratedFromMyCleaner"

    /// Préférences reprises (les seules clés que l'app écrit).
    static var migratedKeys: [String] {
        Array(SettingsKey.defaults.keys) + ["traffic.day", "traffic.down", "traffic.up"]
    }

    static var defaultSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// À appeler au tout début du lancement, AVANT `register(defaults:)` (sinon les valeurs par défaut
    /// masqueraient les « clés absentes ») et avant l'ouverture de la base d'historique.
    static func run(
        supportDirectory: URL = defaultSupportDirectory,
        defaults: UserDefaults = .standard,
        legacyPreferences: [String: Any]? = UserDefaults.standard.persistentDomain(forName: legacyBundleID)
    ) {
        guard !defaults.bool(forKey: doneFlag) else { return }
        moveFolder(
            from: supportDirectory.appendingPathComponent(legacyFolderName, isDirectory: true),
            to: supportDirectory.appendingPathComponent(currentFolderName, isDirectory: true)
        )
        if let legacyPreferences { copyPreferences(legacyPreferences, into: defaults) }
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
