import Foundation
import Testing
@testable import Soaro

/// `measure` écrit à la main : note chaque dossier demandé, rend les tailles prévues, et peut s'arrêter à chaque appel
/// pour que le test observe l'état entre deux mesures (deux sémaphores, aucun délai).
final class ScriptedMeasure: @unchecked Sendable {
    private let lock = NSLock()
    private var sizes: [String: UInt64]
    private var recorded: [String] = []
    private let gated: Bool
    let started = AsyncSignal()
    let release = DispatchSemaphore(value: 0)

    init(_ sizes: [String: UInt64], gated: Bool = false) { self.sizes = sizes; self.gated = gated }

    /// Dossiers demandés, dans l'ordre (le dernier composant du chemin).
    var calls: [String] { lock.lock(); defer { lock.unlock() }; return recorded }
    var paths: [String] = []

    func measure(_ folder: URL) -> UInt64 {
        lock.lock()
        recorded.append(folder.lastPathComponent)
        paths.append(folder.path)
        let size = sizes[folder.lastPathComponent] ?? 0
        lock.unlock()
        if gated { started.signal(); release.wait() }
        return size
    }
}

/// Tailles progressives (T6) : les lignes apparaissent tout de suite, chaque taille arrive une à une.
@MainActor
@Suite(.serialized) struct SimulatorsProgressiveSizesTests {
    static let u1 = "00000000-0000-4000-8000-000000000001"
    static let u2 = "00000000-0000-4000-8000-000000000002"
    static let u3 = "00000000-0000-4000-8000-000000000003"
    let now = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!
    let present = SimulatorToolDetection(devicesFolderExists: true, simctlPath: "/fake/simctl")
    let home = URL(fileURLWithPath: "/home-fake/user-x")

    /// Trois appareils : « Charlie » (u1), « Alpha » (u2), « Bravo » (u3) : l'ordre du listage (nom) est Alpha, Bravo, Charlie.
    static let json = """
    {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
      {"udid": "\(u1)", "name": "Charlie", "state": "Shutdown"},
      {"udid": "\(u2)", "name": "Alpha", "state": "Shutdown"},
      {"udid": "\(u3)", "name": "Bravo", "state": "Shutdown"}]}}
    """

    func runner() -> FakeCommandRunner {
        let fake = FakeCommandRunner()
        fake.script(.finished(stdout: Self.json), executable: "/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "-j"])
        return fake
    }

    func model(_ runner: CommandRunner, _ measure: ScriptedMeasure) -> SimulatorsModel {
        SimulatorsModel(runner: runner, detect: { self.present }, locateXcrun: { _ in "/usr/bin/xcrun" }, home: home,
                        now: { self.now }, measure: { measure.measure($0) }, demo: false, confirm: { _, _, _, _ in false }, notify: { _ in })
    }

    func waitUntilMeasuring(_ measure: ScriptedMeasure) async {
        await measure.started.wait()
    }

    func udids(_ m: SimulatorsModel) -> [String] { m.rows.map(\.device.device.udid) }

    // MARK: Lignes avant les tailles

    @Test func rowsExistBeforeAnySizeInListingOrder() async {
        let measure = ScriptedMeasure([:], gated: true)
        let m = model(runner(), measure)
        m.scan()
        await waitUntilMeasuring(measure)   // la liste est appliquée, la première mesure est en cours
        #expect(m.phase == .listed)
        #expect(m.isMeasuring)
        #expect(udids(m) == [Self.u2, Self.u3, Self.u1], "ordre du listage : nom (Alpha, Bravo, Charlie)")
        #expect(m.rows.allSatisfy { m.size(of: $0) == nil }, "aucune taille connue")
        #expect(m.measuredSizeTotal == 0)
        for _ in 0..<3 { measure.release.signal() }
        await m.scanTask?.value
    }

    @Test func sizesFillOneByOneAndTheOrderStaysUntilTheEnd() async {
        let measure = ScriptedMeasure([Self.u2: 200_000_000, Self.u3: 900_000_000, Self.u1: 500_000_000], gated: true)
        let m = model(runner(), measure)
        m.scan()
        await waitUntilMeasuring(measure)                 // mesure de Alpha (u2) en cours
        #expect(measure.calls == [Self.u2])
        measure.release.signal()
        await waitUntilMeasuring(measure)                 // Alpha appliqué, Bravo (u3) en cours
        #expect(m.size(of: m.rows[0]) == 200_000_000)
        #expect(m.size(of: m.rows[1]) == nil)
        #expect(udids(m) == [Self.u2, Self.u3, Self.u1], "pas de tri tant que ça mesure")
        measure.release.signal()
        await waitUntilMeasuring(measure)                 // Charlie (u1) en cours
        #expect(m.size(of: m.rows[1]) == 900_000_000)
        #expect(m.isMeasuring)
        measure.release.signal()
        await m.scanTask?.value
        #expect(!m.isMeasuring)
        #expect(measure.calls == [Self.u2, Self.u3, Self.u1], "une mesure à la fois, dans l'ordre")
        #expect(udids(m) == [Self.u3, Self.u1, Self.u2], "tri par taille décroissante à la fin")
        #expect(m.measuredSizeTotal == 1_600_000_000)
    }

    @Test func aSmallDeviceLeavesTheListAtOnceAndJoinsTheFooter() async {
        let measure = ScriptedMeasure([Self.u2: 50_000_000, Self.u3: 900_000_000, Self.u1: 500_000_000], gated: true)
        let m = model(runner(), measure)
        m.scan()
        await waitUntilMeasuring(measure)                 // Alpha (u2, 50 Mo) en cours
        #expect(m.rows.count == 3)
        #expect(m.hiddenSmallCount == 0)
        measure.release.signal()
        await waitUntilMeasuring(measure)                 // Alpha appliqué : petit, il disparaît
        #expect(udids(m) == [Self.u3, Self.u1])
        #expect(m.hiddenSmallCount == 1)
        #expect(m.hiddenSmallSize == 50_000_000)
        measure.release.signal()
        await waitUntilMeasuring(measure)
        measure.release.signal()
        await m.scanTask?.value
        #expect(m.hiddenSmallCount == 1)
    }

    @Test func theThresholdIsStrict() async {
        let measure = ScriptedMeasure([Self.u2: 99_999_999, Self.u3: 100_000_000, Self.u1: 100_000_001])
        let m = model(runner(), measure)
        m.scan()
        await m.scanTask?.value
        #expect(Set(udids(m)) == [Self.u3, Self.u1])
        #expect(m.hiddenSmallCount == 1)
    }

    // MARK: Fin

    @Test func finalListAndFooterEqualSuggestOnTheFinalSizes() async {
        let sizes: [String: UInt64] = [Self.u2: 30_000_000, Self.u3: 900_000_000, Self.u1: 500_000_000]
        let measure = ScriptedMeasure(sizes)
        let m = model(runner(), measure)
        m.scan()
        await m.scanTask?.value
        let listing = SimulatorScanner.list(runner: runner(), xcrunPath: "/usr/bin/xcrun")
        let expected = DeviceSuggestions.suggest(listing.devices.map { SizedSimulator(device: $0, size: sizes[$0.udid] ?? 0) },
                                                 now: now, limitDays: DeviceSuggestions.defaultLimitDays)
        #expect(m.rows == expected.rows)
        #expect(m.hiddenSmallCount == expected.hiddenSmallCount)
        #expect(m.hiddenSmallSize == expected.hiddenSmallSize)
        #expect(m.measuredSizeTotal == 1_400_000_000)
        #expect(!m.isMeasuring)
    }

    @Test func sizesAreMeasuredOnlyUnderTheDevicesFolderOfTheHome() async {
        let measure = ScriptedMeasure([:])
        let m = model(runner(), measure)
        m.scan()
        await m.scanTask?.value
        let root = "/home-fake/user-x/Library/Developer/CoreSimulator/Devices/"
        #expect(Set(measure.paths) == [root + Self.u1, root + Self.u2, root + Self.u3])
    }

    // MARK: Annulation

    @Test func cancelAfterOneMeasurementStopsEverything() async {
        let measure = ScriptedMeasure([Self.u2: 200_000_000, Self.u3: 900_000_000, Self.u1: 500_000_000], gated: true)
        let m = model(runner(), measure)
        m.scan()
        await waitUntilMeasuring(measure)                 // première mesure en cours
        m.cancel()                                        // Retour
        measure.release.signal()
        await m.scanTask?.value
        #expect(measure.calls == [Self.u2], "plus aucune mesure après l'annulation")
        #expect(m.phase == .notScanned)
        #expect(m.rows.isEmpty)
        #expect(!m.isMeasuring)
        // On observe l'écriture tardive elle-même : la taille que le modèle garde pour l'appareil (sans le contrôle
        // d'annulation après la mesure, elle serait écrite alors que la mesure s'est terminée après le Retour).
        #expect(m.measuredSize(udid: Self.u2) == nil, "la taille arrivée après l'annulation n'est pas appliquée")
        #expect(m.measuredSizes.isEmpty)
    }

    @Test func cancelAfterTwoMeasurementsAppliesNoLaterSize() async {
        let measure = ScriptedMeasure([Self.u2: 200_000_000, Self.u3: 900_000_000, Self.u1: 500_000_000], gated: true)
        let m = model(runner(), measure)
        m.scan()
        await waitUntilMeasuring(measure)
        measure.release.signal()
        await waitUntilMeasuring(measure)                 // deuxième mesure en cours
        m.cancel()
        measure.release.signal()
        await m.scanTask?.value
        #expect(measure.calls.count == 2)
        #expect(m.measuredSize(udid: Self.u3) == nil, "la deuxième taille, arrivée après l'annulation, n'est pas appliquée")
        #expect(m.measuredSizes.isEmpty)
    }

    @Test func scanAgainStopsTheMeasuringOfTheFirstScan() async {
        let measure = ScriptedMeasure([Self.u2: 200_000_000, Self.u3: 900_000_000, Self.u1: 500_000_000], gated: true)
        let m = model(runner(), measure)
        m.scan()
        await waitUntilMeasuring(measure)
        let first = m.scanTask
        m.scan()                                           // « Scan again »
        // Quatre mesures au total (une pour le premier scan annulé, trois pour le second) : on les libère toutes, sans
        // supposer laquelle reçoit quel signal. Le premier scan se termine sans appliquer sa taille.
        measure.release.signal()
        for _ in 0..<3 { await waitUntilMeasuring(measure); measure.release.signal() }
        await first?.value
        await m.scanTask?.value
        #expect(m.phase == .listed)
        #expect(measure.calls.count == 4, "une mesure pour le premier scan annulé, trois pour le second")
        #expect(m.measuredSizeTotal == 1_600_000_000)
    }
}
