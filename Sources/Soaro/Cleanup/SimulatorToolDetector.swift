import Foundation

/// Ce que l'on sait, sans rien lancer, de l'outil des simulateurs Apple sur ce Mac.
struct SimulatorToolDetection: Equatable {
    /// `<home>/Library/Developer/CoreSimulator/Devices` existe et c'est un dossier.
    let devicesFolderExists: Bool
    /// Le `simctl` du dossier de développeur actif (celui que `xcrun` lancera), `nil` s'il est absent.
    let simctlPath: String?

    /// L'outil est « présent » dès qu'un dossier d'appareils ou un `simctl` existe.
    var isToolPresent: Bool { devicesFolderExists || simctlPath != nil }

    /// La rangée « Simulators and emulators » de la liste des outils : visible si l'outil est présent, ou en mode démo.
    /// `nil` : la détection n'a pas encore eu lieu (la rangée reste cachée).
    static func showsToolsRow(detection: SimulatorToolDetection?, demo: Bool) -> Bool {
        demo || (detection?.isToolPresent ?? false)
    }
}

/// Les quatre questions que la détection pose au disque (un faux est injecté dans les tests).
protocol ToolFileSystem {
    func isDirectory(_ path: String) -> Bool
    /// Fichier ordinaire (pas un dossier) exécutable, liens suivis.
    func isExecutableRegularFile(_ path: String) -> Bool
    /// Destination d'un lien symbolique, `nil` si le chemin n'existe pas ou n'est pas un lien.
    func symlinkDestination(of path: String) -> String?
    /// Noms des entrées d'un dossier (vide si illisible).
    func entries(inDirectory path: String) -> [String]
}

/// Le vrai disque, par `FileManager` : lecture seule.
struct DiskToolFileSystem: ToolFileSystem {
    func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    func isExecutableRegularFile(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            && !isDir.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    func symlinkDestination(of path: String) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: path)
    }

    func entries(inDirectory path: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    }
}

/// Détection PURE et injectable de l'outil des simulateurs : on regarde le disque, on ne lance RIEN
/// (ni `xcrun`, ni `xcode-select`), on ne lit ni la variable d'environnement du développeur ni le PATH.
enum SimulatorToolDetector {
    /// Lien écrit par `xcode-select -s` : il désigne le dossier `Developer` choisi.
    static let selectLink = "/var/db/xcode_select_link"
    static let simctlSuffix = "/usr/bin/simctl"

    static func detect(home: URL, fileSystem: ToolFileSystem = DiskToolFileSystem()) -> SimulatorToolDetection {
        let devices = home.appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true).path
        return SimulatorToolDetection(devicesFolderExists: fileSystem.isDirectory(devices),
                                      simctlPath: simctlPath(fileSystem))
    }

    /// Chemin absolu normalisé d'une destination de lien, par manipulation de CHAÎNES seulement (ni URL, ni FileManager, ni
    /// NSString : le résultat ne dépend ni de la version de macOS ni du disque). Une destination relative part de `base`.
    /// Les composants vides et `.` sont ignorés ; `..` retire le composant précédent, sans jamais passer au-dessus de la racine.
    static func resolvedPath(destination: String, base: String) -> String {
        var parts: [Substring] = []
        let start = destination.hasPrefix("/") ? "" : base
        for component in (start + "/" + destination).split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(component)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    /// Le `simctl` que `/usr/bin/xcrun` lancera VRAIMENT : celui du dossier de développeur actif (`xcrun` suit le dossier actif).
    /// - Lien `xcode_select_link` présent : SEULE source, `<destination>/usr/bin/simctl` (destination relative résolue contre
    ///   `/var/db`). Pas de repli : avec les Command Line Tools actifs et Xcode installé, `xcrun simctl` échouerait.
    /// - Lien absent : le repli de `xcode-select` lui-même, `/Applications/Xcode.app`, puis chaque `/Applications/Xcode*.app`
    ///   trié par nom.
    /// Le candidat doit être un fichier ordinaire exécutable. Rien n'est lancé.
    static func simctlPath(_ fileSystem: ToolFileSystem) -> String? {
        if let destination = fileSystem.symlinkDestination(of: selectLink) {
            let resolved = resolvedPath(destination: destination, base: "/var/db")
            let candidate = (resolved == "/" ? "" : resolved) + simctlSuffix
            return fileSystem.isExecutableRegularFile(candidate) ? candidate : nil
        }
        var candidates = ["/Applications/Xcode.app/Contents/Developer" + simctlSuffix]
        let others = fileSystem.entries(inDirectory: "/Applications")
            .filter { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }
            .sorted()
        for entry in others {
            candidates.append("/Applications/\(entry)/Contents/Developer" + simctlSuffix)
        }
        return candidates.first { fileSystem.isExecutableRegularFile($0) }
    }
}
