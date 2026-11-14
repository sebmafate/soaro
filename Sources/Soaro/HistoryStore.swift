import Foundation
import SQLite3

/// Une mesure agrégée (moyenne sur ~30 s). Les champs `nil` n'ont pas pu être mesurés.
struct HistoryRow: Equatable {
    var timestamp: Date
    var cpu: Double?          // 0...1
    var memory: Double?       // 0...1
    var gpu: Double?          // 0...1
    var netDown: Double?      // octets / s
    var netUp: Double?
    var diskRead: Double?
    var diskWrite: Double?
    var battery: Double?      // 0...100
    var cpuTemp: Double?      // °C
    var power: Double?        // W
}

enum HistoryMetric: String, CaseIterable, Identifiable {
    case cpu, memory, gpu, network, disk, battery, temperature, power
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Mémoire"
        case .gpu: "GPU"
        case .network: "Réseau"
        case .disk: "Disque (E/S)"
        case .battery: "Batterie"
        case .temperature: "Température"
        case .power: "Consommation"
        }
    }
}

enum HistoryRange: String, CaseIterable, Identifiable {
    case hour, day, week, month
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hour: "1 h"
        case .day: "24 h"
        case .week: "7 j"
        case .month: "30 j"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .hour: 3_600
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        }
    }

    /// Taille des tranches de regroupement (≈ 120 à 360 points par graphique).
    var bucket: Int {
        switch self {
        case .hour: 30
        case .day: 300
        case .week: 1_800
        case .month: 7_200
        }
    }
}

/// Historique persistant dans `~/Library/Application Support/Soaro/history.sqlite`.
/// Tous les accès passent par une file série : l'objet est utilisable depuis n'importe quel thread.
final class HistoryStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "soaro.history", qos: .utility)
    static let retention: TimeInterval = 30 * 86_400

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Soaro", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("history.sqlite")
    }

    /// `path` peut être `":memory:"` (tests).
    init?(path: String = HistoryStore.defaultURL.path) {
        guard sqlite3_open(path, &db) == SQLITE_OK else { return nil }
        let schema = """
        CREATE TABLE IF NOT EXISTS samples(
          ts INTEGER PRIMARY KEY,
          cpu REAL, mem REAL, gpu REAL,
          net_down REAL, net_up REAL,
          disk_read REAL, disk_write REAL,
          battery REAL, cpu_temp REAL, power REAL
        );
        """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else { return nil }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
    }

    deinit { sqlite3_close(db) }

    // MARK: Écriture

    func insert(_ row: HistoryRow) {
        queue.async { [self] in
            var stmt: OpaquePointer?
            let sql = "INSERT OR REPLACE INTO samples VALUES (?,?,?,?,?,?,?,?,?,?,?)"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, Int64(row.timestamp.timeIntervalSince1970))
            let values = [row.cpu, row.memory, row.gpu, row.netDown, row.netUp, row.diskRead, row.diskWrite, row.battery, row.cpuTemp, row.power]
            for (i, value) in values.enumerated() {
                if let value { sqlite3_bind_double(stmt, Int32(i + 2), value) } else { sqlite3_bind_null(stmt, Int32(i + 2)) }
            }
            sqlite3_step(stmt)
        }
    }

    func prune(olderThan date: Date = Date().addingTimeInterval(-HistoryStore.retention)) {
        queue.async { [self] in
            sqlite3_exec(db, "DELETE FROM samples WHERE ts < \(Int64(date.timeIntervalSince1970))", nil, nil, nil)
        }
    }

    func clear() {
        queue.async { [self] in sqlite3_exec(db, "DELETE FROM samples", nil, nil, nil) }
    }

    // MARK: Lecture

    /// Mesures de la période, regroupées en tranches de `range.bucket` secondes (moyenne).
    func query(range: HistoryRange, now: Date = Date()) async -> [HistoryRow] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: queryNow(range: range, now: now))
            }
        }
    }

    private func queryNow(range: HistoryRange, now: Date) -> [HistoryRow] {
        let from = Int64(now.addingTimeInterval(-range.duration).timeIntervalSince1970)
        let sql = """
        SELECT (ts / ?1) * ?1 AS t, AVG(cpu), AVG(mem), AVG(gpu), AVG(net_down), AVG(net_up),
               AVG(disk_read), AVG(disk_write), AVG(battery), AVG(cpu_temp), AVG(power)
        FROM samples WHERE ts >= ?2 GROUP BY t ORDER BY t
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(range.bucket))
        sqlite3_bind_int64(stmt, 2, from)

        func column(_ i: Int32) -> Double? {
            sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, i)
        }
        var rows: [HistoryRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(HistoryRow(
                timestamp: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 0))),
                cpu: column(1), memory: column(2), gpu: column(3),
                netDown: column(4), netUp: column(5), diskRead: column(6), diskWrite: column(7),
                battery: column(8), cpuTemp: column(9), power: column(10)
            ))
        }
        return rows
    }
}

// MARK: - Agrégation

/// Moyenne les mesures reçues toutes les 3 s pour produire une ligne par ~30 s.
struct HistoryAccumulator {
    private var rows: [HistoryRow] = []
    let flushEvery: Int

    init(flushEvery: Int = 10) { self.flushEvery = flushEvery }

    /// Ajoute une mesure ; renvoie la ligne agrégée quand la fenêtre est pleine.
    mutating func add(_ row: HistoryRow) -> HistoryRow? {
        rows.append(row)
        guard rows.count >= flushEvery else { return nil }
        defer { rows.removeAll(keepingCapacity: true) }
        func mean(_ keyPath: KeyPath<HistoryRow, Double?>) -> Double? {
            let values = rows.compactMap { $0[keyPath: keyPath] }
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        return HistoryRow(
            timestamp: rows.last!.timestamp,
            cpu: mean(\.cpu), memory: mean(\.memory), gpu: mean(\.gpu),
            netDown: mean(\.netDown), netUp: mean(\.netUp),
            diskRead: mean(\.diskRead), diskWrite: mean(\.diskWrite),
            battery: mean(\.battery), cpuTemp: mean(\.cpuTemp), power: mean(\.power)
        )
    }
}
