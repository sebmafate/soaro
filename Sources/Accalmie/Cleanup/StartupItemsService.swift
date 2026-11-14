import Foundation

/// Agent de lancement (LaunchAgent) lancé à l'ouverture de session.
struct LaunchAgentItem: Identifiable, Equatable {
    let label: String
    let plist: URL
    let program: String?
    let runAtLoad: Bool
    let isUserOwned: Bool          // dans ~/Library/LaunchAgents (installé par l'utilisateur ou une app)
    var isDisabled: Bool
    /// Le même label peut exister dans deux dossiers : l'identité, c'est le fichier.
    var id: String { plist.path }

    var displayName: String {
        // « com.google.keystone.agent » → « keystone.agent » : plus lisible que le label complet.
        let parts = label.split(separator: ".")
        return parts.count > 2 ? parts.dropFirst(2).joined(separator: ".") : label
    }
}

/// « Élément d'ouverture » listé dans Réglages Système > Éléments de connexion.
struct LoginItem: Identifiable, Equatable {
    let name: String
    let path: String
    var id: String { name + path }
}

enum StartupItemsService {
    static var userID: uid_t { getuid() }

    static var defaultDirectories: [URL] {
        [URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/LaunchAgents"),
         URL(fileURLWithPath: "/Library/LaunchAgents")]
    }

    // MARK: Agents de lancement

    /// Liste les agents hors Apple. Lecture seule des plist.
    static func launchAgents(in directories: [URL] = defaultDirectories, disabled: Set<String>) -> [LaunchAgentItem] {
        let userDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/LaunchAgents").path
        var items: [LaunchAgentItem] = []
        for dir in directories {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: file),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let label = plist["Label"] as? String, !label.hasPrefix("com.apple.")
                else { continue }
                let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
                items.append(LaunchAgentItem(
                    label: label, plist: file, program: program,
                    runAtLoad: plist["RunAtLoad"] as? Bool ?? false,
                    isUserOwned: dir.path == userDir,
                    isDisabled: disabled.contains(label)
                ))
            }
        }
        return items.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Labels désactivés par l'utilisateur (`launchctl print-disabled`).
    static func disabledLabels() -> Set<String> {
        guard let output = run("/bin/launchctl", ["print-disabled", "gui/\(userID)"]) else { return [] }
        return parseDisabled(output)
    }

    static func parseDisabled(_ output: String) -> Set<String> {
        var labels: Set<String> = []
        for line in output.split(separator: "\n") where line.contains("=> disabled") || line.contains("=> true") {
            let parts = line.split(separator: "\"")
            if parts.count >= 2 { labels.insert(String(parts[1])) }
        }
        return labels
    }

    /// Active / désactive un agent pour l'utilisateur courant, sans droits administrateur et sans toucher au fichier.
    @discardableResult
    static func setEnabled(_ item: LaunchAgentItem, enabled: Bool) -> Bool {
        guard !item.label.hasPrefix("com.apple.") else { return false }
        let target = "gui/\(userID)/\(item.label)"
        if enabled {
            return run("/bin/launchctl", ["enable", target]) != nil
        }
        let ok = run("/bin/launchctl", ["disable", target]) != nil
        _ = run("/bin/launchctl", ["bootout", target])       // l'arrête maintenant (peut échouer s'il ne tourne pas)
        return ok
    }

    // MARK: Éléments d'ouverture (System Events)

    /// `nil` si l'accès à System Events est refusé (autorisation d'automatisation).
    static func loginItems() -> [LoginItem]? {
        let script = """
        tell application "System Events"
            set out to ""
            repeat with li in login items
                set out to out & (name of li) & "|" & (path of li) & linefeed
            end repeat
            return out
        end tell
        """
        guard let output = run("/usr/bin/osascript", ["-e", script]) else { return nil }
        return parseLoginItems(output)
    }

    static func parseLoginItems(_ output: String) -> [LoginItem] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty else { return nil }
            return LoginItem(name: String(parts[0]), path: String(parts[1]))
        }
    }

    @discardableResult
    static func removeLoginItem(_ item: LoginItem) -> Bool {
        let escaped = item.name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"System Events\" to delete (first login item whose name is \"\(escaped)\")"
        return run("/usr/bin/osascript", ["-e", script]) != nil
    }

    // MARK: Outil

    /// Sortie standard si le code de retour est 0, sinon `nil`.
    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let out = Pipe()
        task.standardOutput = out
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return task.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
