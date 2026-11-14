import Foundation

/// Dossier de dépendances / de build régénérable d'un projet (`node_modules`, `.build`, `target`, `Pods`).
struct DevArtifact: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case nodeModules = "node_modules"
        case swiftBuild = ".build"
        case rustTarget = "target"
        case pods = "Pods"

        /// Un dossier n'est retenu que si l'un de ces fichiers l'accompagne : c'est ce qui prouve que c'est bien un artefact.
        var manifests: [String] {
            switch self {
            case .nodeModules: ["package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb"]
            case .swiftBuild: ["Package.swift", "Package.resolved"]
            case .rustTarget: ["Cargo.toml", "Cargo.lock", "pom.xml"]
            case .pods: ["Podfile", "Podfile.lock"]
            }
        }

        var label: String {
            switch self {
            case .nodeModules: "npm"
            case .swiftBuild: "Swift"
            case .rustTarget: "Rust / Maven"
            case .pods: "CocoaPods"
            }
        }

        var restoreHint: String {
            switch self {
            case .nodeModules: "npm install"
            case .swiftBuild: "swift build"
            case .rustTarget: "cargo build"
            case .pods: "pod install"
            }
        }
    }

    let url: URL
    let kind: Kind
    var size: UInt64
    let lastActivity: Date?
    var id: String { url.path }
    var projectName: String { url.deletingLastPathComponent().lastPathComponent }
    var projectPath: String { (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath }

    func daysInactive(now: Date = Date()) -> Int? {
        lastActivity.map { max(0, Int(now.timeIntervalSince($0) / 86_400)) }
    }
}

enum DevArtifactScanner {
    /// Dossiers à ne jamais parcourir.
    static let skippedNames: Set<String> = ["Library", "Applications", ".Trash", "Pictures", "Movies", "Music", "node_modules"]
    /// Seul dossier caché exploré (c'est là que vivent certains projets de développement) ; les autres (.git, .cache…) sont ignorés.
    static let allowedHidden: Set<String> = [".t3"]
    static let maxDepth = 8
    /// Un projet inactif depuis ce nombre de jours est pré-sélectionné.
    static let staleAfterDays = 60

    /// En dessous de ce poids, un dossier n'est pas utile à lister (workspaces vides, simples liens symboliques…).
    static let minimumSize: UInt64 = 1_000_000

    static func scan(
        roots: [URL] = defaultRoots(),
        minSize: UInt64 = minimumSize,
        isCancelled: () -> Bool = { false }
    ) -> [DevArtifact] {
        var results: [DevArtifact] = []
        for root in roots {
            walk(root, depth: 0, into: &results, isCancelled: isCancelled)
            if isCancelled() { break }
        }
        return results.filter { $0.size >= minSize }.sorted { $0.size > $1.size }
    }

    static func defaultRoots(home: URL = URL(fileURLWithPath: NSHomeDirectory())) -> [URL] { [home] }

    private static func walk(_ dir: URL, depth: Int, into results: inout [DevArtifact], isCancelled: () -> Bool) {
        guard depth <= maxDepth, !isCancelled() else { return }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey], options: []
        ) else { return }

        for entry in entries {
            let name = entry.lastPathComponent
            guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }

            if let kind = DevArtifact.Kind(rawValue: name), let activity = activity(of: dir, kind: kind) {
                results.append(DevArtifact(
                    url: entry, kind: kind, size: CleanupService.allocatedSize(of: entry), lastActivity: activity.date
                ))
                continue      // inutile de descendre dans un artefact
            }
            if skippedNames.contains(name) || values.isPackage == true { continue }
            if name.hasPrefix("."), !allowedHidden.contains(name), DevArtifact.Kind(rawValue: name) == nil { continue }
            walk(entry, depth: depth + 1, into: &results, isCancelled: isCancelled)
        }
    }

    /// `nil` si aucun fichier manifeste n'accompagne le dossier. Sinon, la date de dernière activité du projet.
    private struct Activity { var date: Date? }

    private static func activity(of project: URL, kind: DevArtifact.Kind) -> Activity? {
        let fm = FileManager.default
        var latest: Date?
        var hasManifest = false
        for manifest in kind.manifests {
            let url = project.appendingPathComponent(manifest)
            guard fm.fileExists(atPath: url.path) else { continue }
            hasManifest = true
            if let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                latest = max(latest ?? .distantPast, d)
            }
        }
        guard hasManifest else { return nil }
        // Un `git commit`, `checkout`… met à jour l'index : c'est le meilleur signe d'activité.
        let gitIndex = project.appendingPathComponent(".git/index")
        if let d = (try? gitIndex.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
            latest = max(latest ?? .distantPast, d)
        }
        return Activity(date: latest)
    }

    /// Vrai si `url` est un dossier de dépendances/build d'un projet (nom connu + fichier de projet voisin).
    /// Sert aussi au scan des gros fichiers, qui n'a aucune raison de parcourir ces dossiers.
    static func isArtifact(_ url: URL) -> Bool {
        guard let kind = DevArtifact.Kind(rawValue: url.lastPathComponent) else { return false }
        return activity(of: url.deletingLastPathComponent(), kind: kind) != nil
    }

    /// Supprime l'artefact (régénérable). Plusieurs garde-fous : nom exact, dans le dossier personnel, manifeste présent.
    static func remove(_ artifact: DevArtifact) -> Bool {
        let project = artifact.url.deletingLastPathComponent()
        guard artifact.url.lastPathComponent == artifact.kind.rawValue,
              CleanupService.isSafeToDelete(artifact.url),
              activity(of: project, kind: artifact.kind) != nil
        else { return false }
        return (try? FileManager.default.removeItem(at: artifact.url)) != nil
    }
}
