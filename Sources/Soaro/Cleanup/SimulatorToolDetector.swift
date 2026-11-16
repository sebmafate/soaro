import Foundation

/// Ce que l'on sait, sans rien lancer, de l'outil des simulateurs Apple sur ce Mac.
struct SimulatorToolDetection: Equatable {
    /// `<home>/Library/Developer/CoreSimulator/Devices` existe et c'est un dossier.
    let devicesFolderExists: Bool
    /// Premier `simctl` exécutable trouvé sur le disque, `nil` s'il n'y en a pas.
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

    /// Premier candidat qui est un fichier ordinaire exécutable, dans cet ordre :
    /// 1. le `simctl` de l'Xcode choisi (destination du lien `xcode_select_link`, relative à `/var/db` si elle l'est) ;
    /// 2. `/Applications/Xcode.app` ;
    /// 3. chaque `/Applications/Xcode*.app`, trié par nom.
    static func simctlPath(_ fileSystem: ToolFileSystem) -> String? {
        var candidates: [String] = []
        if let destination = fileSystem.symlinkDestination(of: selectLink) {
            let resolved = destination.hasPrefix("/")
                ? destination
                : URL(fileURLWithPath: destination, relativeTo: URL(fileURLWithPath: "/var/db", isDirectory: true)).standardized.path
            candidates.append(resolved + simctlSuffix)
        }
        candidates.append("/Applications/Xcode.app/Contents/Developer" + simctlSuffix)
        let others = fileSystem.entries(inDirectory: "/Applications")
            .filter { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }
            .sorted()
        for entry in others {
            candidates.append("/Applications/\(entry)/Contents/Developer" + simctlSuffix)
        }
        return candidates.first { fileSystem.isExecutableRegularFile($0) }
    }
}
