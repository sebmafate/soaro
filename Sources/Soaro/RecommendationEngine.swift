import Foundation

/// Tout ce dont le moteur a besoin pour décider. Pas d'effet de bord → facile à tester.
struct EngineInput {
    var snapshot: SystemSnapshot
    var processes: [ProcessGroup]
    /// Moyenne du CPU sur les derniers échantillons (0...1) et nombre d'échantillons utilisés.
    var recentCPUAverage: Double
    var recentCPUSamples: Int
    /// Tailles récupérables ; `nil` = inconnu / inaccessible.
    var cleanupSizes: [CleanupKind: UInt64?]
    /// Applications dont la mémoire croît de façon continue (voir `LeakDetector`).
    var leaks: [LeakSuspect] = []
}

enum RecommendationEngine {
    static let gigabyte: UInt64 = 1_000_000_000

    static func evaluate(_ input: EngineInput) -> [Recommendation] {
        var result: [Recommendation] = []
        let s = input.snapshot

        // MARK: Disque
        let free = s.disk.available
        let freeFraction = s.disk.availableFraction
        if s.disk.total > 0 {
            // Seuils bas : sur un gros disque, 15 % libres ne sont pas un problème.
            if freeFraction < 0.05 || free < 10 * gigabyte {
                result.append(Recommendation(
                    id: "disk.low", severity: .critical,
                    title: String(localized: "Disk almost full"),
                    detail: String(localized: "Only \(Format.fileBytes(free)) (\(Format.percent(freeFraction))) left. The system slows down when the disk is full."),
                    action: .openStorageSettings, actionLabel: String(localized: "Open Storage")
                ))
            } else if freeFraction < 0.10 || free < 25 * gigabyte {
                result.append(Recommendation(
                    id: "disk.low", severity: .warning,
                    title: String(localized: "Disk space is getting low"),
                    detail: String(localized: "\(Format.fileBytes(free)) available (\(Format.percent(freeFraction)))."),
                    action: .openStorageSettings, actionLabel: String(localized: "Open Storage")
                ))
            }
        }

        let reclaimable = CleanupKind.quickCleanTotal(sizes: input.cleanupSizes)
        if reclaimable >= 500_000_000 {
            let urgent = freeFraction < 0.10
            result.append(Recommendation(
                id: "cleanup.quick", severity: urgent ? .warning : .info,
                title: String(localized: "\(Format.fileBytes(reclaimable)) can be freed"),
                detail: String(localized: "Caches, logs and build files, safe for your data."),
                action: .quickCleanup, actionLabel: String(localized: "Clean")
            ))
        }

        if let trash = (input.cleanupSizes[.trash] ?? nil), trash >= 500_000_000 {
            result.append(Recommendation(
                id: "cleanup.trash", severity: .info,
                title: String(localized: "The Trash contains \(Format.fileBytes(trash))"),
                detail: String(localized: "Empty it to free up space."),
                action: .cleanup(.trash), actionLabel: String(localized: "Empty")
            ))
        }

        // MARK: Mémoire
        let m = s.memory
        let swapHigh = m.swapUsed >= 3 * gigabyte
        if m.pressure != .normal || swapHigh {
            let heavy = input.processes
                .filter { $0.canQuit && $0.memory >= 400_000_000 }
                .max { $0.memory < $1.memory }
            let severity: Severity = m.pressure == .critical ? .critical : .warning
            let title = m.pressure == .normal ? String(localized: "A lot of swap in use") : String(localized: "Memory under pressure")
            if let heavy, let path = heavy.appPath {
                result.append(Recommendation(
                    id: "memory.pressure", severity: severity, title: title,
                    detail: String(localized: "\(heavy.name) uses \(Format.bytes(heavy.memory)). Quitting it would free up memory."),
                    action: .quitApp(path: path, name: heavy.name), actionLabel: String(localized: "Quit \(heavy.name)")
                ))
            } else {
                result.append(Recommendation(
                    id: "memory.pressure", severity: severity, title: title,
                    detail: String(localized: "Swap: \(Format.bytes(m.swapUsed)). Close apps you are not using."),
                    action: .openActivityMonitor, actionLabel: String(localized: "Activity Monitor")
                ))
            }
        }

        // MARK: CPU
        if input.recentCPUSamples >= 8, input.recentCPUAverage >= 0.80 {
            let culprit = input.processes.max { $0.cpu < $1.cpu }
            if let culprit, culprit.cpu >= 30 {
                let detail = String(localized: "\(culprit.name) has been using about \(Int(culprit.cpu)) % CPU for a while.")
                if culprit.canQuit, let path = culprit.appPath {
                    result.append(Recommendation(
                        id: "cpu.sustained", severity: .warning, title: String(localized: "Processor under heavy load"),
                        detail: detail,
                        action: .quitApp(path: path, name: culprit.name), actionLabel: String(localized: "Quit \(culprit.name)")
                    ))
                } else {
                    result.append(Recommendation(
                        id: "cpu.sustained", severity: .warning, title: String(localized: "Processor under heavy load"),
                        detail: detail, action: .openActivityMonitor, actionLabel: String(localized: "Activity Monitor")
                    ))
                }
            } else {
                result.append(Recommendation(
                    id: "cpu.sustained", severity: .warning, title: String(localized: "Processor under heavy load"),
                    detail: String(localized: "Average usage of \(Format.percent(input.recentCPUAverage)) over the last few seconds."),
                    action: .openActivityMonitor, actionLabel: String(localized: "Activity Monitor")
                ))
            }
        }

        // MARK: Fuites mémoire
        for leak in input.leaks.prefix(2) {
            let detail = String(localized: "+\(Format.bytes(leak.growth)) in \(Format.minutes(leak.minutes)), \(Format.bytes(leak.currentMemory)) now. Restarting it resets its counter.")
            if leak.canQuit, let path = leak.appPath {
                result.append(Recommendation(
                    id: "leak.\(leak.id)", severity: .warning,
                    title: String(localized: "\(leak.name) seems to be leaking memory"), detail: detail,
                    action: .quitApp(path: path, name: leak.name), actionLabel: String(localized: "Quit \(leak.name)")
                ))
            } else {
                result.append(Recommendation(
                    id: "leak.\(leak.id)", severity: .warning,
                    title: String(localized: "\(leak.name) seems to be leaking memory"), detail: detail,
                    action: .openActivityMonitor, actionLabel: String(localized: "Activity Monitor")
                ))
            }
        }

        // MARK: Batterie
        if let b = s.battery {
            if !b.isPluggedIn && b.percent <= 10 {
                result.append(Recommendation(
                    id: "battery.low", severity: .critical,
                    title: String(localized: "Battery very low (\(Int(b.percent)) %)"),
                    detail: String(localized: "Plug in the charger to avoid a shutdown."),
                    action: nil, actionLabel: nil
                ))
            } else if !b.isPluggedIn && b.percent <= 20 {
                result.append(Recommendation(
                    id: "battery.low", severity: .warning,
                    title: String(localized: "Battery low (\(Int(b.percent)) %)"),
                    detail: b.minutesRemaining.map { String(localized: "About \(Format.minutes($0)) of battery left.") } ?? String(localized: "Remember to plug in the charger."),
                    action: nil, actionLabel: nil
                ))
            }
            if let health = b.health, health < 0.80 {
                result.append(Recommendation(
                    id: "battery.health", severity: health < 0.70 ? .warning : .info,
                    title: String(localized: "Battery worn: \(Format.percent(health)) of its original capacity"),
                    detail: String(localized: "\(b.cycleCount) charge cycles. Below 80 %, Apple considers the battery consumed."),
                    action: nil, actionLabel: nil
                ))
            }
            let batteryTemp = b.temperature ?? s.sensors?.battery
            if let t = batteryTemp, t >= 42 {
                result.append(Recommendation(
                    id: "battery.hot", severity: .warning,
                    title: String(localized: "Battery hot (\(Int(t)) °C)"),
                    detail: String(localized: "Prolonged heat wears the battery faster. Avoid charging under a cushion or in the sun."),
                    action: nil, actionLabel: nil
                ))
            }
        }

        // MARK: Température
        if s.thermalState == .serious || s.thermalState == .critical {
            result.append(Recommendation(
                id: "thermal", severity: s.thermalState == .critical ? .critical : .warning,
                title: String(localized: "Your Mac is getting hot"),
                detail: String(localized: "The system is slowing down to cool off. Close heavy tasks and let the machine breathe."),
                action: nil, actionLabel: nil
            ))
        }

        if let cpuTemp = s.sensors?.cpu, cpuTemp >= 95, !result.contains(where: { $0.id == "thermal" }) {
            result.append(Recommendation(
                id: "thermal", severity: .warning,
                title: String(localized: "Processor very hot (\(Int(cpuTemp)) °C)"),
                detail: String(localized: "Close demanding apps and check that the vents are not blocked."),
                action: nil, actionLabel: nil
            ))
        }

        // MARK: Redémarrage
        if s.uptime >= 14 * 86_400 {
            result.append(Recommendation(
                id: "uptime", severity: .info,
                title: String(localized: "No restart for \(Format.uptime(s.uptime))"),
                detail: String(localized: "A restart frees fragmented memory and applies updates."),
                action: nil, actionLabel: nil
            ))
        }

        return result.sorted { $0.severity > $1.severity }
    }
}
