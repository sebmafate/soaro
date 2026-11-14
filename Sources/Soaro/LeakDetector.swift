import Foundation

/// Application dont la mémoire grimpe régulièrement depuis longtemps (fuite probable).
struct LeakSuspect: Equatable, Identifiable {
    var id: String
    var name: String
    var appPath: String?
    var canQuit: Bool
    var growth: UInt64         // octets gagnés sur la période observée
    var minutes: Int           // durée observée
    var currentMemory: UInt64
}

/// Détecte une croissance mémoire linéaire et soutenue. Fonction pure : testable.
enum LeakDetector {
    struct Point: Equatable {
        var date: Date
        var bytes: UInt64
    }

    /// Seuils volontairement conservateurs : mieux vaut rater une fuite que crier au loup.
    static let minDuration: TimeInterval = 30 * 60
    static let minPoints = 20
    static let minGrowth: UInt64 = 500_000_000
    static let minRelativeGrowth = 0.4
    static let minLinearity = 0.85       // R² de la droite de tendance

    static func isLeaking(_ series: [Point]) -> (growth: UInt64, minutes: Int)? {
        guard series.count >= minPoints, let first = series.first, let last = series.last else { return nil }
        let duration = last.date.timeIntervalSince(first.date)
        guard duration >= minDuration, last.bytes > first.bytes else { return nil }

        let growth = last.bytes - first.bytes
        guard growth >= minGrowth, Double(growth) / Double(max(first.bytes, 1)) >= minRelativeGrowth else { return nil }

        // Régression linéaire (x = secondes depuis le début, y = octets) → R²
        let xs = series.map { $0.date.timeIntervalSince(first.date) }
        let ys = series.map { Double($0.bytes) }
        let n = Double(series.count)
        let meanX = xs.reduce(0, +) / n, meanY = ys.reduce(0, +) / n
        var sxx = 0.0, sxy = 0.0, syy = 0.0
        for (x, y) in zip(xs, ys) {
            sxx += (x - meanX) * (x - meanX)
            sxy += (x - meanX) * (y - meanY)
            syy += (y - meanY) * (y - meanY)
        }
        guard sxx > 0, syy > 0 else { return nil }
        let r2 = (sxy * sxy) / (sxx * syy)
        guard r2 >= minLinearity, sxy > 0 else { return nil }
        return (growth, Int(duration / 60))
    }
}

/// Garde les derniers points de mémoire par application pour alimenter le détecteur.
struct MemoryTrendTracker {
    private(set) var series: [String: [LeakDetector.Point]] = [:]
    var maxPoints = 180                       // 3 h à un point par minute
    var minTrackedMemory: UInt64 = 200_000_000
    var sampleInterval: TimeInterval = 55

    private var lastSample = Date.distantPast

    mutating func record(_ groups: [ProcessGroup], at date: Date = Date()) {
        guard date.timeIntervalSince(lastSample) >= sampleInterval else { return }
        lastSample = date

        let alive = Set(groups.map(\.id))
        series = series.filter { alive.contains($0.key) }     // une app fermée repart de zéro
        for group in groups where group.memory >= minTrackedMemory || series[group.id] != nil {
            var points = series[group.id, default: []]
            points.append(.init(date: date, bytes: group.memory))
            series[group.id] = Array(points.suffix(maxPoints))
        }
    }

    func suspects(among groups: [ProcessGroup]) -> [LeakSuspect] {
        groups.compactMap { group in
            guard let points = series[group.id], let verdict = LeakDetector.isLeaking(points) else { return nil }
            return LeakSuspect(
                id: group.id, name: group.name, appPath: group.appPath, canQuit: group.canQuit,
                growth: verdict.growth, minutes: verdict.minutes, currentMemory: group.memory
            )
        }
        .sorted { $0.growth > $1.growth }
    }
}
