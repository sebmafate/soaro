import Foundation
import Testing
@testable import Soaro

/// Tailles scriptées PAR APPAREIL et par appel (la dernière se répète) : scan, mesure avant, mesure après, nouveau scan.
/// Note aussi si un appel a eu lieu sur le fil principal (le lot ne doit jamais y tourner).
final class PerDeviceSizes: @unchecked Sendable {
    private let lock = NSLock()
    private let sizes: [String: [UInt64]]
    private var indexes: [String: Int] = [:]
    private var recorded: [String] = []
    private var main = 0

    init(_ sizes: [String: [UInt64]]) { self.sizes = sizes }

    var calls: [String] { lock.lock(); defer { lock.unlock() }; return recorded }
    var callsOnTheMainThread: Int { lock.lock(); defer { lock.unlock() }; return main }

    func measure(_ folder: URL) -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        let udid = folder.lastPathComponent
        let index = indexes[udid, default: 0]
        indexes[udid] = index + 1
        recorded.append(udid)
        if Thread.isMainThread { main += 1 }
        guard let list = sizes[udid], !list.isEmpty else { return 0 }
        return list[min(index, list.count - 1)]
    }
}

/// Confirmation enregistrée : répond toujours la même chose et note chaque demande.
@MainActor
final class RecordingConfirm {
    struct Ask: Equatable {
        let title: String
        let message: String
        let button: String
        let critical: Bool
    }

    var answer: Bool
    private(set) var asks: [Ask] = []
    init(answer: Bool) { self.answer = answer }

    var handler: ConfirmHandler {
        { [unowned self] title, message, button, critical in
            self.asks.append(Ask(title: title, message: message, button: button, critical: critical))
            return self.answer
        }
    }
}

/// Suppression par le modèle (SL9 T5) : confirmation, lot hors de l'acteur principal, bilan, nouveau scan.
@MainActor
@Suite(.serialized) struct SimulatorsDeletionTests {
    static func udid(_ n: Int) -> String { String(format: "00000000-0000-4000-8000-%012d", n) }
    static let a = udid(1), b = udid(2), c = udid(3)
    static let xcrun = "/usr/bin/xcrun"
    static let listArgs = ["simctl", "list", "devices", "-j"]
    let present = SimulatorToolDetection(devicesFolderExists: true, simctlPath: "/fake/simctl")
    static let confirmMessageTail = "will be freed. The devices, the apps and data on them, and their snapshots will be deleted. "
        + "You can create new devices from Xcode or Android Studio."

    let box: Sandbox
    /// Une porte PAR TEST (jamais la porte partagée du processus) : les suites tournent en parallèle.
    let gate = SimulatorDeletionGate()
    let runner = FakeCommandRunner()
    let confirm: RecordingConfirm
    var toasts = ToastBox()

    final class ToastBox { var messages: [String] = [] }

    init() throws {
        box = try Sandbox(insideHome: true)
        confirm = RecordingConfirm(answer: true)
    }

    static func device(_ n: Int, name: String? = nil, state: String = "Shutdown") -> (udid: String, name: String, state: String?) {
        (udid(n), name ?? "iPhone \(n)", state)
    }

    static func list(_ devices: [(udid: String, name: String, state: String?)]) -> CommandOutcome {
        .finished(stdout: SimulatorRemovalOneDeviceTests.listJSON(devices))
    }

    func scriptList(_ outcomes: [CommandOutcome]) {
        runner.script(sequence: outcomes, executable: Self.xcrun, arguments: Self.listArgs)
    }

    func scriptDelete(_ udid: String, _ outcome: CommandOutcome = .finished()) {
        runner.script(outcome, executable: Self.xcrun, arguments: ["simctl", "delete", udid])
    }

    func model(_ runner: CommandRunner? = nil, sizes: PerDeviceSizes, detect: (() -> Void)? = nil,
               locate: @escaping ([String]) -> String? = { _ in "/usr/bin/xcrun" }) -> SimulatorsModel {
        let toasts = toasts
        let detection = present
        return SimulatorsModel(runner: runner ?? self.runner,
                               detect: { detect?(); return detection },
                               locateXcrun: locate,
                               home: box.root,
                               now: { Date() },
                               measure: { sizes.measure($0) },
                               demo: false,
                               confirm: confirm.handler,
                               deletionGate: gate,
                               notify: { toasts.messages.append($0) })
    }

    /// Scan, puis coche exactement ces appareils (les autres sont décochés).
    func scanAndSelect(_ m: SimulatorsModel, _ udids: [String]) async {
        m.scan()
        await m.scanTask?.value
        for row in m.rows {
            let id = row.device.device.udid
            if m.selected.contains(id) != udids.contains(id) { m.toggle(row) }
        }
    }

    func displayOrder(_ m: SimulatorsModel) -> [String] { m.rows.map(\.device.device.udid) }
    func deleteCalls() -> [FakeCommandRunner.Call] { runner.calls.filter { $0.arguments.contains("delete") } }
    func freed(_ value: UInt64) -> String { "\(Format.fileBytes(value)) freed" }

    static let half: UInt64 = 500_000_000

    // MARK: Règle « Delete disponible » (fonction pure)

    @Test(arguments: [
        (SimulatorsModel.Phase.listed, false, 1, false, true),
        (.listed, true, 1, false, false),      // tailles en cours de mesure
        (.listed, false, 0, false, false),     // rien de coché
        (.listed, false, 1, true, false),      // une suppression est en cours
        (.listing, false, 1, false, false),
        (.notScanned, false, 1, false, false),
        (.empty, false, 1, false, false),
        (.failed(.couldNotRead), false, 1, false, false),
    ])
    func theDeleteRuleIsAPureFunction(phase: SimulatorsModel.Phase, measuring: Bool, selected: Int, deleting: Bool, expected: Bool) {
        #expect(SimulatorsModel.canDelete(phase: phase, isMeasuring: measuring, selectedCount: selected, isDeleting: deleting) == expected)
    }

    // MARK: Confirmation (R8)

    @Test func theConfirmationNamesTheCountTheSizeAndTheLoss() async throws {
        scriptList([Self.list([Self.device(1), Self.device(2), Self.device(3)])])
        confirm.answer = false
        let sizes = PerDeviceSizes([Self.a: [Self.half], Self.b: [400_000_000], Self.c: [300_000_000]])
        let m = model(sizes: sizes)
        await scanAndSelect(m, [Self.a, Self.b])

        m.deleteSelected()

        let ask = try #require(confirm.asks.first)
        #expect(confirm.asks.count == 1)
        #expect(ask.title == "Delete the selected devices? (2)")
        #expect(ask.message == "\(Format.fileBytes(900_000_000)) \(Self.confirmMessageTail)")
        #expect(ask.button == "Delete")
        #expect(ask.critical)
    }

    @Test func cancellingTheConfirmationCallsNothingAndKeepsTheSelectionAndTheToast() async {
        scriptList([Self.list([Self.device(1), Self.device(2)])])
        confirm.answer = false
        let m = model(sizes: PerDeviceSizes([Self.a: [Self.half], Self.b: [Self.half]]))
        await scanAndSelect(m, [Self.a])
        let before = runner.calls.count, selection = m.selected

        m.deleteSelected()
        await m.deleteTask?.value

        #expect(runner.calls.count == before, "aucun appel après le scan")
        #expect(deleteCalls().isEmpty)
        #expect(m.selected == selection)
        #expect(toasts.messages.isEmpty)
        #expect(!m.isDeleting)
        #expect(m.deleteTask == nil)
    }

    @Test func deleteDoesNothingWhenTheRuleSaysNo() async {
        scriptList([Self.list([Self.device(1)])])
        let m = model(sizes: PerDeviceSizes([Self.a: [Self.half]]))
        await scanAndSelect(m, [])                      // rien de coché
        m.deleteSelected()
        #expect(confirm.asks.isEmpty, "pas même la question")
        #expect(m.deleteTask == nil)

        let fresh = model(sizes: PerDeviceSizes([:]))   // jamais scanné
        fresh.deleteSelected()
        #expect(confirm.asks.isEmpty)
    }

    @Test func deleteIsUnavailableWhileTheSizesAreBeingMeasured() async {
        scriptList([Self.list([Self.device(1)])])
        let gated = ScriptedMeasure([Self.a: Self.half], gated: true)
        let m = SimulatorsModel(runner: runner, detect: { self.present }, locateXcrun: { _ in Self.xcrun }, home: box.root,
                                measure: { gated.measure($0) }, demo: false, confirm: confirm.handler, deletionGate: gate, notify: { _ in })
        m.scan()
        await gated.started.wait()
        #expect(m.isMeasuring)
        #expect(!m.canDelete)
        m.deleteSelected()
        #expect(confirm.asks.isEmpty)
        gated.release.signal()
        await m.scanTask?.value
    }

    // MARK: Lot complet

    @Test func afterTheConfirmationTheCallsAreScanThenRecheckAndDeletePerDeviceThenRescan() async {
        scriptList([Self.list([Self.device(1), Self.device(2), Self.device(3)]),    // scan
                    Self.list([Self.device(1), Self.device(2), Self.device(3)]),    // revérification du premier
                    Self.list([Self.device(1), Self.device(2), Self.device(3)]),    // revérification du second
                    Self.list([Self.device(3)])])                                   // nouveau scan
        scriptDelete(Self.a)
        scriptDelete(Self.b)
        let sizes = PerDeviceSizes([Self.a: [Self.half, Self.half, 0], Self.b: [400_000_000, 400_000_000, 100_000_000],
                                    Self.c: [300_000_000]])
        let m = model(sizes: sizes)
        await scanAndSelect(m, [Self.a, Self.b])
        let order = displayOrder(m).filter { [Self.a, Self.b].contains($0) }

        m.deleteSelected()
        #expect(m.isDeleting, "tout de suite après la confirmation")
        await m.deleteTask?.value

        var expected: [[String]] = [Self.listArgs]
        for id in order { expected += [Self.listArgs, ["simctl", "delete", id]] }
        expected.append(Self.listArgs)
        #expect(runner.calls.map(\.arguments) == expected)
        #expect(runner.calls.allSatisfy { $0.executable == "/usr/bin/xcrun" })
        #expect(runner.unscriptedCalls.isEmpty)
        #expect(toasts.messages == [freed(Self.half + 300_000_000)], "avant moins après, pour chaque appareil")
        #expect(!m.isDeleting)
        #expect(m.phase == .listed)
        #expect(displayOrder(m) == [Self.c], "la liste est relue : les appareils supprimés ont disparu")
        #expect(sizes.callsOnTheMainThread == 0, "ni scan, ni lot sur le fil principal")
    }

    @Test func everyTargetIsMeasuredBeforeAndAfterItsOwnDeleteAndNeverOnTheMainThread() async {
        scriptList([Self.list([Self.device(1)])])
        scriptDelete(Self.a)
        let sizes = PerDeviceSizes([Self.a: [Self.half, Self.half, 0]])
        let m = model(sizes: sizes)
        await scanAndSelect(m, [Self.a])
        m.deleteSelected()
        await m.deleteTask?.value
        #expect(sizes.calls.filter { $0 == Self.a }.count >= 3)
        #expect(sizes.callsOnTheMainThread == 0)
    }

    // MARK: Appareil démarré entre le scan et l'action (R5)

    @Test func aDeviceBootedAfterTheScanIsRefusedAndTheOthersAreRemoved() async {
        // Deux appareils cochés : le premier a démarré depuis le scan (refusé), le second est retiré.
        let booted = Self.device(1, name: "iPhone 15", state: "Booted")
        scriptList([Self.list([Self.device(1, name: "iPhone 15"), Self.device(2)]),
                    Self.list([booted, Self.device(2)]),
                    Self.list([booted, Self.device(2)]),
                    Self.list([booted, Self.device(2)])])
        scriptDelete(Self.b)
        let sizes = PerDeviceSizes([Self.a: [Self.half], Self.b: [Self.half, Self.half, 0]])
        let m = model(sizes: sizes)
        await scanAndSelect(m, [Self.a, Self.b])

        m.deleteSelected()
        await m.deleteTask?.value

        #expect(deleteCalls().map(\.arguments) == [["simctl", "delete", Self.b]], "le démarré n'est jamais touché")
        #expect(toasts.messages == ["\(freed(Self.half)) · “iPhone 15” is running: quit it first."])
    }

    @Test func aSingleBootedTargetShowsOnlyTheRunningText() async {
        let booted = Self.device(1, name: "iPhone 15", state: "Booted")
        scriptList([Self.list([Self.device(1, name: "iPhone 15")]), Self.list([booted]), Self.list([booted])])
        let m = model(sizes: PerDeviceSizes([Self.a: [Self.half]]))
        await scanAndSelect(m, [Self.a])

        m.deleteSelected()
        await m.deleteTask?.value

        #expect(deleteCalls().isEmpty)
        #expect(toasts.messages == ["“iPhone 15” is running: quit it first."])
        #expect(m.phase == .listed, "nouveau scan : l'appareil est maintenant affiché comme en cours d'exécution")
        #expect(m.rows.first?.isRunning == true)
    }

    @Test func aRunningAndAFailedDeviceGiveTheCombinedCount() async {
        let booted = Self.device(1, state: "Booted")
        scriptList([Self.list([Self.device(1), Self.device(2)]), Self.list([booted, Self.device(2)]),
                    Self.list([booted, Self.device(2)]), Self.list([booted, Self.device(2)])])
        scriptDelete(Self.b, .finished(exit: 1, stderr: "boom /Users/someone"))
        let m = model(sizes: PerDeviceSizes([Self.a: [Self.half], Self.b: [Self.half]]))
        await scanAndSelect(m, [Self.a, Self.b])

        m.deleteSelected()
        await m.deleteTask?.value

        #expect(toasts.messages == ["Devices that could not be removed: 2"])
    }

    @Test func aRunningDeviceCanNeverBeSelected() async {
        scriptList([Self.list([Self.device(1, state: "Booted"), Self.device(2)])])
        let m = model(sizes: PerDeviceSizes([Self.a: [Self.half], Self.b: [Self.half]]))
        m.scan()
        await m.scanTask?.value
        let running = m.rows.first { $0.device.device.udid == Self.a }!
        #expect(running.isRunning)
        m.toggle(running)
        #expect(!m.selected.contains(Self.a))
        #expect(m.selectedCount == m.selected.count)
        for row in m.rows where !row.isRunning && !m.selected.contains(row.device.device.udid) { m.toggle(row) }
        #expect(!m.selected.contains(Self.a))
    }

    // MARK: Échecs

    @Test func aDeleteTimeoutStopsTheBatchAndShowsTheDidNotAnswerText() async {
        scriptList([Self.list([Self.device(1), Self.device(2)])])
        scriptDelete(Self.a, .timedOut)
        scriptDelete(Self.b)
        let m = model(sizes: PerDeviceSizes([Self.a: [Self.half], Self.b: [Self.half]]))
        await scanAndSelect(m, [Self.a, Self.b])
        let first = displayOrder(m).first { [Self.a, Self.b].contains($0) }!
        scriptDelete(first, .timedOut)

        m.deleteSelected()
        await m.deleteTask?.value

        #expect(deleteCalls().count == 1, "aucune suppression après le délai dépassé")
        #expect(toasts.messages == ["Xcode’s simulator service did not answer. Try again in a moment."])
        #expect(!m.isDeleting)
        #expect(m.phase == .listed, "le scan est quand même relancé")
    }

    @Test func aFailingToolLeavesTheRealFolderAndShowsTheCount() async throws {
        try box.file("Library/Developer/CoreSimulator/Devices/\(Self.a)/data/file.bin")
        scriptList([Self.list([Self.device(1)])])
        scriptDelete(Self.a, .finished(exit: 1))
        let m = model(sizes: PerDeviceSizes([Self.a: [Self.half]]))
        await scanAndSelect(m, [Self.a])

        m.deleteSelected()
        await m.deleteTask?.value

        #expect(toasts.messages == ["Devices that could not be removed: 1"])
        #expect(box.exists("Library/Developer/CoreSimulator/Devices/\(Self.a)/data/file.bin"))
    }

    @Test func theToolAndTheDetectionAreCheckedAgainAtActionTime() async {
        scriptList([Self.list([Self.device(1), Self.device(2)])])
        var detections = 0, locates = 0
        let sizes = PerDeviceSizes([Self.a: [Self.half], Self.b: [Self.half]])
        // La porte donne `xcrun` au scan, puis plus rien : Xcode a disparu entre-temps.
        let m = model(sizes: sizes, detect: { detections += 1 }, locate: { _ in locates += 1; return locates == 1 ? Self.xcrun : nil })
        await scanAndSelect(m, [Self.a, Self.b])
        #expect(detections == 1 && locates == 1)

        m.deleteSelected()
        await m.deleteTask?.value

        #expect(detections == 3, "scan, action, nouveau scan")
        #expect(locates == 3)
        #expect(runner.calls.count == 1, "après le scan, plus aucun lancement")
        #expect(toasts.messages == ["Devices that could not be removed: 2"], "chaque cible compte comme un échec")
        #expect(m.phase == .failed(.couldNotRead))
    }

    // MARK: Pendant la suppression

    @Test func toggleLimitAndScanAreIgnoredWhileDeleting() async {
        let blocking = BlockingRunner(Self.list([Self.device(1), Self.device(2)]))
        let m = model(blocking, sizes: PerDeviceSizes([Self.a: [Self.half], Self.b: [Self.half]]))
        m.scan()
        await blocking.started.wait()
        blocking.release.signal()
        await m.scanTask?.value
        for row in m.rows where !m.selected.contains(row.device.device.udid) { m.toggle(row) }
        let selection = m.selected, limit = m.limitDays, rowsBefore = m.rows
        #expect(selection.count == 2)

        m.deleteSelected()
        await blocking.started.wait()                 // la revérification du premier appareil est en cours
        #expect(m.isDeleting)
        #expect(!m.canDelete)
        #expect(!m.canScanAgain)
        let callsBefore = blocking.calls.count

        m.toggle(m.rows[0])
        m.setLimit(180)
        m.scan()

        #expect(m.selected == selection)
        #expect(m.limitDays == limit)
        #expect(m.rows == rowsBefore)
        #expect(m.phase == .listed)
        #expect(blocking.calls.count == callsBefore, "scan() est ignoré : aucun nouvel appel")

        for _ in 0..<20 { blocking.release.signal() }
        await m.deleteTask?.value
        #expect(!m.isDeleting)
    }

    @Test func backDuringADeletionStartsNoNewTargetKeepsTheToastAndLeavesTheScreenToRescan() async {
        let blocking = BlockingRunner(Self.list([Self.device(1), Self.device(2)]))
        let sizes = PerDeviceSizes([Self.a: [Self.half, Self.half, 0], Self.b: [Self.half, Self.half, 0]])
        let m = model(blocking, sizes: sizes)
        m.scan()
        await blocking.started.wait()
        blocking.release.signal()
        await m.scanTask?.value
        for row in m.rows where !m.selected.contains(row.device.device.udid) { m.toggle(row) }

        m.deleteSelected()
        await blocking.started.wait()                 // revérification du premier appareil en cours
        m.cancel()                                    // bouton Retour
        #expect(m.phase == .notScanned)
        for _ in 0..<20 { blocking.release.signal() }
        await m.deleteTask?.value

        let deletes = blocking.calls.filter { $0.arguments.contains("delete") }
        #expect(deletes.count == 1, "le premier appareil est fini, le second n'est pas commencé")
        #expect(blocking.calls.count == 3, "scan, revérification, suppression : pas de nouveau scan")
        #expect(toasts.messages == [freed(Self.half)], "le toast dit ce qui a été fait")
        #expect(m.phase == .notScanned, "la prochaine ouverture relance le scan, jamais de liste périmée")
        #expect(!m.isDeleting)
        #expect(m.rows.isEmpty)
    }

    // MARK: Une suppression en cours est un fait du processus, pas d'un modèle (revue, point 1)

    /// Deux appareils listés, cochés, prêts à être supprimés avec un lanceur bloquant.
    func blockedBatch(_ model: SimulatorsModel, _ blocking: BlockingRunner) async {
        model.scan()
        await blocking.started.wait()
        blocking.release.signal()
        await model.scanTask?.value
        for row in model.rows where !model.selected.contains(row.device.device.udid) { model.toggle(row) }
        model.deleteSelected()
        await blocking.started.wait()                 // la revérification du premier appareil est en cours
    }

    @Test func aBatchStillEndsWithItsToastAndFreesTheGateWhenTheModelIsDestroyed() async {
        let blocking = BlockingRunner(Self.list([Self.device(1), Self.device(2)]))
        let sizes = PerDeviceSizes([Self.a: [Self.half, Self.half, 0], Self.b: [Self.half, Self.half, 0]])
        var m: SimulatorsModel? = model(blocking, sizes: sizes)
        await blockedBatch(m!, blocking)
        #expect(gate.isBusy)
        let task = m!.deleteTask!
        weak var weakModel = m
        m = nil                                       // l'onglet a été quitté : le modèle disparaît
        #expect(weakModel == nil, "le lot ne retient pas le modèle")

        for _ in 0..<20 { blocking.release.signal() }
        await task.value

        #expect(toasts.messages == [freed(2 * Self.half)], "le toast arrive quand même")
        #expect(!gate.isBusy, "la porte est libérée")
        #expect(blocking.calls.filter { $0.arguments.contains("delete") }.count == 2, "le lot va jusqu'au bout")
    }

    @Test func aSecondModelCannotScanOrDeleteWhileABatchRunsAndCanAfterwards() async {
        let blocking = BlockingRunner(Self.list([Self.device(1), Self.device(2)]))
        let sizes = PerDeviceSizes([Self.a: [Self.half, Self.half, 0], Self.b: [Self.half, Self.half, 0]])
        let first = model(blocking, sizes: sizes)

        // L'autre surface (fenêtre ou panneau) a déjà sa liste, cochée.
        let otherRunner = FakeCommandRunner()
        otherRunner.script(Self.list([Self.device(1), Self.device(2)]), executable: Self.xcrun, arguments: Self.listArgs)
        otherRunner.script(.finished(), executable: Self.xcrun, arguments: ["simctl", "delete", Self.a])
        otherRunner.script(.finished(), executable: Self.xcrun, arguments: ["simctl", "delete", Self.b])
        let other = model(otherRunner, sizes: PerDeviceSizes([Self.a: [Self.half], Self.b: [Self.half]]))
        await scanAndSelect(other, [Self.a, Self.b])
        // L'onglet rouvert : un modèle neuf.
        let reopenedRunner = FakeCommandRunner()
        reopenedRunner.script(Self.list([Self.device(3)]), executable: Self.xcrun, arguments: Self.listArgs)
        let reopened = model(reopenedRunner, sizes: PerDeviceSizes([Self.c: [Self.half]]))

        await blockedBatch(first, blocking)
        let asks = confirm.asks.count, otherCalls = otherRunner.calls.count

        #expect(other.isDeleting && reopened.isDeleting, "tous les modèles le voient")
        #expect(!other.canDelete && !other.canScanAgain)
        other.deleteSelected()
        other.scan()
        reopened.scan()
        #expect(confirm.asks.count == asks, "pas même la question")
        #expect(otherRunner.calls.count == otherCalls, "ni scan ni suppression")
        #expect(reopenedRunner.calls.isEmpty)
        #expect(reopened.phase == .notScanned)
        #expect(!gate.begin(), "la porte refuse un second lot")

        for _ in 0..<20 { blocking.release.signal() }
        await first.deleteTask?.value
        await reopened.scanTask?.value               // son scan demandé pendant le lot part à la fin

        #expect(!gate.isBusy)
        #expect(reopened.phase == .listed && reopenedRunner.calls.count == 1)
        #expect(other.canDelete && other.canScanAgain, "après le lot, l'autre modèle peut agir")
        #expect(otherRunner.calls.count == otherCalls, "l'autre modèle n'a pas été relancé tout seul")
    }

    @Test func theGateIsFreeAgainAfterATimeoutAfterAFailureAndWhenTheToolIsGone() async {
        scriptList([Self.list([Self.device(1)])])
        scriptDelete(Self.a, .timedOut)
        let m = model(sizes: PerDeviceSizes([Self.a: [Self.half]]))
        await scanAndSelect(m, [Self.a])
        m.deleteSelected()
        #expect(gate.isBusy)
        await m.deleteTask?.value
        #expect(!gate.isBusy, "délai dépassé")

        scriptDelete(Self.a, .finished(exit: 1))
        await scanAndSelect(m, [Self.a])
        m.deleteSelected()
        await m.deleteTask?.value
        #expect(!gate.isBusy, "échec")
        #expect(m.canScanAgain)

        var locates = 0
        let gone = model(sizes: PerDeviceSizes([Self.a: [Self.half]]), locate: { _ in locates += 1; return locates == 1 ? Self.xcrun : nil })
        await scanAndSelect(gone, [Self.a])
        gone.deleteSelected()
        await gone.deleteTask?.value
        #expect(!gate.isBusy, "outil disparu")
    }

    @Test func theSharedGateIsTheDefaultOfTheApplicationModels() {
        let m = SimulatorsModel(runner: FakeCommandRunner(), demo: false, confirm: { _, _, _, _ in false }, notify: { _ in })
        #expect(m.isDeleting == SimulatorDeletionGate.shared.isBusy)
    }

    @Test func backThenReopeningDuringTheBatchRescansWhenItEnds() async {
        let blocking = BlockingRunner(Self.list([Self.device(1), Self.device(2)]))
        let sizes = PerDeviceSizes([Self.a: [Self.half, Self.half, 0], Self.b: [Self.half, Self.half, 0]])
        let m = model(blocking, sizes: sizes)
        await blockedBatch(m, blocking)
        m.cancel()                                    // Retour
        #expect(m.phase == .notScanned)
        m.scan()                                      // l'écran est rouvert avant la fin : ignoré, mais retenu
        #expect(m.phase == .notScanned)
        #expect(m.progressMessage == "Deleting…", "pas « Looking for… » pendant la suppression, même pour un modèle neuf")

        for _ in 0..<20 { blocking.release.signal() }
        await m.deleteTask?.value
        await m.scanTask?.value

        #expect(m.phase == .listed, "le scan retenu part à la fin du lot")
        #expect(m.progressMessage == "Looking for simulators and emulators…")
        #expect(!gate.isBusy)
    }

    // MARK: Catalogue

    @Test func theTwoConfirmationKeysAreInTheCatalogInNineLanguages() throws {
        let catalog = try TranslationCatalog.loadCatalog(TranslationCatalogTests.localizable)
        let strings = try #require(catalog["strings"] as? [String: Any])
        let keys = ["Delete the selected devices? (%lld)",
                    "%@ will be freed. The devices, the apps and data on them, and their snapshots will be deleted. "
                    + "You can create new devices from Xcode or Android Studio."]
        for key in keys {
            let entry = try #require(strings[key] as? [String: Any], "clé absente : \(key)")
            #expect(entry["variations"] == nil)
            let localizations = try #require(entry["localizations"] as? [String: Any])
            #expect(Set(localizations.keys) == Set(TranslationCatalog.requiredTranslations))
            for language in TranslationCatalog.requiredTranslations {
                let unit = try #require((localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any], "\(key) / \(language)")
                let value = try #require(unit["value"] as? String)
                #expect(!value.isEmpty)
                #expect(TranslationCatalog.placeholders(in: value).byPosition == TranslationCatalog.placeholders(in: key).byPosition,
                        "\(key) / \(language)")
            }
        }
    }
}
