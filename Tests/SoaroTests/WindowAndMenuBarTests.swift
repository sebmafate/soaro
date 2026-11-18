import Foundation
import Testing
@testable import Soaro

@Suite struct MenuBarItemTests {
    private let GB: UInt64 = 1_000_000_000

    private func snapshot(battery: Bool = true) -> SystemSnapshot {
        SystemSnapshot(
            date: Date(), cpu: CPUStats(user: 0.33, system: 0.10),
            memory: MemoryStats(total: 16 * GB, app: 8 * GB, wired: 3 * GB, compressed: 2 * GB, cached: GB, swapUsed: 0, pressure: .normal),
            disk: DiskStats(total: 1_000 * GB, available: 140 * GB),
            thermalState: .nominal, uptime: 100,
            gpu: GPUStats(utilization: 0.06, memoryUsed: 0),
            battery: battery ? BatteryStats(percent: 100, isCharging: true, isPluggedIn: true, isFullyCharged: false, minutesRemaining: nil, cycleCount: 1,
                                            health: 1, designCapacity: nil, maxCapacity: nil, temperature: nil, batteryPower: nil, systemPower: nil, adapterWatts: nil) : nil,
            network: NetworkStats(downRate: 13_000, upRate: 99_000, localIP: nil, wifi: nil, latencyMs: nil)
        )
    }

    @Test func buildsSelectedItemsInFixedOrder() {
        let items = MenuBarItem.items(for: snapshot(), cpu: true, gpu: true, memory: true, disk: true, network: true, battery: true)
        #expect(items == [
            .stacked(label: "CPU", value: Format.percent(0.43)),
            .stacked(label: "GPU", value: Format.percent(0.06)),
            .stacked(label: "RAM", value: Format.percent(0.8125)),
            .stacked(label: "SSD", value: Format.percent(0.86), level: .medium),
            .pair(top: "↑ 99 KB/s", bottom: "↓ 13 KB/s"),
            .battery(percent: 100, charging: true),
        ])
    }

    @Test func skipsUnselectedAndUnavailableMeasures() {
        #expect(MenuBarItem.items(for: snapshot(), cpu: false, gpu: false, memory: false, disk: false, network: false, battery: false).isEmpty)
        // Batterie demandée sur un Mac sans batterie : simplement absente.
        let items = MenuBarItem.items(for: snapshot(battery: false), cpu: true, gpu: false, memory: false, disk: false, network: false, battery: true)
        #expect(items == [.stacked(label: "CPU", value: Format.percent(0.43))])
    }

    @Test func inlineTextJoinsItems() {
        #expect(MenuBarItem.inlineText([]) == nil)
        #expect(MenuBarItem.inlineText([.stacked(label: "CPU", value: "43%"), .pair(top: "↑ 1 KB/s", bottom: "↓ 2 KB/s")]) == "CPU 43% · ↓ 2 KB/s ↑ 1 KB/s")
    }
}

@Suite struct PressureLevelTests {
    private let GB: UInt64 = 1_000_000_000

    @Test func loadThresholds() {
        #expect(PressureLevel.load(0.10) == .normal)
        #expect(PressureLevel.load(0.59) == .normal)
        #expect(PressureLevel.load(0.60) == .medium)
        #expect(PressureLevel.load(0.80) == .high)
        #expect(PressureLevel.load(0.95) == .critical)
        #expect(PressureLevel.load(1.0) == .critical)
    }

    @Test func memoryFollowsRealPressureNotPercentage() {
        func mem(_ pressure: MemoryPressure, swap: UInt64, app: UInt64 = 12) -> MemoryStats {
            MemoryStats(total: 16 * GB, app: app * GB, wired: 2 * GB, compressed: GB, cached: 0, swapUsed: swap, pressure: pressure)
        }
        // 94 % utilisés mais pression normale : c'est le fonctionnement normal de macOS.
        #expect(PressureLevel.memory(mem(.normal, swap: 0)) == .normal)
        #expect(PressureLevel.memory(mem(.warning, swap: 2 * GB)) == .medium)
        #expect(PressureLevel.memory(mem(.warning, swap: 12 * GB)) == .high)       // swap ≥ la moitié de la RAM
        #expect(PressureLevel.memory(mem(.critical, swap: 0, app: 2)) == .critical)
    }

    @Test func diskThresholds() {
        #expect(PressureLevel.disk(0.79) == .normal)
        #expect(PressureLevel.disk(0.86) == .medium)
        #expect(PressureLevel.disk(0.92) == .high)
        #expect(PressureLevel.disk(0.97) == .critical)
    }

    @Test func batteryOnlyMattersWhenUnplugged() {
        func battery(_ percent: Double, plugged: Bool) -> BatteryStats {
            BatteryStats(percent: percent, isCharging: plugged, isPluggedIn: plugged, isFullyCharged: false, minutesRemaining: nil, cycleCount: 1,
                         health: 1, designCapacity: nil, maxCapacity: nil, temperature: nil, batteryPower: nil, systemPower: nil, adapterWatts: nil)
        }
        #expect(PressureLevel.battery(battery(3, plugged: true)) == .normal)
        #expect(PressureLevel.battery(battery(50, plugged: false)) == .normal)
        #expect(PressureLevel.battery(battery(18, plugged: false)) == .medium)
        #expect(PressureLevel.battery(battery(9, plugged: false)) == .high)
        #expect(PressureLevel.battery(battery(4, plugged: false)) == .critical)
    }

    @Test func onlyNonNormalLevelsHaveAColor() {
        #expect(PressureLevel.normal.color == nil)
        #expect(PressureLevel.medium.color != nil && PressureLevel.high.color != nil && PressureLevel.critical.color != nil)
        #expect(MenuBarItem.pair(top: "a", bottom: "b").level == .normal)
    }
}

@Suite struct AdjustableThresholdTests {
    private func makeDefaults() -> (UserDefaults, () -> Void) {
        let name = "soaro.thresholds.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    @Test func customThresholdsChangeTheLevel() {
        let strict = LevelThresholds(medium: 30, high: 50, critical: 70)
        #expect(PressureLevel.load(0.40) == .normal)                          // seuils par défaut
        #expect(PressureLevel.load(0.40, thresholds: strict) == .medium)
        #expect(PressureLevel.load(0.55, thresholds: strict) == .high)
        #expect(PressureLevel.disk(0.86, thresholds: LevelThresholds(medium: 90, high: 95, critical: 98)) == .normal)
    }

    @Test func descendingThresholdsForBattery() {
        let t = LevelThresholds(medium: 40, high: 25, critical: 10)
        #expect(t.level(descending: 50) == .normal)
        #expect(t.level(descending: 40) == .medium)
        #expect(t.level(descending: 20) == .high)
        #expect(t.level(descending: 8) == .critical)
    }

    @Test func savedThresholdsRoundTripAndDefaultsApplyWhenUnset() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        #expect(PressureThresholds.load(from: defaults) == .default)

        var custom = PressureThresholds()
        custom.load = LevelThresholds(medium: 50, high: 70, critical: 90)
        custom.battery = LevelThresholds(medium: 30, high: 15, critical: 5)
        custom.save(to: defaults)
        #expect(PressureThresholds.load(from: defaults) == custom)
    }

    @Test func corruptedPreferencesAreReordered() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        defaults.set(95, forKey: "threshold.load.medium")       // dans le désordre et hors bornes
        defaults.set(40, forKey: "threshold.load.high")
        defaults.set(250, forKey: "threshold.load.critical")
        defaults.set(5, forKey: "threshold.battery.medium")
        defaults.set(50, forKey: "threshold.battery.critical")
        let t = PressureThresholds.load(from: defaults)
        #expect(t.load == LevelThresholds(medium: 40, high: 95, critical: 100))
        #expect(t.battery.medium > t.battery.high && t.battery.high > t.battery.critical)
    }

    @Test func menuBarItemsUseTheGivenThresholds() {
        let GB: UInt64 = 1_000_000_000
        let s = SystemSnapshot(
            date: Date(), cpu: CPUStats(user: 0.4, system: 0.05),
            memory: MemoryStats(total: 16 * GB, app: 8 * GB, wired: 2 * GB, compressed: GB, cached: 0, swapUsed: 0, pressure: .normal),
            disk: DiskStats(total: 1_000 * GB, available: 140 * GB), thermalState: .nominal, uptime: 1
        )
        var t = PressureThresholds()
        t.load = LevelThresholds(medium: 40, high: 60, critical: 80)
        t.disk = LevelThresholds(medium: 90, high: 95, critical: 99)
        let items = MenuBarItem.items(for: s, cpu: true, gpu: false, memory: false, disk: true, network: false, battery: false, thresholds: t)
        #expect(items == [.stacked(label: "CPU", value: Format.percent(0.45), level: .medium), .stacked(label: "SSD", value: Format.percent(0.86), level: .normal)])
    }
}

@Suite struct MenuBarTooltipTests {
    private let GB: UInt64 = 1_000_000_000

    private func snapshot() -> SystemSnapshot {
        SystemSnapshot(
            date: Date(), cpu: CPUStats(user: 0.2, system: 0.1),
            memory: MemoryStats(total: 16 * GB, app: 8 * GB, wired: 3 * GB, compressed: 2 * GB, cached: GB, swapUsed: 12 * GB, pressure: .warning),
            disk: DiskStats(total: 1_000 * GB, available: 140 * GB), thermalState: .nominal, uptime: 100
        )
    }

    private func rec(_ id: String, _ severity: Severity, _ title: String) -> Recommendation {
        Recommendation(id: id, severity: severity, title: title, detail: "Detail of \(title)", action: nil, actionLabel: nil)
    }

    @Test func calmStateSaysSo() {
        let text = MenuBarTooltip.text(recommendations: [], snapshot: snapshot(), items: [.stacked(label: "CPU", value: "30%")])
        #expect(text == "Soaro: everything is fine")
    }

    @Test func listsAlertsWithTheirReasonThenSuggestions() {
        let text = MenuBarTooltip.text(
            recommendations: [rec("a", .warning, "Memory under pressure"), rec("b", .info, "28 GB to free")],
            snapshot: snapshot(), items: []
        )
        #expect(text.hasPrefix("Soaro: 1 attention point\n• Memory under pressure\n   Detail of Memory under pressure"))
        #expect(text.contains("1 suggestion:\n• 28 GB to free"))
        #expect(!text.contains("Detail of 28 GB"))                  // les suggestions restent courtes
    }

    @Test func criticalAlertsAreMarkedAndCounted() {
        let text = MenuBarTooltip.text(recommendations: [rec("a", .critical, "Disk almost full"), rec("b", .warning, "CPU overloaded")], snapshot: nil, items: [])
        #expect(text.hasPrefix("Soaro: 2 attention points\n⚠︎ Disk almost full"))
        #expect(text.contains("• CPU overloaded"))
    }

    @Test func explainsEveryColouredValue() {
        let s = snapshot()
        let items = MenuBarItem.items(for: s, cpu: true, gpu: false, memory: true, disk: true, network: false, battery: false)
        let lines = MenuBarTooltip.explanations(for: items, snapshot: s)
        #expect(lines.count == 2)                                    // CPU à 30 % : normal, donc pas d'explication
        #expect(lines[0].hasPrefix("Memory: high pressure, swap") && lines[0].hasSuffix("(level: high)"))
        #expect(lines[1].hasPrefix("Disk \(Format.percent(0.86)) full") && lines[1].hasSuffix("(level: medium)"))

        let text = MenuBarTooltip.text(recommendations: [], snapshot: s, items: items)
        #expect(text.contains("Colored values:"))
    }
}

@Suite struct RateFormatTests {
    private let en = Locale(identifier: "en_US")
    private let fr = Locale(identifier: "fr_FR")

    @Test func shortUnitsOnly() {
        #expect(Format.rate(0, locale: en) == "0 B/s")
        #expect(Format.rate(512, locale: en) == "512 B/s")
        #expect(Format.rate(999, locale: en) == "999 B/s")
        #expect(Format.rate(1_000, locale: en) == "1 KB/s")
        #expect(Format.rate(99_400, locale: en) == "99 KB/s")
        #expect(Format.rate(1_500_000, locale: en) == "1.5 MB/s")
        #expect(Format.rate(2_300_000_000, locale: en) == "2.3 GB/s")
        #expect(!Format.rate(5, locale: en).contains("bytes"))
    }

    @Test func decimalSeparatorFollowsTheLanguage() {
        #expect(Format.rate(1_500_000, locale: fr) == "1,5 MB/s")
        #expect(Format.menuBarRate(12_400_000, locale: fr) == "12,4 MB/s")
    }

    @Test func menuBarNeverShowsBytes() {
        #expect(Format.menuBarRate(0, locale: en) == "0 KB/s")
        #expect(Format.menuBarRate(400, locale: en) == "0 KB/s")
        #expect(Format.menuBarRate(600, locale: en) == "1 KB/s")
        #expect(Format.menuBarRate(99_000, locale: en) == "99 KB/s")
        #expect(Format.menuBarRate(999_700, locale: en) == "1.0 MB/s")           // jamais « 1000 KB/s »
        #expect(Format.menuBarRate(12_400_000, locale: en) == "12.4 MB/s")
    }

    @Test func percentFollowsTheLanguage() {
        #expect(Format.percent(0.43, locale: en) == "43%")
        #expect(Format.percent(0, locale: en) == "0%")
        #expect(Format.percent(1, locale: en) == "100%")
        // En français, l'espace avant « % » est une espace insécable fine.
        #expect(Format.percent(0.43, locale: fr).replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ") == "43 %")
    }

    @Test func bytesNeverSpellOutZero() {
        #expect(Format.bytes(0, locale: en) == "0 bytes")
        #expect(!Format.fileBytes(0, locale: en).lowercased().contains("zero"))
        #expect(Format.fileBytes(1_500_000_000, locale: en) == "1.5 GB")
    }

    @Test func durationsUseTheLanguageAbbreviations() {
        #expect(Format.minutes(45, locale: en) == "45m")
        #expect(Format.minutes(192, locale: en) == "3h 12m")
        #expect(Format.uptime(5 * 86_400 + 9 * 3_600 + 1_234, locale: en) == "5d 9h")
        #expect(Format.uptime(3 * 3_600 + 5 * 60, locale: en) == "3h 5m")
        #expect(Format.uptime(5 * 86_400 + 9 * 3_600, locale: fr) == "5j 9h")
        #expect(Format.uptime(5 * 86_400 + 9 * 3_600, locale: Locale(identifier: "ja_JP")) == "5日9時間")
    }
}

@Suite struct MachineInfoTests {
    @Test func parsesSystemProfilerOutput() throws {
        let json = """
        {"SPHardwareDataType":[{"_name":"hardware_overview","chip_type":"Apple M1 Pro","machine_model":"MacBookPro18,1",
          "machine_name":"MacBook Pro","number_processors":"proc 10:0:8:2","physical_memory":"16 GB","serial_number":"ABC123"}]}
        """
        let hardware = try #require(MachineInfo.parseHardware(Data(json.utf8)))
        #expect(hardware["machine_name"] == "MacBook Pro")
        #expect(hardware["chip_type"] == "Apple M1 Pro")
        #expect(hardware["machine_model"] == "MacBookPro18,1")
        #expect(MachineInfo.parseHardware(Data("pas du json".utf8)) == nil)
        #expect(MachineInfo.parseHardware(Data("{}".utf8)) == nil)
    }

    @Test func titleCombinesModelAndChip() {
        var info = MachineInfo(modelName: "MacBook Pro", modelIdentifier: nil, chip: "Apple M1 Pro", serialNumber: nil, totalCores: 10,
                               performanceCores: 8, efficiencyCores: 2, gpuCores: 16, memory: 0, osVersion: "macOS 27.0", displays: [])
        #expect(info.title == "MacBook Pro (M1 Pro)")
        info.chip = nil
        #expect(info.title == "MacBook Pro")
    }
}

@Suite struct VisibilityTests {
    @MainActor @Test func activeTabsFollowWhatIsOnScreen() {
        let state = AppState(history: nil)
        #expect(state.activeTabs.isEmpty && !state.isUIVisible)

        state.activeTab = .network
        state.isPopoverVisible = true
        #expect(state.activeTabs == [.network])

        state.isWindowVisible = true
        state.windowTab = .battery
        #expect(state.activeTabs == [.network, .battery])

        state.isPopoverVisible = false
        #expect(state.activeTabs == [.battery] && state.isUIVisible)

        state.windowTab = nil                      // section « Ce Mac » ou réglages : aucune mesure coûteuse
        #expect(state.activeTabs.isEmpty && state.isUIVisible)
    }
}
