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
                    title: "Disque presque plein",
                    detail: "Il ne reste que \(Format.fileBytes(free)) (\(Format.percent(freeFraction))). Le système ralentit quand le disque est saturé.",
                    action: .openStorageSettings, actionLabel: "Ouvrir Stockage"
                ))
            } else if freeFraction < 0.10 || free < 25 * gigabyte {
                result.append(Recommendation(
                    id: "disk.low", severity: .warning,
                    title: "Espace disque en baisse",
                    detail: "\(Format.fileBytes(free)) disponibles (\(Format.percent(freeFraction))).",
                    action: .openStorageSettings, actionLabel: "Ouvrir Stockage"
                ))
            }
        }

        let quickKinds = CleanupKind.allCases.filter(\.includedInQuickClean)
        let reclaimable = quickKinds.reduce(UInt64(0)) { $0 + ((input.cleanupSizes[$1] ?? nil) ?? 0) }
        if reclaimable >= 500_000_000 {
            let urgent = freeFraction < 0.10
            result.append(Recommendation(
                id: "cleanup.quick", severity: urgent ? .warning : .info,
                title: "\(Format.fileBytes(reclaimable)) à récupérer",
                detail: "Caches, journaux et fichiers de compilation sans risque pour vos données.",
                action: .quickCleanup, actionLabel: "Nettoyer"
            ))
        }

        if let trash = (input.cleanupSizes[.trash] ?? nil), trash >= 500_000_000 {
            result.append(Recommendation(
                id: "cleanup.trash", severity: .info,
                title: "La corbeille contient \(Format.fileBytes(trash))",
                detail: "Videz-la pour libérer de l'espace.",
                action: .cleanup(.trash), actionLabel: "Vider"
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
            let title = m.pressure == .normal ? "Beaucoup de swap utilisé" : "Mémoire sous pression"
            if let heavy, let path = heavy.appPath {
                result.append(Recommendation(
                    id: "memory.pressure", severity: severity, title: title,
                    detail: "\(heavy.name) occupe \(Format.bytes(heavy.memory)). Le quitter libérerait de la mémoire.",
                    action: .quitApp(path: path, name: heavy.name), actionLabel: "Quitter \(heavy.name)"
                ))
            } else {
                result.append(Recommendation(
                    id: "memory.pressure", severity: severity, title: title,
                    detail: "Swap : \(Format.bytes(m.swapUsed)). Fermez les applications inutilisées.",
                    action: .openActivityMonitor, actionLabel: "Moniteur d'activité"
                ))
            }
        }

        // MARK: CPU
        if input.recentCPUSamples >= 8, input.recentCPUAverage >= 0.80 {
            let culprit = input.processes.max { $0.cpu < $1.cpu }
            if let culprit, culprit.cpu >= 30 {
                let detail = "\(culprit.name) utilise environ \(Int(culprit.cpu)) % de CPU depuis un moment."
                if culprit.canQuit, let path = culprit.appPath {
                    result.append(Recommendation(
                        id: "cpu.sustained", severity: .warning, title: "Processeur très sollicité",
                        detail: detail,
                        action: .quitApp(path: path, name: culprit.name), actionLabel: "Quitter \(culprit.name)"
                    ))
                } else {
                    result.append(Recommendation(
                        id: "cpu.sustained", severity: .warning, title: "Processeur très sollicité",
                        detail: detail, action: .openActivityMonitor, actionLabel: "Moniteur d'activité"
                    ))
                }
            } else {
                result.append(Recommendation(
                    id: "cpu.sustained", severity: .warning, title: "Processeur très sollicité",
                    detail: "Utilisation moyenne de \(Format.percent(input.recentCPUAverage)) sur les dernières secondes.",
                    action: .openActivityMonitor, actionLabel: "Moniteur d'activité"
                ))
            }
        }

        // MARK: Fuites mémoire
        for leak in input.leaks.prefix(2) {
            let detail = "+\(Format.bytes(leak.growth)) en \(Format.minutes(leak.minutes)), \(Format.bytes(leak.currentMemory)) actuellement. Le relancer remet son compteur à zéro."
            if leak.canQuit, let path = leak.appPath {
                result.append(Recommendation(
                    id: "leak.\(leak.id)", severity: .warning,
                    title: "\(leak.name) semble fuir de la mémoire", detail: detail,
                    action: .quitApp(path: path, name: leak.name), actionLabel: "Quitter \(leak.name)"
                ))
            } else {
                result.append(Recommendation(
                    id: "leak.\(leak.id)", severity: .warning,
                    title: "\(leak.name) semble fuir de la mémoire", detail: detail,
                    action: .openActivityMonitor, actionLabel: "Moniteur d'activité"
                ))
            }
        }

        // MARK: Batterie
        if let b = s.battery {
            if !b.isPluggedIn && b.percent <= 10 {
                result.append(Recommendation(
                    id: "battery.low", severity: .critical,
                    title: "Batterie très faible (\(Int(b.percent)) %)",
                    detail: "Branchez le chargeur pour éviter une extinction.",
                    action: nil, actionLabel: nil
                ))
            } else if !b.isPluggedIn && b.percent <= 20 {
                result.append(Recommendation(
                    id: "battery.low", severity: .warning,
                    title: "Batterie faible (\(Int(b.percent)) %)",
                    detail: b.minutesRemaining.map { "Environ \(Format.minutes($0)) d'autonomie restante." } ?? "Pensez à brancher le chargeur.",
                    action: nil, actionLabel: nil
                ))
            }
            if let health = b.health, health < 0.80 {
                result.append(Recommendation(
                    id: "battery.health", severity: health < 0.70 ? .warning : .info,
                    title: "Batterie usée : \(Format.percent(health)) de sa capacité d'origine",
                    detail: "\(b.cycleCount) cycles de charge. En dessous de 80 %, Apple considère la batterie comme consommée.",
                    action: nil, actionLabel: nil
                ))
            }
            let batteryTemp = b.temperature ?? s.sensors?.battery
            if let t = batteryTemp, t >= 42 {
                result.append(Recommendation(
                    id: "battery.hot", severity: .warning,
                    title: "Batterie chaude (\(Int(t)) °C)",
                    detail: "Une chaleur prolongée use la batterie plus vite. Évitez de charger sous un coussin ou au soleil.",
                    action: nil, actionLabel: nil
                ))
            }
        }

        // MARK: Température
        if s.thermalState == .serious || s.thermalState == .critical {
            result.append(Recommendation(
                id: "thermal", severity: s.thermalState == .critical ? .critical : .warning,
                title: "Le Mac chauffe",
                detail: "Le système réduit les performances pour se refroidir. Fermez les tâches lourdes et aérez la machine.",
                action: nil, actionLabel: nil
            ))
        }

        if let cpuTemp = s.sensors?.cpu, cpuTemp >= 95, !result.contains(where: { $0.id == "thermal" }) {
            result.append(Recommendation(
                id: "thermal", severity: .warning,
                title: "Processeur très chaud (\(Int(cpuTemp)) °C)",
                detail: "Fermez les applications gourmandes et vérifiez que les aérations ne sont pas obstruées.",
                action: nil, actionLabel: nil
            ))
        }

        // MARK: Redémarrage
        if s.uptime >= 14 * 86_400 {
            result.append(Recommendation(
                id: "uptime", severity: .info,
                title: "Pas de redémarrage depuis \(Format.uptime(s.uptime))",
                detail: "Un redémarrage libère la mémoire fragmentée et applique les mises à jour.",
                action: nil, actionLabel: nil
            ))
        }

        return result.sorted { $0.severity > $1.severity }
    }
}
