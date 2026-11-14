import Foundation

struct LargeFile: Identifiable, Equatable {
    let url: URL
    let size: UInt64
    let modified: Date?
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var folder: String { (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath }
}

/// Cherche les gros fichiers de l'utilisateur. Les paquets (`.photoslibrary`, `.app`, bundles de VM…)
/// sont ignorés : on ne propose jamais de supprimer l'intérieur d'une bibliothèque.
enum LargeFileScanner {
    /// Dossiers jamais parcourus (gérés ailleurs ou sans intérêt).
    static let skippedNames: Set<String> = ["Library", "Applications", ".Trash", "node_modules"]

    /// Sorties de build générées : inutile de les parcourir pour chercher des fichiers « oubliés ».
    /// (Uniquement pour le scan : ce n'est PAS une liste de choses à supprimer, un `build/` peut contenir des fichiers versionnés.)
    static let generatedNames: Set<String> = ["build", "dist", "out", "target", "Pods", "DerivedData"]
    static let projectMarkers = ["package.json", "build.gradle", "build.gradle.kts", "settings.gradle", "Cargo.toml", "pom.xml",
                                 "Package.swift", "Podfile", "pubspec.yaml", "CMakeLists.txt", "Makefile"]

    static func isGeneratedOutput(_ url: URL) -> Bool {
        guard generatedNames.contains(url.lastPathComponent) else { return false }
        let parent = url.deletingLastPathComponent()
        return projectMarkers.contains { FileManager.default.fileExists(atPath: parent.appendingPathComponent($0).path) }
    }

    /// Racines par défaut : tous les dossiers visibles du dossier personnel.
    static func defaultRoots(home: URL = URL(fileURLWithPath: NSHomeDirectory())) -> [URL] {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: home, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        return children.filter {
            !skippedNames.contains($0.lastPathComponent)
                && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    static func scan(
        roots: [URL],
        minSize: UInt64,
        limit: Int = 200,
        isCancelled: () -> Bool = { false }
    ) -> [LargeFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        let keySet = Set(keys)          // construit une fois : ce set était recréé à chaque fichier (≈ 1 M d'allocations)
        var found: [LargeFile] = []

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                if isCancelled() { return sorted(found, limit) }
                guard let values = try? url.resourceValues(forKeys: keySet) else { continue }
                if values.isDirectory == true {
                    if skippedNames.contains(url.lastPathComponent) || isGeneratedOutput(url) || DevArtifactScanner.isArtifact(url) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard values.isRegularFile == true, let size = values.totalFileAllocatedSize, UInt64(size) >= minSize else { continue }
                found.append(LargeFile(url: url, size: UInt64(size), modified: values.contentModificationDate))
            }
        }
        return sorted(found, limit)
    }

    private static func sorted(_ files: [LargeFile], _ limit: Int) -> [LargeFile] {
        Array(files.sorted { $0.size > $1.size }.prefix(limit))
    }

    /// Met à la corbeille (récupérable). Refuse tout ce qui est hors du dossier personnel.
    static func trash(_ files: [LargeFile]) -> (freed: UInt64, failures: Int) {
        var freed: UInt64 = 0
        var failures = 0
        for file in files {
            guard CleanupService.isSafeToDelete(file.url) else { failures += 1; continue }
            do {
                try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                freed += file.size
            } catch {
                failures += 1
            }
        }
        return (freed, failures)
    }
}
