import Foundation

// MARK: - Modèle

/// Un conseil de réglage. Contrairement à une recommandation (alerte), il n'y a rien d'urgent :
/// pas de notification, pas de badge, et l'utilisateur peut l'ignorer définitivement.
struct Advice: Identifiable, Equatable {
    enum Action: Equatable {
        /// Ouvre un panneau de Réglages Système. L'app ne modifie jamais un réglage elle-même.
        case openSettings(String)
        case showStartupItems
        case openActivityMonitor
    }

    let id: String
    var systemImage: String
    var title: String
    var detail: String
    var action: Action?
    var actionLabel: String?
}

enum SettingsPane {
    static let battery = "x-apple.systempreferences:com.apple.Battery-Settings.extension"
    static let softwareUpdate = "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
    static let storage = "x-apple.systempreferences:com.apple.settings.Storage"
    static let timeMachine = "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension"
}

struct SleepBlocker: Equatable {
    var name: String
    var seconds: Int
}

/// État des réglages du système, lu sans rien modifier (voir `AdviceProbe`).
struct SystemFacts: Equatable {
    var chargeLimit: Int? = nil                 // % auquel macOS plafonne la charge
    var lowPowerMode = false
    var sleepBlockers: [SleepBlocker] = []
    var enabledAgentCount = 0
    var autoEmptyTrash = true
    var pendingUpdateVersion: String? = nil
    var timeMachineConfigured = true
    var lastBackup: Date? = nil
}

struct AdviceInput {
    var facts: SystemFacts
    var battery: BatteryStats?
    var disk: DiskStats?
    var processes: [ProcessGroup] = []
    var osVersion: String = ""
    var now = Date()
}

// MARK: - Moteur (fonction pure)

enum AdviceEngine {
    static let sleepBlockerThreshold = 2 * 3_600
    static let agentThreshold = 12
    static let spotlightCPUThreshold = 50.0
    static let backupMaxAge: TimeInterval = 14 * 86_400
    static let spotlightProcesses: Set<String> = ["mds", "mds_stores", "mdworker", "mdworker_shared", "mdsync", "corespotlightd", "spotlightknowledged"]

    static func evaluate(_ input: AdviceInput) -> [Advice] {
        var result: [Advice] = []
        let facts = input.facts

        // 1. Limite de charge : explique pourquoi une batterie branchée ne monte pas à 100 %.
        if let b = input.battery, let limit = facts.chargeLimit, limit < 100, b.isPluggedIn, !b.isCharging, b.percent <= Double(limit) + 1 {
            result.append(Advice(
                id: "battery.chargeLimit", systemImage: "battery.75percent",
                title: String(localized: "Charge limited to \(limit) % by macOS"),
                detail: String(localized: "This is not a fault: optimized charging caps the charge (and lets the battery drop to that level) to slow its wear while the Mac stays plugged in. To go back to 100 %, for example before a trip, change it in Battery settings."),
                action: .openSettings(SettingsPane.battery), actionLabel: String(localized: "Battery Settings")
            ))
        }

        // 2. Mode économie d'énergie
        if let b = input.battery, !b.isPluggedIn, b.percent <= 30, !facts.lowPowerMode {
            result.append(Advice(
                id: "battery.lowPowerMode", systemImage: "leaf",
                title: String(localized: "Turn on Low Power Mode"),
                detail: String(localized: "\(Int(b.percent)) % battery left. This mode lowers brightness and background activity to extend battery life."),
                action: .openSettings(SettingsPane.battery), actionLabel: String(localized: "Battery Settings")
            ))
        }

        // 3. Veille empêchée depuis longtemps par une app
        let blockers = facts.sleepBlockers.filter { $0.seconds >= sleepBlockerThreshold }.sorted { $0.seconds > $1.seconds }
        if let first = blockers.first {
            let names = Array(Set(blockers.map(\.name))).sorted().prefix(3).joined(separator: ", ")
            result.append(Advice(
                id: "sleep.blocked", systemImage: "moon.zzz",
                title: blockers.count == 1 ? String(localized: "\(first.name) is preventing sleep") : String(localized: "Some apps are preventing sleep"),
                detail: String(localized: "\(names): sleep blocked for \(Format.minutes(first.seconds / 60)). The Mac does not fall asleep by itself, which uses energy and drains the battery when unplugged. Close the app if this is not intended."),
                action: .openActivityMonitor, actionLabel: String(localized: "Activity Monitor")
            ))
        }

        // 4. Trop de programmes au démarrage
        if facts.enabledAgentCount >= agentThreshold {
            result.append(Advice(
                id: "startup.agents", systemImage: "power.circle",
                title: String(localized: "Programs launching at login: \(facts.enabledAgentCount)"),
                detail: String(localized: "Each one slows down startup and keeps using memory. Many are automatic updaters for apps you may no longer use."),
                action: .showStartupItems, actionLabel: String(localized: "Show the list")
            ))
        }

        // 5. Indexation Spotlight : informer que c'est temporaire
        let spotlightCPU = input.processes.filter { spotlightProcesses.contains($0.name) }.reduce(0) { $0 + $1.cpu }
        if spotlightCPU >= spotlightCPUThreshold {
            result.append(Advice(
                id: "spotlight.indexing", systemImage: "magnifyingglass",
                title: String(localized: "Spotlight is indexing your files"),
                detail: String(localized: "Indexing uses about \(Int(spotlightCPU)) % of the processor. This is normal after an update or when many files are added, and it stops by itself: no action needed."),
                action: nil, actionLabel: nil
            ))
        }

        // 6. Stockage
        if let disk = input.disk, disk.total > 0, disk.availableFraction < 0.20 {
            if !facts.autoEmptyTrash {
                result.append(Advice(
                    id: "storage.autoTrash", systemImage: "trash",
                    title: String(localized: "Empty the Trash automatically"),
                    detail: String(localized: "\(Format.percent(disk.availableFraction)) of free space left. macOS can delete items that stayed in the Trash for more than 30 days (Finder › Settings › Advanced)."),
                    action: .openSettings(SettingsPane.storage), actionLabel: String(localized: "Storage Settings")
                ))
            } else {
                result.append(Advice(
                    id: "storage.optimize", systemImage: "internaldrive",
                    title: String(localized: "Optimize storage"),
                    detail: String(localized: "\(Format.percent(disk.availableFraction)) of free space left. Storage settings offer to move files to iCloud and remove movies you have already watched."),
                    action: .openSettings(SettingsPane.storage), actionLabel: String(localized: "Storage Settings")
                ))
            }
        }

        // 7. Mise à jour de macOS en attente
        if let pending = facts.pendingUpdateVersion, isVersion(pending, newerThan: input.osVersion) {
            result.append(Advice(
                id: "update.pending.\(pending)", systemImage: "arrow.down.circle",
                title: String(localized: "macOS \(pending) is available"),
                detail: String(localized: "Updates fix security flaws and performance problems. You are running macOS \(input.osVersion)."),
                action: .openSettings(SettingsPane.softwareUpdate), actionLabel: String(localized: "Software Update")
            ))
        }

        // 8. Sauvegarde Time Machine
        if !facts.timeMachineConfigured {
            result.append(Advice(
                id: "backup.none", systemImage: "externaldrive.badge.timemachine",
                title: String(localized: "No Time Machine backup"),
                detail: String(localized: "Without a backup, a disk failure or an accidental deletion is permanent. An external drive is enough; especially worth doing before a big cleanup."),
                action: .openSettings(SettingsPane.timeMachine), actionLabel: String(localized: "Time Machine Settings")
            ))
        } else if let last = facts.lastBackup, input.now.timeIntervalSince(last) > backupMaxAge {
            let days = Int(input.now.timeIntervalSince(last) / 86_400)
            result.append(Advice(
                id: "backup.old", systemImage: "externaldrive.badge.timemachine",
                title: String(localized: "Last backup \(days) days ago"),
                detail: String(localized: "Connect your Time Machine drive to update the backup."),
                action: .openSettings(SettingsPane.timeMachine), actionLabel: String(localized: "Time Machine Settings")
            ))
        }

        return result
    }

    /// Comparaison numérique de versions (« 27.2 » > « 27.0.1 »).
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0) ?? 0 } }
        let a = parts(candidate), b = parts(current)
        guard !a.isEmpty, !b.isEmpty else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

// MARK: - Analyse des sorties système (fonctions pures)

enum AdviceParsing {
    /// `pmset -g battlimit` → plus petite limite de charge active, ou `nil`.
    static func chargeLimit(_ output: String) -> Int? {
        var limits: [Int] = []
        for line in output.split(separator: "\n") where line.contains("chargeSocLimitSoc") {
            let digits = line.split(separator: "=").last?.filter(\.isNumber) ?? ""
            if let value = Int(digits), (1...100).contains(value) { limits.append(value) }
        }
        return limits.min()
    }

    /// Processus système qui empêchent la veille pour de bonnes raisons : jamais signalés.
    static let ignoredSleepOwners: Set<String> = [
        "powerd", "bluetoothd", "WindowServer", "coreaudiod", "sharingd", "backupd", "softwareupdated", "mds", "mds_stores",
        "apsd", "cloudd", "nsurlsessiond", "kernel_task", "runningboardd", "UserEventAgent", "useractivityd", "mediaremoted",
    ]
    static let sleepAssertions = ["PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion"]

    /// `pmset -g assertions` → apps qui empêchent la veille du système, avec la durée.
    /// Ex. : `   pid 1234(Amphetamine): [0x0005] 03:53:31 PreventUserIdleSystemSleep named: "…"`
    static func sleepBlockers(_ output: String) -> [SleepBlocker] {
        var blockers: [SleepBlocker] = []
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("pid "), sleepAssertions.contains(where: { line.contains(" \($0) ") }),
                  let open = line.firstIndex(of: "("), let close = line.range(of: "):")?.lowerBound, open < close
            else { continue }
            let name = String(line[line.index(after: open)..<close])
            guard !ignoredSleepOwners.contains(name) else { continue }

            // La durée suit le crochet fermant : « ] HH:MM:SS »
            guard let bracket = line.range(of: "] ")?.upperBound else { continue }
            let duration = line[bracket...].prefix { $0.isNumber || $0 == ":" }.split(separator: ":").compactMap { Int($0) }
            guard duration.count == 3 else { continue }
            blockers.append(SleepBlocker(name: name, seconds: duration[0] * 3_600 + duration[1] * 60 + duration[2]))
        }
        return blockers
    }

    /// Préférences `com.apple.SoftwareUpdate` → version de macOS en attente (la plus haute), ou `nil`.
    static func pendingUpdateVersion(_ prefs: [String: Any]) -> String? {
        var versions: [String] = []
        for update in prefs["RecommendedUpdates"] as? [[String: Any]] ?? [] {
            let name = (update["Display Name"] as? String ?? "").lowercased()
            if name.contains("macos"), let version = update["Display Version"] as? String { versions.append(version) }
        }
        // Clés du type « MSU_UPDATE_26B123_patch_27.2_minor »
        for key in prefs["AutoInstallProductKeys"] as? [String] ?? [] {
            let parts = key.split(separator: "_")
            if let index = parts.firstIndex(where: { $0 == "patch" || $0 == "full" }), index + 1 < parts.count {
                let version = String(parts[index + 1])
                if version.first?.isNumber == true { versions.append(version) }
            }
        }
        return versions.max { AdviceEngine.isVersion($1, newerThan: $0) }
    }

    /// `tmutil destinationinfo` → une destination est-elle configurée ?
    static func timeMachineConfigured(_ output: String) -> Bool {
        !output.contains("No destinations configured") && output.contains("ID")
    }

    /// Préférences `com.apple.TimeMachine` → date de la sauvegarde la plus récente.
    static func lastBackup(_ prefs: [String: Any]) -> Date? {
        (prefs["Destinations"] as? [[String: Any]] ?? [])
            .flatMap { $0["SnapshotDates"] as? [Date] ?? [] }
            .max()
    }
}

// MARK: - Collecte (lecture seule)

enum AdviceProbe {
    /// Lit l'état des réglages. Lance quelques commandes : à appeler hors du thread principal, de temps en temps.
    static func collect() -> SystemFacts {
        var facts = SystemFacts()
        facts.chargeLimit = run("/usr/bin/pmset", ["-g", "battlimit"]).flatMap(AdviceParsing.chargeLimit)
        facts.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        facts.sleepBlockers = run("/usr/bin/pmset", ["-g", "assertions"]).map(AdviceParsing.sleepBlockers) ?? []
        facts.enabledAgentCount = StartupItemsService.launchAgents(disabled: StartupItemsService.disabledLabels())
            .filter { !$0.isDisabled && $0.runAtLoad }.count
        facts.autoEmptyTrash = UserDefaults(suiteName: "com.apple.finder")?.bool(forKey: "FXRemoveOldTrashItems") ?? true

        if let prefs = NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.SoftwareUpdate.plist") as? [String: Any] {
            facts.pendingUpdateVersion = AdviceParsing.pendingUpdateVersion(prefs)
        }
        if let output = run("/usr/bin/tmutil", ["destinationinfo"], acceptFailure: true) {
            facts.timeMachineConfigured = AdviceParsing.timeMachineConfigured(output)
        }
        if let prefs = NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.TimeMachine.plist") as? [String: Any] {
            facts.lastBackup = AdviceParsing.lastBackup(prefs)
        }
        return facts
    }

    private static func run(_ path: String, _ arguments: [String], acceptFailure: Bool = false) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let out = Pipe()
        task.standardOutput = out
        task.standardError = out
        do { try task.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard acceptFailure || task.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
