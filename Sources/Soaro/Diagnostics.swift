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
        print("== Réglages lus")
        print("limite de charge : \(facts.chargeLimit.map { "\($0) %" } ?? "aucune")")
        print("mode économie d'énergie : \(facts.lowPowerMode ? "activé" : "désactivé")")
        print("veille empêchée par : " + (facts.sleepBlockers.isEmpty ? "aucune app tierce" : facts.sleepBlockers.map { "\($0.name) (\(Format.minutes($0.seconds / 60)))" }.joined(separator: ", ")))
        print("programmes au démarrage (actifs) : \(facts.enabledAgentCount)")
        print("corbeille vidée automatiquement : \(facts.autoEmptyTrash ? "oui" : "non")")
        print("mise à jour en attente : \(facts.pendingUpdateVersion ?? "aucune")")
        print("Time Machine : \(facts.timeMachineConfigured ? "configuré" : "non configuré"), dernière sauvegarde : \(facts.lastBackup.map { "\($0)" } ?? "inconnue")")

        let sampler = SystemSampler()
        let snap = sampler.snapshot()
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
        let list = AdviceEngine.evaluate(AdviceInput(facts: facts, battery: BatterySampler.sample(), disk: snap.disk,
                                                     processes: SystemSampler.processGroups(), osVersion: os))
        print("== Conseils (\(list.count))")
        for item in list {
            print("• \(item.title)")
            print("    \(item.detail)")
            if let label = item.actionLabel { print("    [\(label)]") }
        }
        exit(0)
    }

    /// `Soaro --scan` : lance les scanners de nettoyage en LECTURE SEULE sur le vrai dossier personnel.
    static func scan() -> Never {
        func timed<T>(_ label: String, _ block: () -> T) -> T {
            let start = Date()
            let result = block()
            print(String(format: "(%@ : %.1f s)", label, Date().timeIntervalSince(start)))
            return result
        }

        print("== Caches de nettoyage")
        for kind in CleanupKind.allCases {
            let size = CleanupService.size(of: kind)
            print("\(kind.title) : \(size.map(Format.fileBytes) ?? "inaccessible / absent")")
        }

        if CommandLine.arguments.contains("--per-root") {
            print("== Temps par racine")
            for root in LargeFileScanner.defaultRoots() {
                let start = Date()
                _ = LargeFileScanner.scan(roots: [root], minSize: 200_000_000, limit: 1)
                print(String(format: "%5.1f s  %@", Date().timeIntervalSince(start), root.lastPathComponent))
            }
        }

        print("== Gros fichiers (> 200 Mo)")
        let files = timed("scan") { LargeFileScanner.scan(roots: LargeFileScanner.defaultRoots(), minSize: 200_000_000, limit: 8) }
        for f in files { print("\(Format.fileBytes(f.size))  \(f.folder)/\(f.name)") }

        print("== Projets (node_modules, .build, target, Pods)")
        let artifacts = timed("scan") { DevArtifactScanner.scan() }
        print("\(artifacts.count) dossiers, \(Format.fileBytes(artifacts.reduce(0) { $0 + $1.size })) au total")
        for a in artifacts.prefix(8) {
            print("\(Format.fileBytes(a.size))  \(a.kind.label)  \(a.projectPath)  (inactif \(a.daysInactive().map(String.init) ?? "?") j)")
        }

        print("== Applications installées")
        let apps = AppUninstaller.installedApps()
        print("\(apps.count) apps, \(apps.filter(AppUninstaller.canUninstall).count) désinstallables")
        if let sample = apps.first(where: AppUninstaller.canUninstall) {
            let left = AppUninstaller.leftovers(for: sample)
            print("exemple « \(sample.name) » (\(sample.bundleID ?? "?")) : \(left.count) restes")
            for l in left.prefix(5) { print("  \(l.displayPath)  \(Format.fileBytes(l.size))") }
        }

        print("== Démarrage")
        let disabled = StartupItemsService.disabledLabels()
        let agents = StartupItemsService.launchAgents(disabled: disabled)
        print("\(agents.count) agents tiers, \(disabled.count) services désactivés")
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
        print("cœurs (\(snap.cpu.efficiencyCores) E) : " + cores.joined(separator: " · "))

        print("== Mémoire")
        let m = snap.memory
        print("utilisée \(Format.bytes(m.used)) / \(Format.bytes(m.total)) · pression \(m.pressure.label) · swap \(Format.bytes(m.swapUsed))")

        print("== GPU")
        if let gpu = GPUSampler.sample() {
            print("utilisation \(Format.percent(gpu.utilization)) · mémoire \(Format.bytes(gpu.memoryUsed))")
        } else { print("indisponible") }

        print("== Batterie")
        if let b = BatterySampler.sample() {
            print(String(format: "%.0f %% · branché %@ · en charge %@ · cycles %d", b.percent, b.isPluggedIn ? "oui" : "non", b.isCharging ? "oui" : "non", b.cycleCount))
            print("santé \(b.health.map { Format.percent($0) } ?? "?") (\(b.maxCapacity ?? 0)/\(b.designCapacity ?? 0) mAh) · temp \(b.temperature.map { String(format: "%.1f °C", $0) } ?? "?")")
            print("puissance batterie \(b.batteryPower.map { String(format: "%.1f W", $0) } ?? "?") · système \(b.systemPower.map { String(format: "%.1f W", $0) } ?? "?") · chargeur \(b.adapterWatts.map { "\($0) W" } ?? "—")")
            print("temps restant \(b.minutesRemaining.map(Format.minutes) ?? "—")")
        } else { print("pas de batterie") }

        print("== Réseau")
        print("↓ \(Format.rate(net.downRate)) ↑ \(Format.rate(net.upRate)) · IP \(net.localIP ?? "—")")
        if let w = net.wifi {
            print("Wi-Fi \(w.ssid ?? "(SSID masqué)") · \(w.rssi) dBm · \(Int(w.txRate)) Mb/s · canal \(w.channel.map(String.init) ?? "?")")
        } else { print("Wi-Fi : non connecté") }

        print("== VPN (détection locale)")
        let vpn = VPNDetector.detect(processNames: system.runningProcessNames())
        print("mode \(vpn.mode) · nom \(vpn.name ?? "—") · interface \(vpn.interface ?? "—")")
        if CommandLine.arguments.contains("--public-ip") {
            print("== IP publique (requête vers un service tiers, demandée par --public-ip)")
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                do {
                    let info = try await PublicIPService.fetch()
                    print("\(info.flag ?? "?") \(info.ip) · \(info.country ?? "?") · \(info.city ?? "?") · \(info.provider ?? "?")")
                } catch { print("échec : \(error.localizedDescription)") }
                semaphore.signal()
            }
            semaphore.wait()
        }

        print("== Disque")
        print("libre \(Format.fileBytes(snap.disk.available)) / \(Format.fileBytes(snap.disk.total)) · SMART \(DiskIOSampler.smartStatus() ?? "?")")
        if let io { print("E/S : lecture \(Format.rate(io.readRate)) · écriture \(Format.rate(io.writeRate))") }

        print("== Capteurs")
        if let s = sensors.sample() {
            func t(_ v: Double?) -> String { v.map { String(format: "%.0f °C", $0) } ?? "—" }
            print("CPU \(t(s.cpu)) · GPU \(t(s.gpu)) · SSD \(t(s.ssd)) · batterie \(t(s.battery)) · puissance \(s.systemPower.map { String(format: "%.1f W", $0) } ?? "—")")
            print("ventilateurs : " + (s.fans.isEmpty ? "—" : s.fans.map { "#\($0.index) \(Int($0.rpm)) tr/min" }.joined(separator: ", ")))
            print("capteurs bruts : " + s.all.map { "\($0.name)=\(Int($0.celsius))" }.joined(separator: ", "))
        } else { print("aucun capteur lisible") }

        print("== Trafic par app (nettop)")
        for row in NetworkSampler.processTraffic().sorted(by: { $0.down + $0.up > $1.down + $1.up }).prefix(5) {
            print("\(row.name) (\(row.pid)) ↓ \(Format.rate(row.down)) ↑ \(Format.rate(row.up))")
        }

        print("== Énergie (top)")
        for (pid, impact) in EnergySampler.impactByPID().sorted(by: { $0.value > $1.value }).prefix(5) {
            print("pid \(pid) : \(impact)")
        }
        exit(0)
    }
}
