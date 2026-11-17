import Foundation

struct CleanupResult {
    var freed: UInt64
    var failures: Int
    var error: String?
}

/// Scanne et nettoie des emplacements connus et sûrs. Ne touche jamais en dehors du
/// dossier personnel de l'utilisateur.
enum CleanupService {
    /// Le vrai dossier personnel. Seul `isSafeToDelete` s'y réfère toujours : un dossier injecté
    /// pour les tests ne peut donc jamais élargir le périmètre des suppressions (ADR 0006).
    static var realHome: URL { URL(fileURLWithPath: NSHomeDirectory()) }

    static func directory(for kind: CleanupKind, home: URL = realHome) -> URL {
        switch kind {
        case .caches: home.appendingPathComponent("Library/Caches")
        case .logs: home.appendingPathComponent("Library/Logs")
        case .derivedData: home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        case .trash: home.appendingPathComponent(".Trash")
        case .npmCache: home.appendingPathComponent(".npm/_cacache")
        case .gradleCache: home.appendingPathComponent(".gradle/caches")
        case .cargoCache: home.appendingPathComponent(".cargo/registry/cache")
        // Dossier par défaut seulement : NUGET_PACKAGES et globalPackagesFolder ne sont pas lus.
        case .nugetCache: home.appendingPathComponent(".nuget/packages")
        case .xcodeDeviceSupport: home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport")
        case .simulatorCaches: home.appendingPathComponent("Library/Developer/CoreSimulator/Caches")
        }
    }

    /// Éléments de premier niveau supprimables pour ce type de nettoyage.
    static func items(for kind: CleanupKind, home: URL = realHome) -> [URL]? {
        let dir = directory(for: kind, home: home)
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: []
        ) else { return nil }

        switch kind {
        case .caches:
            // On laisse les caches système d'Apple tranquilles.
            return children.filter { !$0.lastPathComponent.hasPrefix("com.apple.") }
        default:
            return children
        }
    }

    /// Taille récupérable, ou `nil` si le dossier est inaccessible / inexistant.
    static func size(of kind: CleanupKind, home: URL = realHome) -> UInt64? {
        guard let items = items(for: kind, home: home) else { return nil }
        return items.reduce(0) { $0 + allocatedSize(of: $1) }
    }

    /// `measure` : la mesure de taille, remplaçable par les tests pour prouver le « avant moins après » sans dépendre du disque.
    static func clean(_ kind: CleanupKind, home: URL = realHome, measure: (URL) -> UInt64 = { allocatedSize(of: $0) }) -> CleanupResult {
        if kind == .trash { return emptyTrash() }

        guard let items = items(for: kind, home: home) else {
            return CleanupResult(freed: 0, failures: 0, error: String(localized: "Folder not accessible"))
        }
        var freed: UInt64 = 0
        var failures = 0
        for item in items {
            guard isSafeToDelete(item) else { failures += 1; continue }
            let before = measure(item)
            do {
                try FileManager.default.removeItem(at: item)
                freed += before
            } catch {
                failures += 1   // fichier en cours d'utilisation, protégé, etc.
                // Suppression interrompue : on compte ce qui a vraiment disparu (avant moins après, jamais négatif).
                let after = measure(item)
                if before > after { freed += before - after }
            }
        }
        return CleanupResult(freed: freed, failures: failures, error: nil)
    }

    /// Vide la corbeille via le Finder (nécessite l'autorisation d'automatisation).
    private static func emptyTrash() -> CleanupResult {
        let before = size(of: .trash) ?? 0
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "tell application \"Finder\" to empty trash"]
        let err = Pipe()
        task.standardError = err
        task.standardOutput = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return CleanupResult(freed: 0, failures: 0, error: error.localizedDescription)
        }
        guard task.terminationStatus == 0 else {
            let message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return CleanupResult(freed: 0, failures: 0, error: message.isEmpty ? String(localized: "Finder refused the command") : message)
        }
        return CleanupResult(freed: before, failures: 0, error: nil)
    }

    // MARK: Sécurité

    /// Refuse tout chemin hors du dossier personnel ou le dossier personnel lui-même.
    static func isSafeToDelete(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let homePath = realHome.standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasPrefix(homePath + "/") && path.count > homePath.count + 1
    }

    // MARK: Taille

    static func allocatedSize(of url: URL) -> UInt64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }

        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        if !isDirectory.boolValue {
            return UInt64((try? url.resourceValues(forKeys: keys).totalFileAllocatedSize) ?? 0)
        }
        guard let enumerator = fm.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: UInt64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += UInt64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
