import Foundation
import Testing
@testable import Soaro

@Suite struct BatteryParsingTests {
    /// Propriétés réelles relevées sur un MacBook Pro M1 Pro (secteur, chargée).
    private func props(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var base: [String: Any] = [
            "BatteryInstalled": true, "CurrentCapacity": 100, "MaxCapacity": 100,
            "ExternalConnected": true, "IsCharging": false, "FullyCharged": true,
            "CycleCount": 240, "Voltage": 12772, "InstantAmperage": 0,
            "TimeRemaining": 65535, "AvgTimeToEmpty": 65535, "AvgTimeToFull": 65535,
            "BatteryData": ["DesignCapacity": 8694, "NominalChargeCapacity": 7725],
            "AdapterDetails": ["Watts": 90],
            "PowerTelemetryData": ["SystemLoad": 29299],
        ]
        base.merge(overrides) { _, new in new }
        return base
    }

    @Test func parsesHealthAndPower() throws {
        let b = try #require(BatterySampler.parse(props()))
        #expect(b.percent == 100)
        #expect(b.isPluggedIn && !b.isCharging && b.isFullyCharged)
        #expect(b.cycleCount == 240)
        #expect(abs((b.health ?? 0) - 7725.0 / 8694.0) < 0.0001)
        #expect(b.adapterWatts == 90)
        #expect(abs((b.systemPower ?? 0) - 29.299) < 0.001)
        #expect(b.minutesRemaining == nil)
    }

    @Test func dischargingUsesTimeRemainingAndNegativePower() throws {
        // L'ampérage négatif est parfois exposé comme un entier non signé géant.
        let negative = NSNumber(value: UInt64(bitPattern: -1500))
        let b = try #require(BatterySampler.parse(props([
            "ExternalConnected": false, "IsCharging": false, "FullyCharged": false,
            "CurrentCapacity": 62, "TimeRemaining": 185, "InstantAmperage": negative,
        ])))
        #expect(b.percent == 62)
        #expect(b.minutesRemaining == 185)
        #expect(b.adapterWatts == nil)
        #expect((b.batteryPower ?? 0) < 0)
        #expect(abs((b.batteryPower ?? 0) - (-19.158)) < 0.01)
    }

    @Test func chargingUsesTimeToFull() throws {
        let b = try #require(BatterySampler.parse(props(["IsCharging": true, "FullyCharged": false, "CurrentCapacity": 40, "AvgTimeToFull": 75])))
        #expect(b.minutesRemaining == 75)
    }

    @Test func noBatteryReturnsNil() {
        #expect(BatterySampler.parse(["BatteryInstalled": false]) == nil)
        #expect(BatterySampler.parse([:]) == nil)
    }
}

@Suite struct NetworkParsingTests {
    @Test func counterWrapIsHandled() {
        #expect(NetworkSampler.delta32(100, 40) == 60)
        #expect(NetworkSampler.delta32(10, UInt32.max - 5) == 16)
    }

    @Test func parsesPing() {
        #expect(NetworkSampler.parsePing("64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=12.345 ms") == 12.345)
        #expect(NetworkSampler.parsePing("Request timeout for icmp_seq 0") == nil)
    }

    @Test func nettopKeepsOnlyTheSecondBlock() {
        let output = """
        ,bytes_in,bytes_out,
        Safari.100,999999,999999,
        ,bytes_in,bytes_out,
        Google Chrome.4242,2048,1024,
        com.apple.WebKit.Networking.77,500,0,
        idle.5,0,0,
        """
        let rows = NetworkSampler.parseNettop(output)
        #expect(rows.count == 2)
        #expect(rows[0] == NetworkTrafficRow(pid: 4242, name: "Google Chrome", down: 2048, up: 1024))
        #expect(rows[1].name == "com.apple.WebKit.Networking" && rows[1].pid == 77)
    }
}

@Suite struct EnergyParsingTests {
    @Test func parsesLastTopSample() {
        let output = """
        PID    POWER
        1      99.0
        PID    POWER
        478    40.3
        92321  37,2
        """
        #expect(EnergySampler.parseTop(output) == [478: 40.3, 92321: 37.2])
    }
}

@Suite struct SMCDecodingTests {
    @Test func decodesFloatsAndIntegers() {
        // 1234.5 en flottant IEEE little-endian
        let bits = Float(1234.5).bitPattern
        let flt = SMCReader.Value(type: "flt ", bytes: [UInt8(bits & 0xff), UInt8(bits >> 8 & 0xff), UInt8(bits >> 16 & 0xff), UInt8(bits >> 24 & 0xff)])
        #expect(SMCReader.decode(flt) == 1234.5)
        #expect(SMCReader.decode(.init(type: "ui8 ", bytes: [2])) == 2)
        #expect(SMCReader.decode(.init(type: "ui16", bytes: [0x04, 0xD2])) == 1234)
        #expect(SMCReader.decode(.init(type: "sp78", bytes: [0x2A, 0x80])) == 42.5)
        #expect(SMCReader.decode(.init(type: "fpe2", bytes: [0x0F, 0xA0])) == 1000)
        #expect(SMCReader.decode(.init(type: "????", bytes: [1, 2])) == nil)
    }

    @Test func sensorAverageIgnoresOutliers() {
        let sensors = [
            TemperatureSensor(name: "PMU tdie1", celsius: 40),
            TemperatureSensor(name: "PMU tdie2", celsius: 50),
            TemperatureSensor(name: "PMU tdie3", celsius: -127),     // capteur absent
            TemperatureSensor(name: "NAND CH0 temp", celsius: 31),
        ]
        #expect(SensorSampler.average(sensors, matching: ["tdie"]) == 45)
        #expect(SensorSampler.average(sensors, matching: ["nand"]) == 31)
        #expect(SensorSampler.average(sensors, matching: ["gpu"]) == nil)
    }
}

@Suite struct HistoryStoreTests {
    @Test func storesAndAggregatesByBucket() async throws {
        let store = try #require(HistoryStore(path: ":memory:"))
        let now = Date()
        // 4 points dans la même tranche de 30 s (ts alignés) puis 1 point plus ancien
        let base = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 30) * 30)
        for i in 0..<4 {
            store.insert(HistoryRow(timestamp: base.addingTimeInterval(Double(i)), cpu: Double(i) / 10, memory: 0.5))
        }
        store.insert(HistoryRow(timestamp: base.addingTimeInterval(-600), cpu: 0.9, battery: 80))

        let rows = await store.query(range: .hour, now: now)
        #expect(rows.count == 2)
        #expect(rows.first?.battery == 80)
        let latest = try #require(rows.last)
        #expect(abs((latest.cpu ?? 0) - 0.15) < 0.0001)     // moyenne de 0, 0.1, 0.2, 0.3
        #expect(latest.gpu == nil)
    }

    @Test func pruneRemovesOldRows() async throws {
        let store = try #require(HistoryStore(path: ":memory:"))
        store.insert(HistoryRow(timestamp: Date().addingTimeInterval(-40 * 86_400), cpu: 1))
        store.insert(HistoryRow(timestamp: Date(), cpu: 0.2))
        store.prune()
        let rows = await store.query(range: .month)
        #expect(rows.count == 1)
    }

    @Test func accumulatorFlushesAveragedRow() {
        var acc = HistoryAccumulator(flushEvery: 3)
        #expect(acc.add(HistoryRow(timestamp: Date(), cpu: 0.2, battery: nil)) == nil)
        #expect(acc.add(HistoryRow(timestamp: Date(), cpu: 0.4, battery: 50)) == nil)
        let row = acc.add(HistoryRow(timestamp: Date(), cpu: 0.6, battery: 70))
        #expect(abs((row?.cpu ?? 0) - 0.4) < 0.0001)
        #expect(row?.battery == 60)
    }
}

@Suite struct LeakDetectorTests {
    private func series(minutes: Int, step: Int = 1, start: UInt64, perMinute: Double, noise: Double = 0) -> [LeakDetector.Point] {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        return stride(from: 0, through: minutes, by: step).map { m in
            let jitter = noise * sin(Double(m))
            return .init(date: t0.addingTimeInterval(Double(m) * 60), bytes: UInt64(max(0, Double(start) + Double(m) * perMinute + jitter)))
        }
    }

    @Test func steadyGrowthIsALeak() {
        // 600 Mo → ~1,6 Go en 60 min
        let verdict = LeakDetector.isLeaking(series(minutes: 60, start: 600_000_000, perMinute: 17_000_000, noise: 5_000_000))
        #expect(verdict != nil)
        #expect((verdict?.growth ?? 0) > 900_000_000)
    }

    @Test func flatUsageIsNotALeak() {
        #expect(LeakDetector.isLeaking(series(minutes: 60, start: 1_000_000_000, perMinute: 0, noise: 20_000_000)) == nil)
    }

    @Test func oneBigJumpIsNotALeak() {
        var points = series(minutes: 60, start: 500_000_000, perMinute: 0)
        for i in 40..<points.count { points[i].bytes = 2_000_000_000 }      // saut brutal (ouverture d'un gros document)
        #expect(LeakDetector.isLeaking(points) == nil)
    }

    @Test func tooShortObservationIsIgnored() {
        #expect(LeakDetector.isLeaking(series(minutes: 15, start: 600_000_000, perMinute: 50_000_000)) == nil)
    }

    @Test func trackerForgetsClosedApps() {
        var tracker = MemoryTrendTracker()
        tracker.sampleInterval = 0
        let app = ProcessGroup(id: "/Applications/A.app", name: "A", cpu: 1, memory: 500_000_000, pids: [1], appPath: "/Applications/A.app")
        tracker.record([app], at: Date())
        #expect(tracker.series[app.id]?.count == 1)
        tracker.record([], at: Date().addingTimeInterval(60))
        #expect(tracker.series[app.id] == nil)
    }
}

@Suite struct NewRecommendationTests {
    private let GB: UInt64 = 1_000_000_000

    private func snapshot(battery: BatteryStats? = nil, sensors: SensorStats? = nil) -> SystemSnapshot {
        SystemSnapshot(
            date: Date(), cpu: CPUStats(user: 0.1, system: 0),
            memory: MemoryStats(total: 16 * GB, app: 6 * GB, wired: 2 * GB, compressed: GB, cached: 3 * GB, swapUsed: 0, pressure: .normal),
            disk: DiskStats(total: 500 * GB, available: 300 * GB),
            thermalState: .nominal, uptime: 3_600, battery: battery, sensors: sensors
        )
    }

    private func battery(percent: Double = 80, plugged: Bool = false, health: Double? = 0.95, temp: Double? = nil) -> BatteryStats {
        BatteryStats(percent: percent, isCharging: false, isPluggedIn: plugged, isFullyCharged: false, minutesRemaining: 45,
                     cycleCount: 300, health: health, designCapacity: 8000, maxCapacity: 7600, temperature: temp,
                     batteryPower: nil, systemPower: nil, adapterWatts: nil)
    }

    private func evaluate(_ snap: SystemSnapshot, leaks: [LeakSuspect] = []) -> [Recommendation] {
        RecommendationEngine.evaluate(EngineInput(snapshot: snap, processes: [], recentCPUAverage: 0.1, recentCPUSamples: 10, cleanupSizes: [:], leaks: leaks))
    }

    @Test func healthyBatteryIsSilent() {
        #expect(evaluate(snapshot(battery: battery())).isEmpty)
    }

    @Test func lowBatterySeverity() {
        #expect(evaluate(snapshot(battery: battery(percent: 18))).first?.severity == .warning)
        #expect(evaluate(snapshot(battery: battery(percent: 8))).first?.severity == .critical)
        // Branchée : pas d'alerte de niveau
        #expect(evaluate(snapshot(battery: battery(percent: 8, plugged: true))).isEmpty)
    }

    @Test func wornBatteryIsReported() {
        let recs = evaluate(snapshot(battery: battery(health: 0.78)))
        #expect(recs.first?.id == "battery.health")
        #expect(recs.first?.severity == .info)
        #expect(evaluate(snapshot(battery: battery(health: 0.65))).first?.severity == .warning)
    }

    @Test func hotBatteryFallsBackToSensorReading() {
        let recs = evaluate(snapshot(battery: battery(), sensors: SensorStats(battery: 44)))
        #expect(recs.contains { $0.id == "battery.hot" })
    }

    @Test func veryHotCPUIsReportedOnce() {
        let recs = evaluate(snapshot(sensors: SensorStats(cpu: 98)))
        #expect(recs.filter { $0.id == "thermal" }.count == 1)
    }

    @Test func leakSuspectBecomesRecommendation() {
        let leak = LeakSuspect(id: "/Applications/Leaky.app", name: "Leaky", appPath: "/Applications/Leaky.app", canQuit: true,
                               growth: 2 * GB, minutes: 90, currentMemory: 3 * GB)
        let rec = evaluate(snapshot(), leaks: [leak]).first
        #expect(rec?.id == "leak./Applications/Leaky.app")
        #expect(rec?.action == .quitApp(path: "/Applications/Leaky.app", name: "Leaky"))
    }
}
