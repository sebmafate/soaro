import Foundation

/// `Soaro --diagnostics` : affiche toutes les mesures en texte puis quitte.
/// Utile pour vérifier ce que lit chaque capteur sur une machine donnée.
enum Diagnostics {
    static var isRequested: Bool { CommandLine.arguments.contains("--diagnostics") }
    static var isScanRequested: Bool { CommandLine.arguments.contains("--scan") }
    static var isAdviceRequested: Bool { CommandLine.arguments.contains("--advice") }

    /// `Soaro --advice` : affiche les réglages lus sur ce Mac et les conseils qui en découlent. Lecture seule.
    static func advice() -> Never {
        let facts = AdviceProbe.collect()
        print("== Settings read")
        print("charge limit: \(facts.chargeLimit.map { "\($0) %" } ?? "none")")
        print("Low Power Mode: \(facts.lowPowerMode ? "on" : "off")")
        print("sleep prevented by: " + (facts.sleepBlockers.isEmpty ? "no third-party app" : facts.sleepBlockers.map { "\($0.name) (\(Format.minutes($0.seconds / 60)))" }.joined(separator: ", ")))
        print("login programs (enabled): \(facts.enabledAgentCount)")
        print("Trash emptied automatically: \(facts.autoEmptyTrash ? "yes" : "no")")
        print("pending update: \(facts.pendingUpdateVersion ?? "none")")
        print("Time Machine: \(facts.timeMachineConfigured ? "configured" : "not configured"), last backup: \(facts.lastBackup.map { "\($0)" } ?? "unknown")")

        let sampler = SystemSampler()
        let snap = sampler.snapshot()
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
        let list = AdviceEngine.evaluate(AdviceInput(facts: facts, battery: BatterySampler.sample(), disk: snap.disk,
                                                     processes: SystemSampler.processGroups(), osVersion: os))
        print("== Tips (\(list.count))")
        for item in list {
            print("• \(item.title)")
            print("    \(item.detail)")
            if let label = item.actionLabel { print("    [\(label)]") }
        }
        exit(0)
    }

    /// Scan des simulateurs de `--scan`, avec la MÊME porte que l'application : détection sans rien lancer, et `xcrun` n'est transmis
    /// que si le `simctl` actif est sur le disque. Sinon « tool not found » et rien n'est lancé.
    static func simulatorScan(runner: CommandRunner, home: URL, fileSystem: ToolFileSystem = DiskToolFileSystem(),
                              locate: ([String]) -> String? = { ToolLocator.firstExecutable(in: $0) }) -> SimulatorScan {
        let detection = SimulatorToolDetector.detect(home: home, fileSystem: fileSystem)
        return SimulatorScanner.scan(runner: runner, xcrunPath: ToolLocator.simulatorXcrunPath(detection: detection, locate: locate), home: home)
    }

    /// Scan Android de `--scan` : SDK, AVD et `ps` (même listage que l'application), puis la taille allouée de chaque dossier.
    /// Sans SDK : rien n'est lu ni lancé. LECTURE SEULE.
    static func androidScan(runner: CommandRunner, home: URL, environment: [String: String],
                            locate: ([String]) -> String? = { ToolLocator.firstExecutable(in: $0) },
                            measure: (URL) -> UInt64 = { CleanupService.allocatedSize(of: $0) }) -> AndroidScan {
        let listing = AndroidEmulatorScanner.list(runner: runner, psPath: locate(ToolLocator.processListCandidates),
                                                  environment: environment, home: home)
        let sized = listing.devices.map { SizedAndroidDevice(device: $0, size: measure($0.folder)) }
        return AndroidScan(status: listing.status, sdk: listing.sdk, devices: sized, skippedCount: listing.skippedCount)
    }

    /// `Soaro --scan` : lance les scanners de nettoyage en LECTURE SEULE sur le vrai dossier personnel.
    static func scan() -> Never {
        func timed<T>(_ label: String, _ block: () -> T) -> T {
            let start = Date()
            let result = block()
            print(String(format: "(%@: %.1f s)", label, Date().timeIntervalSince(start)))
            return result
        }

        print("== Cleanup caches")
        for kind in CleanupKind.allCases {
            let size = CleanupService.size(of: kind)
            print("\(kind.title) : \(size.map { Format.fileBytes($0) } ?? "inaccessible / absent")")
        }

        if CommandLine.arguments.contains("--per-root") {
            print("== Time per root")
            for root in LargeFileScanner.defaultRoots() {
                let start = Date()
                _ = LargeFileScanner.scan(roots: [root], minSize: 200_000_000, limit: 1)
                print(String(format: "%5.1f s  %@", Date().timeIntervalSince(start), root.lastPathComponent))
            }
        }

        print("== Large files (> 200 MB)")
        let files = timed("scan") { LargeFileScanner.scan(roots: LargeFileScanner.defaultRoots(), minSize: 200_000_000, limit: 8) }
        for f in files { print("\(Format.fileBytes(f.size))  \(f.folder)/\(f.name)") }

        print("== Projects (node_modules, .build, target, Pods)")
        let artifacts = timed("scan") { DevArtifactScanner.scan() }
        print("\(artifacts.count) folders, \(Format.fileBytes(artifacts.reduce(0) { $0 + $1.size })) in total")
        for a in artifacts.prefix(8) {
            print("\(Format.fileBytes(a.size))  \(a.kind.label)  \(a.projectPath)  (inactive \(a.daysInactive().map(String.init) ?? "?") d)")
        }

        // Simulateurs iOS : lecture seule (`xcrun simctl list devices -j`), puis tailles allouées sur disque.
        // Le vrai lanceur de commandes n'est construit qu'ici et dans `CleanupTab` (jamais ailleurs).
        let simulatorStart = Date()
        let simulators = Self.simulatorScan(runner: RealCommandRunner(), home: URL(fileURLWithPath: NSHomeDirectory()))
        let suggestions = DeviceSuggestions.suggest(simulators.devices, now: Date(), limitDays: DeviceSuggestions.defaultLimitDays)
        for line in SimulatorReport.lines(scan: simulators, suggestions: suggestions, locale: .current,
                                          limitDays: DeviceSuggestions.defaultLimitDays) { print(line) }
        print(String(format: "(scan: %.1f s)", Date().timeIntervalSince(simulatorStart)))

        // Émulateurs Android : lecture seule (dossier des AVD, puis `/bin/ps`), tailles allouées sur disque. Le vrai lanceur est
        // construit ici (endroit déjà permis) ; l'environnement est celui du processus (lancé depuis un terminal pour `ANDROID_SDK_ROOT`).
        let androidStart = Date()
        let android = Self.androidScan(runner: RealCommandRunner(), home: URL(fileURLWithPath: NSHomeDirectory()),
                                       environment: ProcessInfo.processInfo.environment)
        let androidSuggestions = DeviceSuggestions.suggestAndroid(android.devices, now: Date(), limitDays: DeviceSuggestions.defaultLimitDays)
        for line in AndroidEmulatorReport.lines(scan: android, suggestions: androidSuggestions, now: Date(), locale: .current) { print(line) }
        print(String(format: "(scan: %.1f s)", Date().timeIntervalSince(androidStart)))

        print("== Installed apps")
        let apps = AppUninstaller.installedApps()
        print("\(apps.count) apps, \(apps.filter(AppUninstaller.canUninstall).count) can be uninstalled")
        if let sample = apps.first(where: AppUninstaller.canUninstall) {
            let left = AppUninstaller.leftovers(for: sample)
            print("example “\(sample.name)” (\(sample.bundleID ?? "?")): \(left.count) leftovers")
            for l in left.prefix(5) { print("  \(l.displayPath)  \(Format.fileBytes(l.size))") }
        }

        print("== Startup")
        let disabled = StartupItemsService.disabledLabels()
        let agents = StartupItemsService.launchAgents(disabled: disabled)
        print("\(agents.count) third-party agents, \(disabled.count) disabled services")
        for a in agents.prefix(8) { print("  \(a.isDisabled ? "OFF" : "ON ")  \(a.label)") }
        exit(0)
    }

    static func run() -> Never {
        let system = SystemSampler()
        let network = NetworkSampler()
        let diskIO = DiskIOSampler()
        let sensors = SensorSampler()

        _ = system.sampleCPU(); _ = network.sample(); _ = diskIO.sample()
        Thread.sleep(forTimeInterval: 1.5)
        let snap = system.snapshot()
        let net = network.sample()
        let io = diskIO.sample()

        print("== CPU")
        print(String(format: "total %.0f %% (user %.0f %%, sys %.0f %%)", snap.cpu.total * 100, snap.cpu.user * 100, snap.cpu.system * 100))
        let cores = snap.cpu.perCore.enumerated().map { i, v in
            "\(snap.cpu.coreLabel(i)): \(Int(v * 100)) %"
        }
        print("cores (\(snap.cpu.efficiencyCores) E): " + cores.joined(separator: " · "))

        print("== Memory")
        let m = snap.memory
        print("used \(Format.bytes(m.used)) / \(Format.bytes(m.total)) · pressure \(m.pressure.label) · swap \(Format.bytes(m.swapUsed))")

        print("== GPU")
        if let gpu = GPUSampler.sample() {
            print("usage \(Format.percent(gpu.utilization)) · memory \(Format.bytes(gpu.memoryUsed))")
        } else { print("indisponible") }

        print("== Battery")
        if let b = BatterySampler.sample() {
            print(String(format: "%.0f %% · plugged in %@ · charging %@ · cycles %d", b.percent, b.isPluggedIn ? "oui" : "non", b.isCharging ? "oui" : "non", b.cycleCount))
            print("health \(b.health.map { Format.percent($0) } ?? "?") (\(b.maxCapacity ?? 0)/\(b.designCapacity ?? 0) mAh) · temp \(b.temperature.map { String(format: "%.1f °C", $0) } ?? "?")")
            print("battery power \(b.batteryPower.map { String(format: "%.1f W", $0) } ?? "?") · system \(b.systemPower.map { String(format: "%.1f W", $0) } ?? "?") · charger \(b.adapterWatts.map { "\($0) W" } ?? "—")")
            print("time left \(b.minutesRemaining.map { Format.minutes($0) } ?? "—")")
        } else { print("no battery") }

        print("== Network")
        print("↓ \(Format.rate(net.downRate)) ↑ \(Format.rate(net.upRate)) · IP \(net.localIP ?? "—")")
        if let w = net.wifi {
            print("Wi-Fi \(w.ssid ?? "(SSID hidden)") · \(w.rssi) dBm · \(Int(w.txRate)) Mb/s · channel \(w.channel.map(String.init) ?? "?")")
        } else { print("Wi-Fi: not connected") }

        print("== VPN (local detection)")
        let vpn = VPNDetector.detect(processNames: system.runningProcessNames())
        print("mode \(vpn.mode) · name \(vpn.name ?? "—") · interface \(vpn.interface ?? "—")")
        if CommandLine.arguments.contains("--public-ip") {
            print("== Public IP (request to a third-party service, asked for by --public-ip)")
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                do {
                    let info = try await PublicIPService.fetch()
                    print("\(info.flag ?? "?") \(info.ip) · \(info.country ?? "?") · \(info.city ?? "?") · \(info.provider ?? "?")")
                } catch { print("failed: \(error.localizedDescription)") }
                semaphore.signal()
            }
            semaphore.wait()
        }

        print("== Disk")
        print("free \(Format.fileBytes(snap.disk.available)) / \(Format.fileBytes(snap.disk.total)) · SMART \(DiskIOSampler.smartStatus() ?? "?")")
        if let io { print("I/O: read \(Format.rate(io.readRate)) · write \(Format.rate(io.writeRate))") }

        print("== Sensors")
        if let s = sensors.sample() {
            func t(_ v: Double?) -> String { v.map { String(format: "%.0f °C", $0) } ?? "—" }
            print("CPU \(t(s.cpu)) · GPU \(t(s.gpu)) · SSD \(t(s.ssd)) · battery \(t(s.battery)) · power \(s.systemPower.map { String(format: "%.1f W", $0) } ?? "—")")
            print("fans: " + (s.fans.isEmpty ? "—" : s.fans.map { "#\($0.index) \(Int($0.rpm)) rpm" }.joined(separator: ", ")))
            print("raw sensors: " + s.all.map { "\($0.name)=\(Int($0.celsius))" }.joined(separator: ", "))
        } else { print("no readable sensor") }

        print("== Traffic by app (nettop)")
        for row in NetworkSampler.processTraffic().sorted(by: { $0.down + $0.up > $1.down + $1.up }).prefix(5) {
            print("\(row.name) (\(row.pid)) ↓ \(Format.rate(row.down)) ↑ \(Format.rate(row.up))")
        }

        print("== Energy (top)")
        for (pid, impact) in EnergySampler.impactByPID().sorted(by: { $0.value > $1.value }).prefix(5) {
            print("pid \(pid): \(impact)")
        }
        exit(0)
    }
}
