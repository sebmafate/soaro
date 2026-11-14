import Foundation
import Testing
@testable import Accalmie

private let GB: UInt64 = 1_000_000_000

private func snapshot(
    cpu: Double = 0.1,
    pressure: MemoryPressure = .normal,
    swap: UInt64 = 0,
    diskTotal: UInt64 = 500 * GB,
    diskFree: UInt64 = 300 * GB,
    thermal: ProcessInfo.ThermalState = .nominal,
    uptime: TimeInterval = 3_600
) -> SystemSnapshot {
    SystemSnapshot(
        date: Date(),
        cpu: CPUStats(user: cpu, system: 0),
        memory: MemoryStats(total: 16 * GB, app: 6 * GB, wired: 2 * GB, compressed: 1 * GB, cached: 3 * GB, swapUsed: swap, pressure: pressure),
        disk: DiskStats(total: diskTotal, available: diskFree),
        thermalState: thermal,
        uptime: uptime
    )
}

private func input(
    _ snap: SystemSnapshot,
    processes: [ProcessGroup] = [],
    cpuAvg: Double = 0.1,
    samples: Int = 10,
    cleanup: [CleanupKind: UInt64?] = [:]
) -> EngineInput {
    EngineInput(snapshot: snap, processes: processes, recentCPUAverage: cpuAvg, recentCPUSamples: samples, cleanupSizes: cleanup)
}

private func group(_ name: String, cpu: Double = 1, memory: UInt64 = 100_000_000, quit: Bool = true) -> ProcessGroup {
    ProcessGroup(id: "/Applications/\(name).app", name: name, cpu: cpu, memory: memory, pids: [1],
                 appPath: "/Applications/\(name).app", canQuit: quit)
}

@Suite struct RecommendationEngineTests {
    @Test func healthyMacHasNoRecommendations() {
        #expect(RecommendationEngine.evaluate(input(snapshot())).isEmpty)
    }

    @Test func nearlyFullDiskIsCritical() {
        let recs = RecommendationEngine.evaluate(input(snapshot(diskFree: 20 * GB)))
        #expect(recs.first?.id == "disk.low")
        #expect(recs.first?.severity == .critical)
    }

    @Test func lowDiskIsWarning() {
        let recs = RecommendationEngine.evaluate(input(snapshot(diskFree: 40 * GB)))
        #expect(recs.first?.severity == .warning)
    }

    @Test func comfortableFreeSpaceOnBigDiskIsNotFlagged() {
        // 140 Go libres sur 1 To (14 %) : pas d'alerte.
        let recs = RecommendationEngine.evaluate(input(snapshot(diskTotal: 1_000 * GB, diskFree: 140 * GB)))
        #expect(recs.isEmpty)
    }

    @Test func reclaimableSpaceSuggestsQuickCleanup() {
        let recs = RecommendationEngine.evaluate(input(snapshot(), cleanup: [.caches: 3 * GB, .logs: 0]))
        #expect(recs.contains { $0.action == .quickCleanup })
    }

    @Test func trashIsNotPartOfQuickCleanup() {
        let recs = RecommendationEngine.evaluate(input(snapshot(), cleanup: [.trash: 5 * GB]))
        #expect(!recs.contains { $0.action == .quickCleanup })
        #expect(recs.contains { $0.action == .cleanup(.trash) })
    }

    @Test func unknownSizesAreIgnored() {
        let recs = RecommendationEngine.evaluate(input(snapshot(), cleanup: [.trash: nil, .caches: nil]))
        #expect(recs.isEmpty)
    }

    @Test func memoryPressureSuggestsQuittingHeaviestApp() {
        let procs = [group("Small", memory: 500_000_000), group("Big", memory: 4 * GB), group("Daemon", memory: 9 * GB, quit: false)]
        let recs = RecommendationEngine.evaluate(input(snapshot(pressure: .warning), processes: procs))
        let rec = recs.first { $0.id == "memory.pressure" }
        #expect(rec?.action == .quitApp(path: "/Applications/Big.app", name: "Big"))
    }

    @Test func criticalMemoryOutranksWarnings() {
        let recs = RecommendationEngine.evaluate(input(snapshot(pressure: .critical, diskFree: 80 * GB)))
        #expect(recs.first?.id == "memory.pressure")
    }

    @Test func sustainedCPURequiresEnoughSamples() {
        let procs = [group("Hog", cpu: 250)]
        #expect(RecommendationEngine.evaluate(input(snapshot(), processes: procs, cpuAvg: 0.95, samples: 3)).isEmpty)
        let recs = RecommendationEngine.evaluate(input(snapshot(), processes: procs, cpuAvg: 0.95, samples: 10))
        #expect(recs.first?.action == .quitApp(path: "/Applications/Hog.app", name: "Hog"))
    }

    @Test func nonQuittableCPUHogFallsBackToActivityMonitor() {
        let procs = [group("Hog", cpu: 250, quit: false)]
        let recs = RecommendationEngine.evaluate(input(snapshot(), processes: procs, cpuAvg: 0.95))
        #expect(recs.first?.action == .openActivityMonitor)
    }

    @Test func longUptimeAndThermalAreReported() {
        let recs = RecommendationEngine.evaluate(input(snapshot(thermal: .serious, uptime: 20 * 86_400)))
        #expect(Set(recs.map(\.id)) == ["thermal", "uptime"])
    }
}

@Suite struct ProcessParsingTests {
    @Test func groupsHelpersUnderTheirApp() {
        let output = """
          101   5.0  100000 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
          102  10.0  200000 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)
          103   1.5   50000 /usr/sbin/mDNSResponder
        """
        let groups = SystemSampler.parsePS(output)
        let chrome = groups.first { $0.name == "Google Chrome" }
        #expect(chrome?.pids.sorted() == [101, 102])
        #expect(chrome?.cpu == 15.0)
        #expect(chrome?.memory == 300_000 * 1024)
        #expect(chrome?.appPath == "/Applications/Google Chrome.app")
        #expect(groups.first { $0.name == "mDNSResponder" }?.appPath == nil)
        #expect(groups.count == 2)
    }

    @Test func ignoresMalformedLines() {
        #expect(SystemSampler.parsePS("garbage\n\n  1 x y z").isEmpty)
    }
}

@Suite struct CleanupSafetyTests {
    @Test func refusesPathsOutsideHome() {
        #expect(!CleanupService.isSafeToDelete(URL(fileURLWithPath: "/System/Library")))
        #expect(!CleanupService.isSafeToDelete(URL(fileURLWithPath: "/tmp/whatever")))
    }

    @Test func refusesHomeItself() {
        #expect(!CleanupService.isSafeToDelete(URL(fileURLWithPath: NSHomeDirectory())))
    }

    @Test func acceptsItemsInsideHome() {
        #expect(CleanupService.isSafeToDelete(URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches/foo")))
    }
}

@Suite struct SamplerTests {
    @Test func producesSaneValues() {
        let sampler = SystemSampler()
        _ = sampler.sampleCPU()
        let snap = sampler.snapshot()
        #expect(snap.memory.total > 0)
        #expect(snap.memory.used > 0 && snap.memory.used <= snap.memory.total)
        #expect(snap.disk.total > 0 && snap.disk.available <= snap.disk.total)
        #expect((0...1).contains(snap.cpu.total))
        #expect(snap.uptime > 0)
    }
}
