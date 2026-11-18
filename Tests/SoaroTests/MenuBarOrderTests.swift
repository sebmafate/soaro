import Foundation
import Testing
@testable import Soaro

/// SL22 : l'ordre des mesures dans la barre de menus. Le type pur (lecture tolérante, écriture, déplacements bornés),
/// `MenuBarItem.items(order:)` et la persistance dans les préférences.
@Suite struct MenuBarOrderTypeTests {
    private let all = MenuBarMeasure.allCases
    private func order(_ raw: String?) -> [MenuBarMeasure] { MenuBarOrder(parsing: raw).measures }

    // MARK: Défaut et correspondance des identifiants

    @Test func theDefaultIsTheOrderTheMenuBarAlwaysHad() {
        #expect(MenuBarOrder.default.measures == [.cpu, .gpu, .memory, .disk, .network, .battery])
        #expect(MenuBarOrder.default.serialized == "cpu,gpu,memory,disk,network,battery")
        #expect(MenuBarOrder.defaultSerialized == "cpu,gpu,memory,disk,network,battery")
        #expect(MenuBarOrder().measures == MenuBarOrder.default.measures)
    }

    @Test func everyMeasureHasAUniqueStableIdAndComesBackFromIt() {
        #expect(all.count == 6)
        #expect(Set(all.map(\.rawValue)).count == 6)
        #expect(all.map(\.rawValue) == ["cpu", "gpu", "memory", "disk", "network", "battery"])
        for measure in all { #expect(MenuBarMeasure(rawValue: measure.rawValue) == measure) }
    }

    @Test func theDefaultHoldsEveryMeasureExactlyOnce() {
        #expect(Set(MenuBarOrder.default.measures) == Set(all))
        #expect(MenuBarOrder.default.measures.count == all.count)
    }

    // MARK: Lecture tolérante

    @Test func aMissingEmptyOrCorruptValueGivesTheDefault() {
        for raw in [nil, "", " ", ",", ",,,", "garbage", "foo,bar", "{\"a\":1}", "🙂", "\n"] as [String?] {
            #expect(order(raw) == MenuBarOrder.default.measures, "\(String(describing: raw))")
        }
    }

    @Test func unknownIdsAreDropped() {
        #expect(order("network,foo,cpu,bar,gpu,memory,disk,battery") == [.network, .cpu, .gpu, .memory, .disk, .battery])
    }

    @Test func duplicatesAreDroppedKeepingTheFirst() {
        #expect(order("battery,cpu,battery,cpu,cpu,gpu,memory,disk,network") == [.battery, .cpu, .gpu, .memory, .disk, .network])
    }

    @Test func missingIdsAreAppendedInTheDefaultOrder() {
        #expect(order("battery") == [.battery, .cpu, .gpu, .memory, .disk, .network])
        #expect(order("network,gpu") == [.network, .gpu, .cpu, .memory, .disk, .battery])
        #expect(order("memory,cpu,disk,gpu") == [.memory, .cpu, .disk, .gpu, .network, .battery])
    }

    @Test func spacesAndCapitalsAreForgiven() {
        #expect(order(" Battery , CPU ,gpu,\tmemory,disk,NETWORK") == [.battery, .cpu, .gpu, .memory, .disk, .network])
    }

    @Test func theResultIsAlwaysAFullPermutation() {
        for raw in ["", "x", "cpu", "cpu,cpu", "battery,network,disk,memory,gpu,cpu,cpu,foo", "a,b,c,d,e,f,g", "gpu,,cpu"] {
            let measures = order(raw)
            #expect(measures.count == 6 && Set(measures).count == 6, "\(raw)")
        }
    }

    // MARK: Écriture

    @Test func serialisingThenParsingGivesTheSameOrderForEveryPermutation() {
        for permutation in permutations(of: all) {
            let written = MenuBarOrder(parsing: permutation.map(\.rawValue).joined(separator: ","))
            #expect(written.measures == permutation)
            #expect(MenuBarOrder(parsing: written.serialized).measures == permutation)
            #expect(written.serialized == permutation.map(\.rawValue).joined(separator: ","))
        }
    }

    // MARK: Déplacements

    @Test func moveFromToPutsTheItemAtTheTargetIndex() {
        var order = MenuBarOrder.default
        order.move(from: 0, to: 3)
        #expect(order.measures == [.gpu, .memory, .disk, .cpu, .network, .battery])
        order.move(from: 3, to: 0)
        #expect(order.measures == MenuBarOrder.default.measures)
        order.move(from: 5, to: 1)
        #expect(order.measures == [.cpu, .battery, .gpu, .memory, .disk, .network])
    }

    @Test func moveFromToIsBoundedAndIgnoresABadSource() {
        var order = MenuBarOrder.default
        order.move(from: 2, to: 99)
        #expect(order.measures == [.cpu, .gpu, .disk, .network, .battery, .memory], "au-delà de la fin : à la fin")
        order = .default
        order.move(from: 2, to: -4)
        #expect(order.measures == [.memory, .cpu, .gpu, .disk, .network, .battery], "avant le début : au début")
        order = .default
        order.move(from: -1, to: 2); order.move(from: 6, to: 2); order.move(from: 40, to: 0)
        #expect(order.measures == MenuBarOrder.default.measures, "source hors liste : rien")
        order.move(from: 3, to: 3)
        #expect(order.measures == MenuBarOrder.default.measures)
    }

    @Test func moveUpAndDownSwapWithTheNeighbourAndStopAtTheEnds() {
        var order = MenuBarOrder.default
        order.moveUp(.memory)
        #expect(order.measures == [.cpu, .memory, .gpu, .disk, .network, .battery])
        order.moveDown(.memory)
        #expect(order.measures == MenuBarOrder.default.measures)
        order.moveUp(.cpu)
        #expect(order.measures == MenuBarOrder.default.measures, "le premier ne monte pas")
        order.moveDown(.battery)
        #expect(order.measures == MenuBarOrder.default.measures, "le dernier ne descend pas")
        for _ in 0..<20 { order.moveDown(.cpu) }
        #expect(order.measures.last == .cpu && order.measures.count == 6)
        for _ in 0..<20 { order.moveUp(.cpu) }
        #expect(order.measures.first == .cpu && order.measures.count == 6)
    }

    @Test func canMoveUpAndDownTellTheEnds() {
        let order = MenuBarOrder.default
        #expect(!order.canMoveUp(.cpu) && order.canMoveDown(.cpu))
        #expect(order.canMoveUp(.battery) && !order.canMoveDown(.battery))
        #expect(order.canMoveUp(.disk) && order.canMoveDown(.disk))
    }

    @Test func hiddenMeasuresAreSkippedByAMoveSoItAlwaysShows() {
        // La batterie n'existe pas sur ce Mac : elle reste dans l'ordre, mais un déplacement la saute.
        var order = MenuBarOrder(parsing: "cpu,battery,gpu,memory,disk,network")
        let shown = Set(all).subtracting([.battery])
        order.moveUp(.gpu, among: shown)
        #expect(order.measures == [.gpu, .cpu, .battery, .memory, .disk, .network], "gpu passe devant cpu, pas devant la batterie cachée")
        order = MenuBarOrder(parsing: "cpu,battery,gpu,memory,disk,network")
        order.moveDown(.cpu, among: shown)
        #expect(order.measures == [.battery, .gpu, .cpu, .memory, .disk, .network], "cpu passe derrière gpu")
        #expect(!MenuBarOrder(parsing: "cpu,battery,gpu,memory,disk,network").canMoveUp(.gpu, among: Set([.gpu])), "seul visible : rien à faire")
        #expect(!MenuBarOrder.default.canMoveUp(.cpu, among: shown) && !MenuBarOrder.default.canMoveDown(.network, among: shown))
    }

    @Test func aMoveKeepsTheHiddenMeasuresAtTheirPlaceInTheList() {
        var order = MenuBarOrder.default
        order.moveUp(.network, among: Set(all).subtracting([.battery]))
        #expect(order.measures.contains(.battery) && order.measures.count == 6)
    }

    @Test func droppingOnARowPutsTheDraggedItemWhereThatRowWas() {
        var order = MenuBarOrder.default
        order.move(.cpu, onto: .disk)
        #expect(order.measures == [.gpu, .memory, .disk, .cpu, .network, .battery])
        order.move(.battery, onto: .gpu)
        #expect(order.measures == [.battery, .gpu, .memory, .disk, .cpu, .network])
        order.move(.gpu, onto: .gpu)
        #expect(order.measures == [.battery, .gpu, .memory, .disk, .cpu, .network], "sur soi-même : rien")
    }

    @Test func everyMoveKeepsAFullPermutation() {
        for start in permutations(of: all).prefix(120) {
            for measure in all {
                var order = MenuBarOrder(parsing: start.map(\.rawValue).joined(separator: ","))
                order.moveUp(measure); order.moveDown(measure); order.move(measure, onto: all.randomElement()!)
                #expect(order.measures.count == 6 && Set(order.measures) == Set(all))
            }
        }
    }

    // MARK: Lignes visibles et position

    @Test func theVisibleRowsLeaveOutTheBatteryWhenThereIsNone() {
        let order = MenuBarOrder(parsing: "battery,network,disk,memory,gpu,cpu")
        #expect(order.visible(hasBattery: true) == [.battery, .network, .disk, .memory, .gpu, .cpu])
        #expect(order.visible(hasBattery: false) == [.network, .disk, .memory, .gpu, .cpu])
        #expect(order.visible(hasBattery: false).count == 5)
    }

    @Test func thePositionTextIsOneBasedOutOfTheVisibleCount() {
        #expect(MenuBarOrder.positionText(index: 0, of: 6) == "1 of 6")
        #expect(MenuBarOrder.positionText(index: 1, of: 6) == "2 of 6")
        #expect(MenuBarOrder.positionText(index: 4, of: 5) == "5 of 5")
    }

    // MARK: Aides

    private func permutations(of items: [MenuBarMeasure]) -> [[MenuBarMeasure]] {
        guard items.count > 1 else { return [items] }
        return items.indices.flatMap { i -> [[MenuBarMeasure]] in
            var rest = items
            let head = rest.remove(at: i)
            return permutations(of: rest).map { [head] + $0 }
        }
    }
}

/// `MenuBarItem.items(order:)` : l'ordre voulu, le drapeau collé au réseau, ce qui est caché est sauté.
@Suite struct MenuBarItemsOrderTests {
    private let GB: UInt64 = 1_000_000_000

    private func snapshot(gpu: Bool = true, network: Bool = true, battery: Bool = true) -> SystemSnapshot {
        SystemSnapshot(
            date: Date(), cpu: CPUStats(user: 0.33, system: 0.10),
            memory: MemoryStats(total: 16 * GB, app: 8 * GB, wired: 3 * GB, compressed: 2 * GB, cached: GB, swapUsed: 0, pressure: .normal),
            disk: DiskStats(total: 1_000 * GB, available: 140 * GB),
            thermalState: .nominal, uptime: 100,
            gpu: gpu ? GPUStats(utilization: 0.22, memoryUsed: 1_000_000) : nil,
            battery: battery ? BatteryStats(percent: 67, isCharging: false, isPluggedIn: false, isFullyCharged: false, minutesRemaining: nil, cycleCount: 1,
                                            health: 1, designCapacity: nil, maxCapacity: nil, temperature: nil, batteryPower: nil, systemPower: nil, adapterWatts: nil) : nil,
            network: network ? NetworkStats(downRate: 13_000, upRate: 99_000, localIP: nil, wifi: nil, latencyMs: nil) : nil
        )
    }

    private func items(_ order: MenuBarOrder = .default, snapshot s: SystemSnapshot? = nil, shown: Set<MenuBarMeasure> = Set(MenuBarMeasure.allCases),
                       flag: String? = nil) -> [MenuBarItem] {
        MenuBarItem.items(for: s ?? snapshot(), cpu: shown.contains(.cpu), gpu: shown.contains(.gpu), memory: shown.contains(.memory), disk: shown.contains(.disk),
                          network: shown.contains(.network), battery: shown.contains(.battery), publicIPCountryCode: flag, order: order)
    }

    private func measures(_ list: [MenuBarItem]) -> [MenuBarMeasure] { list.compactMap(\.measure) }

    private func permutations(_ items: [MenuBarMeasure]) -> [[MenuBarMeasure]] {
        guard items.count > 1 else { return [items] }
        return items.indices.flatMap { i -> [[MenuBarMeasure]] in
            var rest = items
            let head = rest.remove(at: i)
            return permutations(rest).map { [head] + $0 }
        }
    }

    @Test func noOrderGivesTheOldFixedOrderSoTheOldCallersAreUnchanged() {
        let old = MenuBarItem.items(for: snapshot(), cpu: true, gpu: true, memory: true, disk: true, network: true, battery: true)
        #expect(measures(old) == [.cpu, .gpu, .memory, .disk, .network, .battery])
        #expect(old == items(.default))
    }

    @Test func everyPermutationOfSixIsRespected() {
        let all = permutations(MenuBarMeasure.allCases)
        #expect(all.count == 720)
        for permutation in all {
            let order = MenuBarOrder(parsing: permutation.map(\.rawValue).joined(separator: ","))
            #expect(measures(items(order)) == permutation, "\(permutation)")
        }
    }

    @Test func eachItemKeepsItsOwnContentWhateverTheOrder() {
        let reversed = MenuBarOrder(parsing: "battery,network,disk,memory,gpu,cpu")
        #expect(items(reversed) == items(.default).reversed())
    }

    @Test func hiddenMeasuresAreSkipped() {
        let order = MenuBarOrder(parsing: "battery,network,disk,memory,gpu,cpu")
        #expect(measures(items(order, shown: [.cpu, .memory, .battery])) == [.battery, .memory, .cpu])
        #expect(measures(items(order, shown: [])) == [])
        #expect(measures(items(order, shown: [.disk])) == [.disk])
    }

    @Test func unavailableMeasuresAreSkippedWhileTheOthersKeepTheirOrder() {
        let order = MenuBarOrder(parsing: "battery,network,gpu,memory,disk,cpu")
        let list = items(order, snapshot: snapshot(gpu: false, network: false, battery: false))
        #expect(measures(list) == [.memory, .disk, .cpu], "pas de GPU, pas de réseau mesuré, pas de batterie")
    }

    @Test func theFlagFollowsTheNetworkItemWhereverItIs() {
        for permutation in permutations(MenuBarMeasure.allCases) {
            let order = MenuBarOrder(parsing: permutation.map(\.rawValue).joined(separator: ","))
            let list = items(order, flag: "FR")
            guard let network = list.firstIndex(where: { if case .pair = $0 { true } else { false } }) else { Issue.record("pas de réseau"); return }
            #expect(list[network + 1] == .flag(countryCode: "FR"), "\(permutation)")
            #expect(list.filter(\.isFlag).count == 1)
            #expect(list.count == 7)
        }
    }

    @Test func noFlagWithoutTheNetworkItemOrWithoutACode() {
        let order = MenuBarOrder(parsing: "battery,network,disk,memory,gpu,cpu")
        #expect(!items(order, shown: [.cpu, .battery], flag: "FR").contains { $0.isFlag })
        #expect(!items(order, snapshot: snapshot(network: false), flag: "FR").contains { $0.isFlag })
        #expect(!items(order, flag: nil).contains { $0.isFlag })
        #expect(!items(order, flag: "XX").contains { $0.isFlag })
    }

    @Test func theFlagComesBeforeWhateverFollowsTheNetworkItem() {
        let order = MenuBarOrder(parsing: "network,battery,cpu,gpu,memory,disk")
        let list = items(order, shown: [.network, .battery, .cpu], flag: "FR")
        #expect(list.count == 4)
        #expect(list[0].measure == .network && list[1] == .flag(countryCode: "FR") && list[2].measure == .battery && list[3].measure == .cpu)
    }

    @Test func theItemMeasureMapping() {
        #expect(MenuBarItem.stacked(label: "CPU", value: "1%").measure == .cpu)
        #expect(MenuBarItem.stacked(label: "GPU", value: "1%").measure == .gpu)
        #expect(MenuBarItem.stacked(label: "RAM", value: "1%").measure == .memory)
        #expect(MenuBarItem.stacked(label: "SSD", value: "1%").measure == .disk)
        #expect(MenuBarItem.pair(top: "a", bottom: "b").measure == .network)
        #expect(MenuBarItem.battery(percent: 5, power: .onBattery).measure == .battery)
        #expect(MenuBarItem.flag(countryCode: "FR").measure == nil)
    }
}

/// L'image réelle du libellé : une autre liste (donc un autre ordre) donne une autre image, la même liste le même objet en cache.
@MainActor @Suite(.serialized) struct MenuBarOrderLabelTests {
    private let cpu = MenuBarItem.stacked(label: "CPU", value: "43%")
    private let ram = MenuBarItem.stacked(label: "RAM", value: "61%")

    @Test func anotherOrderMakesAnotherImageAndTheSameOrderTheCachedOne() throws {
        let first = try #require(MenuBarRenderer.image(severity: nil, compact: true, items: [cpu, ram], darkBar: false, increasedContrast: false))
        let same = try #require(MenuBarRenderer.image(severity: nil, compact: true, items: [cpu, ram], darkBar: false, increasedContrast: false))
        #expect(first === same, "même ordre : le cache sert la même image")
        let swapped = try #require(MenuBarRenderer.image(severity: nil, compact: true, items: [ram, cpu], darkBar: false, increasedContrast: false))
        #expect(swapped !== first, "l'ordre fait partie de la clé de cache")
    }
}

/// Les préférences : la clé, le défaut, les valeurs absentes ou abîmées, et le déplacement qui écrit le nouvel ordre.
@Suite struct MenuBarOrderPersistenceTests {
    private func defaults() -> UserDefaults {
        let name = "soaro.test.order.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func theKeyIsRegisteredWithTheDefaultOrder() {
        #expect(SettingsKey.menuBarOrder == "menuBarOrder")
        #expect(SettingsKey.defaults[SettingsKey.menuBarOrder] as? String == MenuBarOrder.defaultSerialized)
    }

    @Test func aMissingKeyGivesTheDefaultOrder() {
        #expect(MenuBarOrder.load(from: defaults()).measures == MenuBarOrder.default.measures)
    }

    @Test func aCorruptValueGivesTheDefaultOrder() {
        let d = defaults()
        d.set("nonsense;;;", forKey: SettingsKey.menuBarOrder)
        #expect(MenuBarOrder.load(from: d).measures == MenuBarOrder.default.measures)
        d.set(42, forKey: SettingsKey.menuBarOrder)
        #expect(MenuBarOrder.load(from: d).measures == MenuBarOrder.default.measures, "pas une chaîne")
        d.set(["cpu", "gpu"], forKey: SettingsKey.menuBarOrder)
        #expect(MenuBarOrder.load(from: d).measures == MenuBarOrder.default.measures, "pas une chaîne")
    }

    @Test func savedThenLoadedGivesTheSameOrder() {
        let d = defaults()
        var order = MenuBarOrder.default
        order.move(.battery, onto: .cpu)
        order.save(to: d)
        #expect(d.string(forKey: SettingsKey.menuBarOrder) == "battery,cpu,gpu,memory,disk,network")
        #expect(MenuBarOrder.load(from: d).measures == order.measures)
    }

    @Test func aMoveWrittenThroughTheSettingGivesTheNewOrder() {
        let d = defaults()
        d.set("cpu,gpu,memory,disk,network,battery", forKey: SettingsKey.menuBarOrder)
        let written = MenuBarOrder.edit(stored: d.string(forKey: SettingsKey.menuBarOrder)) { $0.moveUp(.disk) }
        d.set(written, forKey: SettingsKey.menuBarOrder)
        #expect(d.string(forKey: SettingsKey.menuBarOrder) == "cpu,gpu,disk,memory,network,battery")
        let again = MenuBarOrder.edit(stored: d.string(forKey: SettingsKey.menuBarOrder)) { $0.move(.cpu, onto: .network) }
        #expect(again == "gpu,disk,memory,network,cpu,battery")
    }

    @Test func editingACorruptValueStartsFromTheDefaultAndWritesAGoodOne() {
        let written = MenuBarOrder.edit(stored: "###") { $0.moveDown(.cpu) }
        #expect(written == "gpu,cpu,memory,disk,network,battery")
        #expect(MenuBarOrder.edit(stored: nil) { _ in } == MenuBarOrder.defaultSerialized)
    }

    @Test func theOldVisibilityKeysAreUntouched() {
        for key in [SettingsKey.menuBarCPU, SettingsKey.menuBarGPU, SettingsKey.menuBarMemory, SettingsKey.menuBarDisk, SettingsKey.menuBarBattery, SettingsKey.menuBarNetwork, SettingsKey.menuBarCompact] {
            #expect(SettingsKey.defaults[key] is Bool, "\(key)")
        }
        #expect(SettingsKey.defaults[SettingsKey.menuBarCPU] as? Bool == true)
        #expect(SettingsKey.defaults[SettingsKey.menuBarNetwork] as? Bool == false)
    }
}

/// Le libellé réel lit l'ordre enregistré, comme il lit les interrupteurs (un `@AppStorage` relance l'affichage quand la valeur change).
@Suite struct MenuBarOrderLabelWiringTests {
    private func read(_ path: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
    }

    @Test func theRealLabelReadsTheSavedOrderThroughAnAppStorage() throws {
        let app = try read("Sources/Soaro/SoaroApp.swift")
        #expect(app.contains("@AppStorage(SettingsKey.menuBarOrder)"), "relance le libellé quand l'ordre change")
        #expect(app.contains("MenuBarOrder(parsing:"), "lecture tolérante")
        #expect(app.contains("order:"), "transmis à MenuBarItem.items")
    }

    @Test func theSnapshotCommandStaysOnTheDefaultOrder() throws {
        let snapshot = try read("Sources/Soaro/Snapshot.swift")
        #expect(!snapshot.contains("menuBarOrder"), "les captures de documentation ne lisent pas les préférences")
    }
}
