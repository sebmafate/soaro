import Foundation
import Testing
@testable import Soaro

/// Lanceur qui rend les résultats d'un `FakeCommandRunner` mais peut BLOQUER un appel choisi (après l'avoir noté), pour arrêter un lot
/// au milieu (Retour, modèle détruit) sans dormir. Armé APRÈS le scan, il ne bloque que les appels qui suivent.
final class GatedRunner: CommandRunner, @unchecked Sendable {
    let inner = FakeCommandRunner()
    let started = AsyncSignal()
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var armed = false
    private let blocks: (String, [String]) -> Bool

    init(blocks: @escaping (String, [String]) -> Bool) { self.blocks = blocks }

    func arm() { lock.lock(); armed = true; lock.unlock() }

    func run(executable: String, arguments: [String], timeLimit: TimeInterval, outputLimit: Int) -> CommandOutcome {
        lock.lock(); let block = armed && blocks(executable, arguments); if block { armed = false }; lock.unlock()
        let outcome = inner.run(executable: executable, arguments: arguments, timeLimit: timeLimit, outputLimit: outputLimit)
        if block { started.signal(); release.wait() }
        return outcome
    }
}

/// SL11 T5 : Delete agit sur les deux groupes (iOS et Android), derrière la même confirmation, la même porte et le même jeton.
/// Dossier personnel de bac à sable `.soaro-test-` (jamais le vrai `~/.android`), faux lanceur, `removeFile` noté. Avant toute
/// confirmation « oui », le test exige que le dossier personnel injecté soit un bac à sable (`requireSandbox`).
@MainActor
@Suite(.serialized) struct AndroidDeletionModelTests {
    static let u1 = "00000000-0000-4000-8000-000000000001"
    static let u2 = "00000000-0000-4000-8000-000000000002"
    static let listArgs = ["simctl", "list", "devices", "-j"]
    static let psArguments = ["-axww", "-o", "command="]
    static let big: UInt64 = 500_000_000
    static let ini: UInt64 = 4_096
    let now = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!
    let present = SimulatorToolDetection(devicesFolderExists: true, simctlPath: "/fake/simctl")
    let absent = SimulatorToolDetection(devicesFolderExists: false, simctlPath: nil)

    let gate = SimulatorDeletionGate()
    let confirm = RecordingConfirm(answer: false)
    let toasts = ToastBox()
    let recorder = AndroidRemovalOneDeviceTests.RemoveRecorder()

    final class ToastBox { var messages: [String] = [] }

    /// Compteurs des appels de détection et de recherche d'outil, par le modèle.
    final class Counters {
        var detections = 0
        var xcrunLookups = 0
        var psLookups = 0
        /// `ps` introuvable à partir de cette recherche (1 = dès le scan) ; `nil` : toujours trouvé.
        var psMissingOnLookup: Int?
    }

    func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    /// Dossier personnel de bac à sable : un faux SDK et les AVD donnés (nom, nom affiché).
    func home(_ avds: [(name: String, display: String)]) throws -> Sandbox {
        let box = try Sandbox(insideHome: true)
        try box.dir("Library/Android/sdk")
        for avd in avds {
            try box.dir(".android/avd/\(avd.name).avd")
            try box.write(".android/avd/\(avd.name).ini", "path.rel=avd/\(avd.name).avd\n")
            try box.write(".android/avd/\(avd.name).avd/config.ini",
                          "avd.ini.displayname=\(avd.display)\nimage.sysdir.1=system-images/android-36/google_apis/arm64-v8a/\n")
            try box.write(".android/avd/\(avd.name).avd/userdata-qemu.img", "x")
        }
        return box
    }

    let phone = (name: "Test_Phone_A", display: "Test Phone A")
    let tablet = (name: "Test_Tablet_B", display: "Test Tablet B")

    func psLine(_ avd: String) -> String { "/Users/test/Library/Android/sdk/emulator/qemu/darwin-aarch64/qemu-system-aarch64 -avd \(avd) -netdelay none" }

    func fake(ios: [[String]] = [], ps: [String] = [""]) -> FakeCommandRunner {
        let fake = FakeCommandRunner()
        if !ios.isEmpty {
            fake.script(sequence: ios.map { .finished(stdout: SimulatorsModelTests.listJSON($0)) }, executable: "/usr/bin/xcrun", arguments: Self.listArgs)
            for udid in [Self.u1, Self.u2] { fake.script(.finished(), executable: "/usr/bin/xcrun", arguments: ["simctl", "delete", udid]) }
        }
        fake.script(sequence: ps.map { .finished(stdout: $0) }, executable: "/bin/ps", arguments: Self.psArguments)
        return fake
    }

    func sizes(_ extra: [String: [UInt64]] = [:]) -> PerDeviceSizes {
        var table: [String: [UInt64]] = [
            // Dossier : scan, avant, après (ou nouveau scan) ; `.ini` : avant, après (le scan ne mesure que les dossiers).
            "Test_Phone_A.avd": [Self.big, Self.big, 0], "Test_Phone_A.ini": [Self.ini, 0],
            "Test_Tablet_B.avd": [Self.big, Self.big, 0], "Test_Tablet_B.ini": [Self.ini, 0],
            Self.u1: [Self.big, Self.big, 0], Self.u2: [Self.big, Self.big, 0],
        ]
        for (key, value) in extra { table[key] = value }
        return PerDeviceSizes(table)
    }

    func model(_ runner: CommandRunner, home box: Sandbox, detection: SimulatorToolDetection? = nil, counters: Counters = Counters(),
               measure: PerDeviceSizes? = nil, removeFile: ((URL) throws -> Void)? = nil) -> SimulatorsModel {
        let detection = detection ?? present
        let measure = measure ?? sizes()
        let toasts = toasts
        let remove = removeFile ?? recorder.remove
        return SimulatorsModel(runner: runner,
                               detect: { counters.detections += 1; return detection },
                               locateTool: { candidates in
                                   if candidates == ToolLocator.processListCandidates {
                                       counters.psLookups += 1
                                       if let missing = counters.psMissingOnLookup, counters.psLookups == missing { return nil }
                                       return "/bin/ps"
                                   }
                                   counters.xcrunLookups += 1
                                   return "/usr/bin/xcrun"
                               },
                               environment: [:], home: box.root, now: { self.now },
                               measure: { measure.measure($0) },
                               removeFile: remove,
                               demo: false, confirm: confirm.handler, deletionGate: gate, notify: { toasts.messages.append($0) })
    }

    /// Scan, puis coche exactement ces appareils (les autres sont décochés).
    func scanAndSelect(_ m: SimulatorsModel, ios: [String] = [], android: [String] = []) async {
        m.scan()
        await m.scanTask?.value
        for row in m.rows where m.selected.contains(row.device.device.udid) != ios.contains(row.device.device.udid) { m.toggle(row) }
        for row in m.androidRows where m.androidSelected.contains(row.device.device.name) != android.contains(row.device.device.name) { m.toggle(row) }
    }

    /// GARDE-FOU : le dossier personnel du modèle est un bac à sable, sinon le test échoue AVANT toute confirmation « oui ».
    func requireSandbox(_ m: SimulatorsModel) throws {
        try #require(m.home.path.contains(".soaro-test-"), "le modèle doit utiliser un dossier personnel de bac à sable")
    }

    func confirmedDelete(_ m: SimulatorsModel) async throws {
        try requireSandbox(m)
        confirm.answer = true
        m.deleteSelected()
        await m.deleteTask?.value
    }

    func freed(_ value: UInt64) -> String { "\(Format.fileBytes(value)) freed" }

    static let messageTail = "will be freed. The devices, the apps and data on them, and their snapshots will be deleted. "
        + "You can create new devices from Xcode or Android Studio."

    // MARK: La règle « Delete disponible »

    @Test(arguments: [
        // (iOS, Android, mesure, iOS cochés, Android cochés, suppression, attendu)
        (SimulatorsModel.Phase.hidden, SimulatorsModel.Phase.listed, false, 0, 1, false, true),      // Android seul, iOS caché
        (.listed, .listed, false, 1, 1, false, true),                                                  // les deux groupes cochés
        (.listed, .listed, false, 0, 1, false, true),                                                  // Android coché seulement
        (.listed, .listed, false, 1, 0, false, true),                                                  // iOS coché seulement
        (.listed, .listed, true, 1, 1, false, false),                                                  // tailles en cours de mesure
        (.listed, .listed, false, 1, 1, true, false),                                                  // suppression en cours
        (.listed, .listed, false, 0, 0, false, false),                                                 // rien de coché
        (.hidden, .listed, false, 2, 0, false, false),                                                 // iOS non listé : ses cases ne comptent pas
        (.listed, .hidden, false, 0, 3, false, false),                                                 // Android non listé : ses cases ne comptent pas
        (.listed, .failed(.couldNotRead), false, 0, 1, false, false),
    ])
    func theStaticRuleTakesBothGroups(phase: SimulatorsModel.Phase, android: SimulatorsModel.Phase, measuring: Bool, iosChecked: Int,
                                       androidChecked: Int, deleting: Bool, expected: Bool) {
        #expect(SimulatorsModel.canDelete(phase: phase, androidPhase: android, isMeasuring: measuring, selectedCount: iosChecked,
                                          androidSelectedCount: androidChecked, isDeleting: deleting) == expected)
    }

    @Test func androidOnlyCheckedByHandMakesDeleteUsable() async throws {
        let box = try home([phone])
        let m = model(fake(ps: [""]), home: box, detection: absent)
        await scanAndSelect(m, android: [])
        #expect(!m.canDelete, "rien n'est coché d'office")
        let row = try #require(m.androidRows.first)
        m.toggle(row)
        #expect(m.canDelete)
        m.toggle(row)
        #expect(!m.canDelete)
    }

    // MARK: Confirmation (R8)

    @Test func theConfirmationCountsAndSizesBothGroupsWithTheExistingTexts() async throws {
        let box = try home([phone])
        let m = model(fake(ios: [[Self.u1]]), home: box)
        await scanAndSelect(m, ios: [Self.u1], android: ["Test_Phone_A"])
        confirm.answer = false

        m.deleteSelected()

        let ask = try #require(confirm.asks.first)
        #expect(confirm.asks.count == 1)
        #expect(ask.title == "Delete the selected devices? (2)")
        #expect(ask.message == "\(Format.fileBytes(2 * Self.big)) \(Self.messageTail)\n\n• Device 1\n• Test Phone A", "iOS puis Android, noms verbatim")
        #expect(ask.button == "Delete")
        #expect(ask.critical)
    }

    @Test func cancellingTheConfirmationChangesNothing() async throws {
        let box = try home([phone, tablet])
        let runner = fake(ios: [[Self.u1]])
        let m = model(runner, home: box)
        await scanAndSelect(m, ios: [Self.u1], android: ["Test_Phone_A"])
        try requireSandbox(m)
        let before = runner.calls.count, selected = m.selected, androidSelected = m.androidSelected
        confirm.answer = false

        m.deleteSelected()
        await m.deleteTask?.value

        #expect(runner.calls.count == before, "aucun appel après le scan")
        #expect(recorder.calls.isEmpty, "aucune suppression")
        #expect(m.selected == selected && m.androidSelected == androidSelected)
        #expect(toasts.messages.isEmpty)
        #expect(!m.isDeleting && m.deleteTask == nil)
        #expect(box.exists(".android/avd/Test_Phone_A.ini") && box.exists(".android/avd/Test_Phone_A.avd/config.ini"))
    }

    // MARK: Lot Android seul

    @Test func androidOnlyCallsPsThenTheRescanAndNeverXcrunNorTheDetectionAgain() async throws {
        let box = try home([phone, tablet])
        let runner = fake(ps: [""])
        let counters = Counters()
        let m = model(runner, home: box, detection: absent, counters: counters)
        await scanAndSelect(m, android: ["Test_Phone_A"])
        let afterScan = runner.calls.count
        #expect(counters.detections == 1 && counters.xcrunLookups == 0 && counters.psLookups == 1)

        try await confirmedDelete(m)

        let calls = Array(runner.calls.dropFirst(afterScan))
        #expect(calls.map(\.executable) == ["/bin/ps", "/bin/ps"], "la revérification, puis le nouveau scan")
        #expect(calls.allSatisfy { $0.arguments == Self.psArguments && $0.timeLimit == 10 && $0.outputLimit == 4 * 1024 * 1024 })
        #expect(counters.detections == 2, "scan et nouveau scan seulement : pas de détection à l'action")
        #expect(counters.xcrunLookups == 0)
        #expect(counters.psLookups == 3, "scan, action, nouveau scan")
        #expect(!box.exists(".android/avd/Test_Phone_A.ini") && !box.exists(".android/avd/Test_Phone_A.avd"))
        #expect(box.exists(".android/avd/Test_Tablet_B.ini") && box.exists(".android/avd/Test_Tablet_B.avd/config.ini"))
        #expect(recorder.calls == ["Test_Phone_A.avd", "Test_Phone_A.ini"])
        #expect(toasts.messages == [freed(Self.big + Self.ini)])
        #expect(m.androidRows.map(\.device.device.name) == ["Test_Tablet_B"], "la liste est relue : la ligne a disparu")
        #expect(m.androidSelected.isEmpty)
        #expect(!m.isDeleting)
    }

    @Test func anAndroidOnlyBatchWithIosListedNeverAsksXcrunAtActionTime() async throws {
        let box = try home([phone])
        let runner = fake(ios: [[Self.u1]], ps: [""])
        let counters = Counters()
        let m = model(runner, home: box, counters: counters)
        await scanAndSelect(m, android: ["Test_Phone_A"])
        let afterScan = runner.calls.count
        #expect(counters.xcrunLookups == 1 && counters.detections == 1)

        try await confirmedDelete(m)

        #expect(Array(runner.calls.dropFirst(afterScan)).map(\.arguments) == [Self.psArguments, Self.listArgs],
                "ps (revérification), puis le nouveau scan : simctl list (plus d'AVD : pas de ps)")
        #expect(counters.detections == 2 && counters.xcrunLookups == 2, "scan et nouveau scan seulement")
        #expect(!runner.calls.contains { $0.arguments.contains("delete") })
    }

    @Test func anIosOnlyBatchNeverLooksUpPsNorRunsItAtActionTime() async throws {
        let box = try home([phone])
        let runner = fake(ios: [[Self.u1, Self.u2], [Self.u1, Self.u2], [Self.u2]], ps: [""])
        let counters = Counters()
        let m = model(runner, home: box, counters: counters)
        await scanAndSelect(m, ios: [Self.u1], android: [])
        let afterScan = runner.calls.count
        #expect(counters.psLookups == 1)

        try await confirmedDelete(m)

        #expect(Array(runner.calls.dropFirst(afterScan)).map(\.arguments) == [Self.listArgs, ["simctl", "delete", Self.u1], Self.listArgs, Self.psArguments],
                "iOS : revérification, suppression ; nouveau scan : simctl list, ps (Android est toujours listé)")
        #expect(counters.psLookups == 2, "scan et nouveau scan seulement : aucune recherche de ps à l'action")
        #expect(recorder.calls.isEmpty)
        #expect(box.exists(".android/avd/Test_Phone_A.ini") && box.exists(".android/avd/Test_Phone_A.avd/config.ini"))
    }

    // MARK: Lot mixte

    @Test func aMixedBatchRunsIosThenAndroidThenRescansAndTheToastIsTheSumOfBoth() async throws {
        let box = try home([phone, tablet])
        // simctl list : scan, revérification de l'appareil iOS, nouveau scan (l'appareil a disparu).
        let runner = fake(ios: [[Self.u1, Self.u2], [Self.u1, Self.u2], [Self.u2]], ps: [""])
        let m = model(runner, home: box)
        await scanAndSelect(m, ios: [Self.u1], android: ["Test_Phone_A"])
        let afterScan = runner.calls.count

        try await confirmedDelete(m)

        let calls = Array(runner.calls.dropFirst(afterScan))
        #expect(calls.map(\.arguments) == [Self.listArgs, ["simctl", "delete", Self.u1], Self.psArguments, Self.listArgs, Self.psArguments])
        #expect(runner.unscriptedCalls.isEmpty)
        #expect(toasts.messages == [freed(Self.big + Self.big + Self.ini)], "iOS 500 Mo, Android 500 Mo et 4 Ko")
        #expect(m.rows.map(\.device.device.udid) == [Self.u2])
        #expect(m.androidRows.map(\.device.device.name) == ["Test_Tablet_B"])
        #expect(m.selected.isEmpty && m.androidSelected.isEmpty)
        #expect(!box.exists(".android/avd/Test_Phone_A.ini") && box.exists(".android/avd/Test_Tablet_B.ini"))
    }

    // MARK: En cours d'exécution à l'action

    @Test func anAvdStartedBetweenTheScanAndTheActionIsRefusedAndTheOthersAreRemoved() async throws {
        let box = try home([phone, tablet])
        // `ps` : scan (rien), revérification de A (A tourne), revérification de B (rien), nouveau scan (A tourne toujours).
        let runner = fake(ps: ["", psLine("Test_Phone_A"), "", psLine("Test_Phone_A")])
        let m = model(runner, home: box, detection: absent)
        await scanAndSelect(m, android: ["Test_Phone_A", "Test_Tablet_B"])

        try await confirmedDelete(m)

        #expect(box.exists(".android/avd/Test_Phone_A.ini") && box.exists(".android/avd/Test_Phone_A.avd/config.ini"), "A est intact")
        #expect(!box.exists(".android/avd/Test_Tablet_B.ini") && !box.exists(".android/avd/Test_Tablet_B.avd"))
        #expect(recorder.calls == ["Test_Tablet_B.avd", "Test_Tablet_B.ini"])
        #expect(toasts.messages == ["\(freed(Self.big + Self.ini)) · “Test Phone A” is running: quit it first."])
    }

    @Test func anAvdAliasRunningMakesTheDeviceRefused() async throws {
        let box = try home([phone])
        try box.write(".android/avd/Test_Phone_B.ini", "path=\(box.root.path)/.android/avd/Test_Phone_A.avd\n")
        let runner = fake(ps: ["", psLine("Test_Phone_B")])
        let m = model(runner, home: box, detection: absent)
        await scanAndSelect(m, android: ["Test_Phone_A"])

        try await confirmedDelete(m)

        #expect(recorder.calls.isEmpty)
        #expect(box.exists(".android/avd/Test_Phone_A.ini") && box.exists(".android/avd/Test_Phone_B.ini"))
        #expect(toasts.messages == ["“Test Phone A” is running: quit it first."])
    }

    @Test func aMissingPsAtActionTimeFailsTheAndroidTargetsWhileIosIsRemoved() async throws {
        let box = try home([phone, tablet])
        let runner = fake(ios: [[Self.u1], [Self.u1], []], ps: [""])
        let counters = Counters()
        counters.psMissingOnLookup = 2                      // trouvé au scan, introuvable à l'action
        let m = model(runner, home: box, counters: counters)
        await scanAndSelect(m, ios: [Self.u1], android: ["Test_Phone_A", "Test_Tablet_B"])
        let afterScan = runner.calls.count

        try await confirmedDelete(m)

        let calls = Array(runner.calls.dropFirst(afterScan)).map(\.arguments)
        #expect(calls == [Self.listArgs, ["simctl", "delete", Self.u1], Self.listArgs, Self.psArguments],
                "iOS supprimé ; aucun ps à l'action ; nouveau scan : simctl list, ps")
        #expect(recorder.calls.isEmpty)
        #expect(box.exists(".android/avd/Test_Phone_A.ini") && box.exists(".android/avd/Test_Tablet_B.ini"))
        #expect(toasts.messages == ["\(freed(Self.big)) · Devices that could not be removed: 2"])
    }

    // MARK: Retour et modèle détruit

    @Test func backAfterTheIosTargetStartsNoAndroidRemovalAndNoRescan() async throws {
        let box = try home([phone])
        let gated = GatedRunner { _, arguments in arguments.contains("delete") }
        gated.inner.script(sequence: [.finished(stdout: SimulatorsModelTests.listJSON([Self.u1]))], executable: "/usr/bin/xcrun", arguments: Self.listArgs)
        gated.inner.script(.finished(), executable: "/usr/bin/xcrun", arguments: ["simctl", "delete", Self.u1])
        gated.inner.script(.finished(stdout: ""), executable: "/bin/ps", arguments: Self.psArguments)
        let m = model(gated, home: box)
        await scanAndSelect(m, ios: [Self.u1], android: ["Test_Phone_A"])
        let afterScan = gated.inner.calls.count
        try requireSandbox(m)
        gated.arm()
        confirm.answer = true

        m.deleteSelected()
        await gated.started.wait()                         // la suppression iOS est en cours
        m.cancel()                                         // bouton Retour
        #expect(m.phase == .notScanned && m.androidPhase == .notScanned)
        for _ in 0..<5 { gated.release.signal() }
        await m.deleteTask?.value

        let calls = Array(gated.inner.calls.dropFirst(afterScan)).map(\.arguments)
        #expect(calls == [Self.listArgs, ["simctl", "delete", Self.u1]], "pas de ps, pas de nouveau scan")
        #expect(recorder.calls.isEmpty)
        #expect(box.exists(".android/avd/Test_Phone_A.ini") && box.exists(".android/avd/Test_Phone_A.avd/config.ini"))
        #expect(toasts.messages == ["\(freed(Self.big)) · Devices that could not be removed: 1"])
        #expect(m.phase == .notScanned && m.androidPhase == .notScanned)
        #expect(!gate.isBusy && !m.isDeleting)
    }

    @Test func aBatchStillEndsWithItsToastAndFreesTheGateWhenTheModelIsDestroyed() async throws {
        let box = try home([phone])
        let gated = GatedRunner { executable, _ in executable == "/bin/ps" }
        gated.inner.script(.finished(stdout: ""), executable: "/bin/ps", arguments: Self.psArguments)
        var m: SimulatorsModel? = model(gated, home: box, detection: absent)
        await scanAndSelect(m!, android: ["Test_Phone_A"])
        try requireSandbox(m!)
        gated.arm()
        confirm.answer = true

        m!.deleteSelected()
        await gated.started.wait()                         // la revérification de `ps` est en cours
        #expect(gate.isBusy)
        let task = m!.deleteTask!
        weak let weakModel = m
        m = nil                                            // l'onglet a été quitté
        #expect(weakModel == nil, "le lot ne retient pas le modèle")
        for _ in 0..<5 { gated.release.signal() }
        await task.value

        #expect(toasts.messages == [freed(Self.big + Self.ini)], "le toast arrive quand même")
        #expect(!gate.isBusy)
        #expect(!box.exists(".android/avd/Test_Phone_A.ini") && !box.exists(".android/avd/Test_Phone_A.avd"), "le lot va jusqu'au bout")
    }

    // MARK: La porte

    @Test func theGateIsBusyDuringTheBatchAndFreeAfterAFailure() async throws {
        let box = try home([phone])
        let runner = fake(ps: [""])
        let m = model(runner, home: box, detection: absent, measure: sizes(["Test_Phone_A.avd": [Self.big]]),
                      removeFile: { _ in throw CocoaError(.fileWriteNoPermission) })
        await scanAndSelect(m, android: ["Test_Phone_A"])
        try requireSandbox(m)
        confirm.answer = true

        m.deleteSelected()
        #expect(m.isDeleting && gate.isBusy)
        await m.deleteTask?.value

        #expect(!gate.isBusy)
        #expect(toasts.messages == ["Devices that could not be removed: 1"])
        #expect(box.exists(".android/avd/Test_Phone_A.ini") && box.exists(".android/avd/Test_Phone_A.avd/config.ini"))
        #expect(m.androidRows.count == 1, "la liste est relue : l'appareil est toujours là")
    }

    @Test func theModelNeverNamesTheRealRemover() throws {
        // Le suppresseur réel arrive par le paramètre `removeFile` : le modèle ne supprime jamais un fichier à la main.
        let text = try String(contentsOf: RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Cleanup/SimulatorsModel.swift"), encoding: .utf8)
        #expect(!text.contains("removeItem("))
        #expect(text.contains("AndroidEmulatorRemover.removeFile"))
    }
}
