import Foundation
import Testing
@testable import Soaro

@Suite struct DeviceSuggestionsTests {
    private let now = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!
    private let big: UInt64 = 500_000_000
    private let iosA = "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
    private let iosB = "com.apple.CoreSimulator.SimRuntime.iOS-18-0"
    private let phone = "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
    private let pad = "com.apple.CoreSimulator.SimDeviceType.iPad-Air"

    private func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    private func dev(_ n: Int, days: Double? = nil, size: UInt64? = nil, model: String? = nil, runtime: String? = nil,
                     state: String = "Shutdown", name: String = "Device", available: Bool = true) -> SizedSimulator {
        let udid = String(format: "00000000-0000-4000-8000-%012d", n)
        let runtimeID = runtime ?? iosA
        return SizedSimulator(
            device: SimulatorDevice(udid: udid, name: name, modelIdentifier: model ?? "model-\(n)", runtimeIdentifier: runtimeID,
                                    runtimeName: SimulatorScanner.runtimeName(runtimeID), state: state, isAvailable: available,
                                    lastUsed: days.map(ago)),
            size: size ?? big)
    }

    private func selected(_ r: DeviceSuggestions.Result) -> Set<Int> {
        Set(r.rows.filter(\.isPreSelected).map { Int($0.device.device.udid.suffix(12))! })
    }
    private func row(_ n: Int, _ r: DeviceSuggestions.Result) -> DeviceSuggestions.Row? {
        r.rows.first { Int($0.device.device.udid.suffix(12)) == n }
    }

    // MARK: Inactivité

    @Test(arguments: [(59.0, false), (60.0, false), (60.99, false), (61.0, true), (400.0, true)])
    func inactiveStrictlyBeyondTheLimitOf60Days(days: Double, expected: Bool) {
        let r = DeviceSuggestions.suggest([dev(1, days: days)], now: now, limitDays: 60)
        #expect(r.rows.first?.isPreSelected == expected)
        #expect(r.rows.first?.isInactive == expected)
    }

    @Test func daysSinceLastUseAreWholeDaysAndNeverNegative() {
        let r = DeviceSuggestions.suggest([dev(1, days: 60.99), dev(2, days: -5), dev(3, days: 0), dev(4)], now: now, limitDays: 60)
        #expect(row(1, r)?.daysSinceLastUse == 60)
        #expect(row(2, r)?.daysSinceLastUse == 0, "une date future vaut 0")
        #expect(row(3, r)?.daysSinceLastUse == 0)
        #expect(row(4, r)?.daysSinceLastUse == nil)
    }

    @Test(arguments: [(30, Set([2, 3, 4, 5])), (90, Set([4, 5])), (180, Set([5]))])
    func theLimitIsAParameter(limit: Int, expected: Set<Int>) {
        let devices = [dev(1, days: 10), dev(2, days: 45), dev(3, days: 90), dev(4, days: 100), dev(5, days: 200)]
        // jours : 10, 45, 90, 100, 200
        let r = DeviceSuggestions.suggest(devices, now: now, limitDays: limit)
        #expect(selected(r) == expected)
    }

    // MARK: Anciennes copies

    @Test func aTrioOfDuplicatesKeepsTheNewestAndSelectsTwoOlderCopiesEvenIfRecent() {
        let m = phone
        let r = DeviceSuggestions.suggest([dev(1, days: 5, model: m), dev(2, days: 3, model: m), dev(3, days: 1, model: m)], now: now, limitDays: 60)
        #expect(selected(r) == [1, 2])
        #expect(row(3, r)?.isPreSelected == false)
        #expect(row(1, r)?.isOlderCopy == true)
        #expect(row(1, r)?.isInactive == false)
        #expect(r.preSelectedCount == 2)
    }

    @Test func aCopyBothInactiveAndOlderCarriesBothReasons() {
        let r = DeviceSuggestions.suggest([dev(1, days: 100, model: phone), dev(2, days: 2, model: phone)], now: now, limitDays: 60)
        #expect(row(1, r)?.isInactive == true)
        #expect(row(1, r)?.isOlderCopy == true)
        #expect(row(1, r)?.isPreSelected == true)
        #expect(row(2, r)?.isPreSelected == false)
    }

    @Test func sameModelOtherRuntimeAndSameRuntimeOtherModelAreNotDuplicates() {
        let r = DeviceSuggestions.suggest([
            dev(1, days: 5, model: phone, runtime: iosA), dev(2, days: 1, model: phone, runtime: iosB),
            dev(3, days: 5, model: pad, runtime: iosA),
        ], now: now, limitDays: 60)
        #expect(selected(r).isEmpty)
        #expect(r.rows.allSatisfy { !$0.isOlderCopy })
    }

    @Test func theModelFallsBackToTheNameWhenTheTypeIdentifierIsMissing() {
        func noModel(_ n: Int, days: Double, name: String) -> SizedSimulator {
            let base = dev(n, days: days, name: name)
            return SizedSimulator(device: SimulatorDevice(udid: base.device.udid, name: name, modelIdentifier: nil,
                                                          runtimeIdentifier: iosA, runtimeName: "iOS 26.2", state: "Shutdown",
                                                          isAvailable: true, lastUsed: base.device.lastUsed), size: big)
        }
        let same = DeviceSuggestions.suggest([noModel(1, days: 5, name: "Phone X"), noModel(2, days: 1, name: "Phone X")], now: now, limitDays: 60)
        #expect(selected(same) == [1])
        let different = DeviceSuggestions.suggest([noModel(1, days: 5, name: "Phone X"), noModel(2, days: 1, name: "Phone Y")], now: now, limitDays: 60)
        #expect(selected(different).isEmpty)
    }

    @Test func aDatedSmallHiddenNewerCopyMakesTheBigOneAnOlderCopy() {
        let r = DeviceSuggestions.suggest([dev(1, days: 5, size: big, model: phone), dev(2, days: 1, size: 1_000, model: phone)], now: now, limitDays: 60)
        #expect(r.rows.map { Int($0.device.device.udid.suffix(12))! } == [1], "le petit n'est pas listé")
        #expect(selected(r) == [1])
        #expect(r.hiddenSmallCount == 1)
    }

    @Test func newestTiesAreBrokenBySizeThenUDID() {
        let sameDay = [dev(1, days: 5, size: 600_000_000, model: phone), dev(2, days: 5, size: 700_000_000, model: phone)]
        #expect(selected(DeviceSuggestions.suggest(sameDay, now: now, limitDays: 60)) == [1], "le plus gros est gardé")
        let sameSize = [dev(1, days: 5, model: phone), dev(2, days: 5, model: phone)]
        #expect(selected(DeviceSuggestions.suggest(sameSize, now: now, limitDays: 60)) == [2], "à égalité, l'UDID le plus petit est gardé")
        #expect(selected(DeviceSuggestions.suggest(sameSize.reversed(), now: now, limitDays: 60)) == [2], "indépendant de l'ordre d'entrée")
    }

    // MARK: Sans date

    @Test func noDateIsNeverPreSelectedAndIsListedAsUnknown() {
        let r = DeviceSuggestions.suggest([dev(1, model: phone)], now: now, limitDays: 0)
        #expect(r.rows.count == 1)
        #expect(r.rows[0].daysSinceLastUse == nil)
        #expect(!r.rows[0].isPreSelected)
    }

    @Test func noDateInAGroupIsNeitherKeeperNorOlderCopy() {
        let r = DeviceSuggestions.suggest([dev(1, model: phone), dev(2, days: 100, model: phone)], now: now, limitDays: 60)
        #expect(row(1, r)?.isOlderCopy == false)
        #expect(row(1, r)?.isPreSelected == false)
        #expect(row(2, r)?.isOlderCopy == false, "seul daté du groupe : c'est lui le gardé")
        #expect(selected(r) == [2], "mais il est inactif au-delà de la limite")
    }

    // MARK: En cours d'exécution

    @Test func aRunningDeviceIsNeverPreSelectedAndIsFlagged() {
        for state in ["Booted", "Booting", "Shutting Down", "Unknown", "Whatever"] {
            let r = DeviceSuggestions.suggest([dev(1, days: 500, state: state)], now: now, limitDays: 60)
            #expect(r.rows.first?.isRunning == true, "\(state)")
            #expect(r.rows.first?.isPreSelected == false, "\(state)")
        }
        let stopped = DeviceSuggestions.suggest([dev(1, days: 500, state: "Shutdown")], now: now, limitDays: 60)
        #expect(stopped.rows.first?.isRunning == false)
    }

    @Test func aRunningOldDuplicatedDeviceIsKeeperAndTheOthersBecomeOlderCopies() {
        let r = DeviceSuggestions.suggest([dev(1, days: 300, model: phone, state: "Booted"), dev(2, days: 2, model: phone)], now: now, limitDays: 60)
        #expect(row(1, r)?.isPreSelected == false)
        #expect(row(1, r)?.isOlderCopy == false)
        #expect(selected(r) == [2], "le démarré compte comme utilisé maintenant : la copie récente est l'ancienne")
    }

    // MARK: Petits appareils

    @Test func smallDevicesAreCountedNotListedAndNeverPreSelected() {
        let r = DeviceSuggestions.suggest([
            dev(1, days: 500, size: 99_999_999), dev(2, days: 500, size: 100_000_000), dev(3, days: 500, size: 1),
        ], now: now, limitDays: 60)
        #expect(r.rows.map { Int($0.device.device.udid.suffix(12))! } == [2], "100 000 000 est listé, 99 999 999 ne l'est pas")
        #expect(r.hiddenSmallCount == 2)
        #expect(r.hiddenSmallSize == 100_000_000)
        #expect(selected(r) == [2])
        #expect(r.preSelectedCount == 1)
        #expect(r.preSelectedSize == 100_000_000)
    }

    @Test func preSelectedTotalsAddUpTheListedSelectedDevices() {
        let r = DeviceSuggestions.suggest([dev(1, days: 100, size: 300_000_000), dev(2, days: 200, size: 200_000_000), dev(3, days: 1, size: 900_000_000)], now: now, limitDays: 60)
        #expect(r.preSelectedCount == 2)
        #expect(r.preSelectedSize == 500_000_000)
        #expect(r.limitDays == 60)
    }

    // MARK: Tri et invariants

    @Test func emptyListGivesAnEmptyResult() {
        let r = DeviceSuggestions.suggest([], now: now, limitDays: 60)
        #expect(r.rows.isEmpty)
        #expect(r.hiddenSmallCount == 0 && r.hiddenSmallSize == 0 && r.preSelectedCount == 0 && r.preSelectedSize == 0)
    }

    @Test func sortedBySizeDescThenNameThenUDID() {
        let r = DeviceSuggestions.suggest([
            dev(1, size: 200_000_000, name: "B"), dev(2, size: 900_000_000, name: "Z"), dev(3, size: 200_000_000, name: "A"),
            dev(5, size: 200_000_000, name: "A"), dev(4, size: 200_000_000, name: "A"),
        ], now: now, limitDays: 60)
        #expect(r.rows.map { Int($0.device.device.udid.suffix(12))! } == [2, 3, 4, 5, 1])
    }

    @Test func sortingIsDeterministicWhateverTheInputOrder() {
        let devices = (1...8).map { dev($0, days: Double($0 * 20), size: UInt64(200_000_000 + ($0 % 3) * 100_000_000), model: $0 % 2 == 0 ? phone : pad) }
        let a = DeviceSuggestions.suggest(devices, now: now, limitDays: 60)
        let b = DeviceSuggestions.suggest(devices.reversed(), now: now, limitDays: 60)
        #expect(a == b)
    }

    @Test func preSelectedIsAlwaysASubsetOfListedAndNeverRunningOrUndatedOrSmall() {
        var devices: [SizedSimulator] = []
        for n in 1...30 {
            devices.append(dev(n, days: n % 4 == 0 ? nil : Double(n * 9), size: n % 5 == 0 ? 10_000 : big,
                               model: n % 3 == 0 ? phone : pad, runtime: n % 2 == 0 ? iosA : iosB,
                               state: n % 7 == 0 ? "Booted" : "Shutdown"))
        }
        for limit in [0, 30, 60, 120] {
            let r = DeviceSuggestions.suggest(devices, now: now, limitDays: limit)
            #expect(r.rows.filter(\.isPreSelected).allSatisfy { r.rows.contains($0) })
            #expect(r.rows.allSatisfy { !$0.isPreSelected || (!$0.isRunning && $0.daysSinceLastUse != nil && $0.device.size >= 100_000_000) })
            #expect(r.rows.count + r.hiddenSmallCount == devices.count)
        }
    }

    @Test func availabilityIsReportedButNotUsedToClassify() {
        let r = DeviceSuggestions.suggest([dev(1, days: 100, available: false), dev(2, days: 5, available: false)], now: now, limitDays: 60)
        #expect(row(1, r)?.device.device.isAvailable == false)
        #expect(selected(r) == [1])
    }

    @Test func theDefaultLimitIsOneNamedConstantOf60Days() {
        #expect(DeviceSuggestions.defaultLimitDays == 60)
        #expect(DeviceSuggestions.smallDeviceThreshold == 100_000_000)
    }

    // MARK: Appareil gardé d'une « ancienne copie »

    private func keptUDIDSuffix(_ n: Int, _ r: DeviceSuggestions.Result) -> Int? {
        row(n, r)?.keptDevice.map { Int($0.device.udid.suffix(12))! }
    }

    @Test func twoCopiesTheOlderNamesTheNewer() {
        let r = DeviceSuggestions.suggest([dev(1, days: 10, model: phone, name: "Newer"), dev(2, days: 30, model: phone, name: "Older")],
                                          now: now, limitDays: 60)
        #expect(row(2, r)?.isOlderCopy == true)
        #expect(keptUDIDSuffix(2, r) == 1)
        #expect(row(2, r)?.keptDevice?.device.name == "Newer")
        #expect(row(1, r)?.keptDevice == nil)
    }

    @Test func threeCopiesBothOlderNameTheNewest() {
        let r = DeviceSuggestions.suggest([dev(1, days: 50, model: phone), dev(2, days: 5, model: phone), dev(3, days: 20, model: phone)],
                                          now: now, limitDays: 60)
        #expect(keptUDIDSuffix(1, r) == 2)
        #expect(keptUDIDSuffix(3, r) == 2)
        #expect(keptUDIDSuffix(2, r) == nil)
    }

    @Test func aSmallKeptDeviceIsStillNamedThoughNotListed() {
        let r = DeviceSuggestions.suggest([dev(1, days: 1, size: 1_000, model: phone, name: "Tiny Newest"),
                                           dev(2, days: 40, model: phone)], now: now, limitDays: 60)
        #expect(row(1, r) == nil, "le petit appareil n'est pas listé")
        #expect(row(2, r)?.keptDevice?.device.name == "Tiny Newest")
        #expect(row(2, r)?.keptDevice?.size == 1_000)
    }

    @Test func aRunningKeptDeviceIsNamedToo() {
        let r = DeviceSuggestions.suggest([dev(1, days: 90, model: phone, state: "Booted", name: "Live"),
                                           dev(2, days: 3, model: phone)], now: now, limitDays: 60)
        #expect(row(2, r)?.isOlderCopy == true)
        #expect(row(2, r)?.keptDevice?.device.name == "Live")
        #expect(row(2, r)?.keptDevice?.device.state == "Booted")
    }

    @Test func aRowThatIsNotAnOlderCopyHasNoKeptDevice() {
        let r = DeviceSuggestions.suggest([dev(1, days: 100), dev(2, days: 5), dev(3)], now: now, limitDays: 60)
        #expect(r.rows.allSatisfy { $0.keptDevice == nil })
    }

    @Test func wholeDaysIsSharedAndNeverNegative() {
        #expect(DeviceSuggestions.wholeDays(from: ago(60.99), to: now) == 60)
        #expect(DeviceSuggestions.wholeDays(from: ago(0), to: now) == 0)
        #expect(DeviceSuggestions.wholeDays(from: ago(-5), to: now) == 0)
    }
}
