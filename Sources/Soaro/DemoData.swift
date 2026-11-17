import Foundation

/// Demo mode: `SOARO_DEMO=1` runs the app on a made-up Mac, so screenshots contain no personal data
/// (no computer name, serial number, IP address, Wi-Fi name, or process of the real machine).
///
/// Nothing is measured and nothing is read from the real Mac: history, preferences and the
/// Application Support folder are not touched either. The recommendations and tips still come from the
/// real engines, fed with these values.
enum DemoMode {
    static let isEnabled = ProcessInfo.processInfo.environment["SOARO_DEMO"] != nil

    /// macOS version shown in demo mode, and the update it offers.
    static let osVersion = "26.1"
    static let pendingUpdate = "26.2"
}

enum DemoData {
    private static let gb: UInt64 = 1_000_000_000
    private static let mb: UInt64 = 1_000_000

    // MARK: Machine

    static let machine = MachineInfo(
        modelName: "MacBook Pro",
        modelIdentifier: "Mac15,7",
        chip: "Apple M3 Pro",
        serialNumber: "C02DEMO0001",
        totalCores: 12,
        performanceCores: 6,
        efficiencyCores: 6,
        gpuCores: 18,
        memory: 18 * 1_073_741_824,
        osVersion: "macOS \(DemoMode.osVersion)",
        displays: [MachineInfo.Display(name: "Built-in Retina Display", pixels: "3024 × 1964", refreshRate: 120)],
        computerName: "MacBook Pro",
        localHostName: "macbook-pro"
    )

    static let localNetworkName = "macbook-pro.local"

    // MARK: Measurements

    static func snapshot(now: Date = Date()) -> SystemSnapshot {
        let cores: [Double] = [0.62, 0.55, 0.48, 0.41, 0.38, 0.30, 0.12, 0.09, 0.08, 0.06, 0.05, 0.04]
        let total: UInt64 = 18 * 1_073_741_824
        return SystemSnapshot(
            date: now,
            cpu: CPUStats(user: 0.27, system: 0.09, perCore: cores, efficiencyCores: 6),
            memory: MemoryStats(total: total, app: 8_400 * mb, wired: 2_300 * mb, compressed: 900 * mb, cached: 4_100 * mb,
                                swapUsed: 0, pressure: .normal),
            disk: DiskStats(total: 994 * gb, available: 169 * gb),
            thermalState: .nominal,
            uptime: 3 * 86_400 + 5 * 3_600,
            gpu: GPUStats(utilization: 0.22, memoryUsed: 1_100 * mb),
            battery: BatteryStats(percent: 67, isCharging: true, isPluggedIn: true, isFullyCharged: false, minutesRemaining: 48,
                                  cycleCount: 187, health: 0.94, designCapacity: 6_075, maxCapacity: 5_710, temperature: 31.4,
                                  batteryPower: 38.2, systemPower: 14.6, adapterWatts: 70),
            network: NetworkStats(downRate: 2_400_000, upRate: 310_000, localIP: "192.168.1.24",
                                  wifi: WiFiInfo(rssi: -52, noise: -92, txRate: 866, ssid: "Home", channel: 36), latencyMs: 12),
            diskIO: DiskIOStats(readRate: 4_800_000, writeRate: 1_900_000),
            sensors: SensorStats(
                cpu: 52, gpu: 47, ssd: 38, battery: 31,
                all: [TemperatureSensor(name: "CPU", celsius: 52), TemperatureSensor(name: "GPU", celsius: 47),
                      TemperatureSensor(name: "SSD", celsius: 38), TemperatureSensor(name: "Battery", celsius: 31)],
                fans: [FanInfo(index: 0, rpm: 1_620, minRPM: 1_200, maxRPM: 5_800)],
                systemPower: 14.6
            )
        )
    }

    /// A smooth curve ending on `last`, for the small charts.
    static func curve(last: Double, spread: Double, count: Int = 60, phase: Double = 0) -> [Double] {
        (0..<count).map { i in
            let t = Double(i) / Double(count)
            let value = last + spread * (sin(t * 9 + phase) * 0.6 + sin(t * 23 + phase * 2) * 0.4)
            return max(0, value)
        }
    }

    // MARK: Apps

    static let processes: [ProcessGroup] = [
        ProcessGroup(id: "xcode", name: "Xcode", cpu: 86, memory: 3_200 * mb, pids: [1001], appPath: "/Applications/Xcode.app", canQuit: true,
                     ioReadRate: 2_100_000, ioWriteRate: 900_000),
        ProcessGroup(id: "render", name: "Studio Render", cpu: 41, memory: 2_900 * mb, pids: [1002], appPath: "/Applications/Studio Render.app", canQuit: true,
                     ioReadRate: 600_000, ioWriteRate: 300_000),
        ProcessGroup(id: "safari", name: "Safari", cpu: 24, memory: 1_450 * mb, pids: [1003], appPath: "/Applications/Safari.app", canQuit: true,
                     ioReadRate: 120_000, ioWriteRate: 60_000),
        ProcessGroup(id: "windowserver", name: "WindowServer", cpu: 12, memory: 420 * mb, pids: [1004], appPath: nil),
        ProcessGroup(id: "music", name: "Music", cpu: 6, memory: 520 * mb, pids: [1005], appPath: "/System/Applications/Music.app", canQuit: true),
        ProcessGroup(id: "mail", name: "Mail", cpu: 4, memory: 610 * mb, pids: [1006], appPath: "/System/Applications/Mail.app", canQuit: true),
        ProcessGroup(id: "notes", name: "Notes", cpu: 2, memory: 280 * mb, pids: [1007], appPath: "/System/Applications/Notes.app", canQuit: true),
        ProcessGroup(id: "finder", name: "Finder", cpu: 1, memory: 240 * mb, pids: [1008], appPath: nil),
    ]

    static let networkProcesses: [NetworkProcess] = [
        NetworkProcess(name: "Safari", appPath: "/Applications/Safari.app", down: 1_700_000, up: 90_000),
        NetworkProcess(name: "Music", appPath: "/System/Applications/Music.app", down: 420_000, up: 4_000),
        NetworkProcess(name: "Mail", appPath: "/System/Applications/Mail.app", down: 160_000, up: 120_000),
        NetworkProcess(name: "Xcode", appPath: "/Applications/Xcode.app", down: 90_000, up: 60_000),
    ]

    static let energyEntries: [EnergyEntry] = [
        EnergyEntry(name: "Xcode", appPath: "/Applications/Xcode.app", impact: 38),
        EnergyEntry(name: "Studio Render", appPath: "/Applications/Studio Render.app", impact: 24),
        EnergyEntry(name: "Safari", appPath: "/Applications/Safari.app", impact: 11),
        EnergyEntry(name: "Music", appPath: "/System/Applications/Music.app", impact: 5),
    ]

    /// The made-up app that keeps growing: the leak detector's example.
    static let leaks: [LeakSuspect] = [
        LeakSuspect(id: "render", name: "Studio Render", appPath: "/Applications/Studio Render.app", canQuit: true,
                    growth: 1_400 * mb, minutes: 42, currentMemory: 2_900 * mb),
    ]

    static let cleanupSizes: [CleanupKind: UInt64?] = [
        .caches: 4_200 * mb, .logs: 310 * mb, .trash: 1_100 * mb,
        .derivedData: 8_700 * mb, .npmCache: 1_300 * mb, .gradleCache: 2_600 * mb,
        .cargoCache: 900 * mb, .nugetCache: 13_100 * mb, .xcodeDeviceSupport: 5_400 * mb, .simulatorCaches: 1_800 * mb,
    ]

    static let traffic = DailyTraffic(down: 3_800 * mb, up: 412 * mb)

    static let vpn = VPNStatus(mode: .full, name: "WireGuard", interface: "utun4")

    static func publicIP(now: Date = Date()) -> PublicIPInfo {
        // 203.0.113.0/24 is reserved for documentation (RFC 5737): it never belongs to a real person.
        PublicIPInfo(ip: "203.0.113.42", countryCode: "FR", country: "France", city: "Paris", provider: "Example ISP", fetchedAt: now)
    }

    /// The state of the settings Soaro reads, chosen to show a few tips.
    static func facts(now: Date = Date()) -> SystemFacts {
        var facts = SystemFacts()
        facts.chargeLimit = nil
        facts.lowPowerMode = false
        facts.sleepBlockers = [SleepBlocker(name: "Studio Render", seconds: 3 * 3_600)]
        facts.enabledAgentCount = 14
        facts.autoEmptyTrash = false
        facts.pendingUpdateVersion = DemoMode.pendingUpdate
        facts.timeMachineConfigured = true
        facts.lastBackup = now.addingTimeInterval(-3 * 86_400)
        return facts
    }

    // MARK: Cleanup tools

    private static func home(_ path: String) -> URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(path) }
    private static func daysAgo(_ days: Double) -> Date { Date().addingTimeInterval(-days * 86_400) }

    static let largeFiles: [LargeFile] = [
        LargeFile(url: home("Movies/Holiday 2024 (4K).mov"), size: 8_400 * mb, modified: daysAgo(210)),
        LargeFile(url: home("Downloads/macOS-installer.dmg"), size: 5_900 * mb, modified: daysAgo(95)),
        LargeFile(url: home("Documents/Archive/backup-2023.zip"), size: 3_100 * mb, modified: daysAgo(420)),
        LargeFile(url: home("Downloads/ubuntu-24.04-desktop-arm64.iso"), size: 2_700 * mb, modified: daysAgo(160)),
        LargeFile(url: home("Movies/Screen Recording 2025-03-02.mov"), size: 1_450 * mb, modified: daysAgo(70)),
        LargeFile(url: home("Music/Sessions/mix-final.wav"), size: 880 * mb, modified: daysAgo(300)),
        LargeFile(url: home("Documents/Scans/passport-scans.pdf"), size: 410 * mb, modified: daysAgo(30)),
        LargeFile(url: home("Downloads/dataset.csv"), size: 260 * mb, modified: daysAgo(12)),
    ]

    static let devArtifacts: [DevArtifact] = [
        DevArtifact(url: home("Projects/web-shop/node_modules"), kind: .nodeModules, size: 1_240 * mb, lastActivity: daysAgo(210)),
        DevArtifact(url: home("Projects/ios-notes/.build"), kind: .swiftBuild, size: 960 * mb, lastActivity: daysAgo(130)),
        DevArtifact(url: home("Projects/game-engine/target"), kind: .rustTarget, size: 2_300 * mb, lastActivity: daysAgo(95)),
        DevArtifact(url: home("Projects/old-app/Pods"), kind: .pods, size: 420 * mb, lastActivity: daysAgo(380)),
        DevArtifact(url: home("Projects/blog/node_modules"), kind: .nodeModules, size: 610 * mb, lastActivity: daysAgo(40)),
        DevArtifact(url: home("Projects/soaro-site/node_modules"), kind: .nodeModules, size: 340 * mb, lastActivity: daysAgo(3)),
    ]

    static let apps: [InstalledApp] = [
        InstalledApp(url: URL(fileURLWithPath: "/Applications/Studio Render.app"), name: "Studio Render", bundleID: "com.example.studiorender",
                     version: "4.2", size: 2_300 * mb, lastUsed: daysAgo(1)),
        InstalledApp(url: URL(fileURLWithPath: "/Applications/Photo Lab.app"), name: "Photo Lab", bundleID: "com.example.photolab",
                     version: "2.9.1", size: 1_150 * mb, lastUsed: daysAgo(240)),
        InstalledApp(url: URL(fileURLWithPath: "/Applications/Pixel Draw.app"), name: "Pixel Draw", bundleID: "com.example.pixeldraw",
                     version: "1.7", size: 640 * mb, lastUsed: daysAgo(400)),
        InstalledApp(url: URL(fileURLWithPath: "/Applications/Quick Notes.app"), name: "Quick Notes", bundleID: "com.example.quicknotes",
                     version: "3.0", size: 180 * mb, lastUsed: daysAgo(9)),
        InstalledApp(url: URL(fileURLWithPath: "/Applications/Sound Mixer.app"), name: "Sound Mixer", bundleID: "com.example.soundmixer",
                     version: "5.1", size: 920 * mb, lastUsed: daysAgo(150)),
    ]

    static func leftovers(for app: InstalledApp) -> [Leftover] {
        let id = app.bundleID ?? "com.example.app"
        return [
            Leftover(url: home("Library/Application Support/\(app.name)"), size: 310 * mb),
            Leftover(url: home("Library/Caches/\(id)"), size: 180 * mb),
            Leftover(url: home("Library/Preferences/\(id).plist"), size: 12_000),
            Leftover(url: home("Library/Logs/\(app.name)"), size: 3 * mb),
        ]
    }

    static let agents: [LaunchAgentItem] = [
        LaunchAgentItem(label: "com.example.studiorender.updater", plist: home("Library/LaunchAgents/com.example.studiorender.updater.plist"),
                        program: "/Applications/Studio Render.app/Contents/MacOS/updater", runAtLoad: true, isUserOwned: true, isDisabled: false),
        LaunchAgentItem(label: "com.example.photolab.helper", plist: home("Library/LaunchAgents/com.example.photolab.helper.plist"),
                        program: "/Applications/Photo Lab.app/Contents/MacOS/helper", runAtLoad: true, isUserOwned: true, isDisabled: false),
        LaunchAgentItem(label: "com.example.soundmixer.agent", plist: home("Library/LaunchAgents/com.example.soundmixer.agent.plist"),
                        program: "/Applications/Sound Mixer.app/Contents/MacOS/agent", runAtLoad: true, isUserOwned: true, isDisabled: true),
        LaunchAgentItem(label: "com.example.cloudsync.agent", plist: URL(fileURLWithPath: "/Library/LaunchAgents/com.example.cloudsync.agent.plist"),
                        program: "/Library/Application Support/CloudSync/agent", runAtLoad: true, isUserOwned: false, isDisabled: false),
    ]

    static let loginItems: [LoginItem] = [
        LoginItem(name: "Studio Render", path: "/Applications/Studio Render.app"),
        LoginItem(name: "Quick Notes", path: "/Applications/Quick Notes.app"),
        LoginItem(name: "Sound Mixer", path: "/Applications/Sound Mixer.app"),
    ]

    // MARK: Simulators

    /// Made-up Xcode simulators for the "Simulators and emulators" tool: generic Apple product names, fake identifiers
    /// (`00000000-0000-4000-8000-0000000000NN`, NN from 41), dates relative to `now`, every size known.
    static func simulators(now: Date = Date()) -> [SizedSimulator] {
        func device(_ n: Int, _ name: String, runtime: String, model: String, days: Double?, state: String = "Shutdown",
                    available: Bool = true, size: UInt64) -> SizedSimulator {
            let runtimeID = "com.apple.CoreSimulator.SimRuntime.\(runtime)"
            return SizedSimulator(
                device: SimulatorDevice(udid: String(format: "00000000-0000-4000-8000-%012d", n), name: name,
                                        modelIdentifier: "com.apple.CoreSimulator.SimDeviceType.\(model)",
                                        runtimeIdentifier: runtimeID, runtimeName: SimulatorScanner.runtimeName(runtimeID),
                                        state: state, isAvailable: available,
                                        lastUsed: days.map { now.addingTimeInterval(-$0 * 86_400) }),
                size: size)
        }
        return [
            // Inactive for 66 days.
            device(41, "iPhone 17 Pro", runtime: "iOS-26-2", model: "iPhone-17-Pro", days: 66, size: 4_100 * mb),
            // An older copy and the one it is a copy of (same name, same model, same system).
            device(42, "iPhone 17", runtime: "iOS-26-2", model: "iPhone-17", days: 4, size: 2_400 * mb),
            device(43, "iPhone 17", runtime: "iOS-26-2", model: "iPhone-17", days: 25, size: 2_100 * mb),
            // Used today.
            device(44, "iPad Air 11-inch", runtime: "iOS-26-2", model: "iPad-Air-11", days: 0.1, size: 1_700 * mb),
            // Running.
            device(45, "iPhone 17 Pro Max", runtime: "iOS-26-2", model: "iPhone-17-Pro-Max", days: 0.02, state: "Booted", size: 3_200 * mb),
            // Unavailable: its system is not installed.
            device(46, "iPhone 15", runtime: "iOS-17-5", model: "iPhone-15", days: 140, available: false, size: 1_300 * mb),
            // Other platforms.
            device(47, "Apple Watch Series 11 (46mm)", runtime: "watchOS-26-0", model: "Apple-Watch-Series-11-46mm", days: 95, size: 900 * mb),
            device(48, "Apple Vision Pro", runtime: "xrOS-26-0", model: "Apple-Vision-Pro", days: 12, size: 1_100 * mb),
            // No date.
            device(49, "iPad mini (A17 Pro)", runtime: "iOS-26-2", model: "iPad-mini-A17-Pro", days: nil, size: 650 * mb),
            // Small devices: counted in the footer, not listed.
            device(50, "Apple TV 4K (3rd generation)", runtime: "tvOS-26-0", model: "Apple-TV-4K-3rd-generation", days: 30, size: 62 * mb),
            device(51, "iPhone SE (3rd generation)", runtime: "iOS-26-2", model: "iPhone-SE-3rd-generation", days: 200, size: 38 * mb),
            device(52, "iPad Pro 13-inch (M5)", runtime: "iOS-26-2", model: "iPad-Pro-13-M5", days: 8, size: 24 * mb),
        ]
    }
}
