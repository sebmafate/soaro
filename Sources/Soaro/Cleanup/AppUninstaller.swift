import AppKit
import CoreServices
import Foundation

struct InstalledApp: Identifiable, Equatable {
    let url: URL
    let name: String
    let bundleID: String?
    let version: String?
    var size: UInt64?
    var lastUsed: Date?
    var id: String { url.path }
}

struct Leftover: Identifiable, Equatable {
    let url: URL
    var size: UInt64
    var id: String { url.path }
    var displayPath: String { (url.path as NSString).abbreviatingWithTildeInPath }
}

/// Désinstalle une application avec ses restes dans `~/Library`. Tout part à la corbeille (récupérable).
enum AppUninstaller {
    static var applicationDirectories: [URL] {
        [URL(fileURLWithPath: "/Applications"),
         URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")]
    }

    static func installedApps(in directories: [URL] = applicationDirectories) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        for dir in directories {
            let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in entries where url.pathExtension == "app" {
                let bundle = Bundle(url: url)
                let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                apps.append(InstalledApp(
                    url: url, name: name, bundleID: bundle?.bundleIdentifier,
                    version: bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                    size: nil, lastUsed: lastUsedDate(of: url)
                ))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Date de dernière ouverture, d'après Spotlight (`kMDItemLastUsedDate`).
    static func lastUsedDate(of url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// Les apps Apple et la nôtre ne sont jamais proposées.
    static func canUninstall(_ app: InstalledApp) -> Bool {
        if let id = app.bundleID {
            if id.hasPrefix("com.apple.") { return false }
            if id == Bundle.main.bundleIdentifier { return false }
        }
        return !app.url.path.hasPrefix("/System/")
    }

    static func isRunning(_ app: InstalledApp) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.path == app.url.path }
    }

    // MARK: Restes

    /// Sous-dossiers de `~/Library` où chercher, et si un nom d'app exact y est aussi accepté.
    private static let searchLocations: [(path: String, allowNameMatch: Bool)] = [
        ("Application Support", true), ("Caches", true), ("Logs", true),
        ("Preferences", false), ("Preferences/ByHost", false), ("Containers", false),
        ("Group Containers", false), ("Saved Application State", false), ("HTTPStorages", false),
        ("WebKit", false), ("Cookies", false), ("LaunchAgents", false), ("Application Scripts", false),
    ]

    /// Correspondance volontairement stricte : jamais de recherche approximative (« Notes » ne doit pas
    /// attraper tout ce qui contient « notes »).
    static func matches(entry: String, bundleID: String?, appName: String, allowNameMatch: Bool, group: Bool) -> Bool {
        if let id = bundleID, id.filter({ $0 == "." }).count >= 2 {
            if entry == id || entry.hasPrefix(id + ".") { return true }          // id, id.plist, id.savedState…
            if group, entry.hasSuffix("." + id) { return true }                  // TEAMID.id, group.id
        }
        return allowNameMatch && appName.count >= 4 && entry.caseInsensitiveCompare(appName) == .orderedSame
    }

    static func leftovers(
        for app: InstalledApp,
        library: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
    ) -> [Leftover] {
        var found: [Leftover] = []
        for location in searchLocations {
            let dir = library.appendingPathComponent(location.path)
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for entry in entries where matches(
                entry: entry, bundleID: app.bundleID, appName: app.name,
                allowNameMatch: location.allowNameMatch, group: location.path == "Group Containers"
            ) {
                let url = dir.appendingPathComponent(entry)
                found.append(Leftover(url: url, size: CleanupService.allocatedSize(of: url)))
            }
        }
        return found
    }

    // MARK: Désinstallation

    struct Result: Equatable {
        var freed: UInt64 = 0
        var failures: [String] = []
    }

    static func uninstall(_ app: InstalledApp, leftovers: [Leftover]) -> Result {
        var result = Result()
        guard canUninstall(app), !isRunning(app) else {
            result.failures.append(app.name)
            return result
        }

        // Les restes d'abord : si l'app elle-même échoue (droits), on ne l'a pas privée de ses réglages pour rien… et inversement.
        for item in leftovers where CleanupService.isSafeToDelete(item.url) {
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                result.freed += item.size
            } catch {
                result.failures.append(item.displayPath)
            }
        }
        do {
            try FileManager.default.trashItem(at: app.url, resultingItemURL: nil)
            result.freed += app.size ?? CleanupService.allocatedSize(of: app.url)
        } catch {
            result.failures.append(app.name)
        }
        return result
    }
}
