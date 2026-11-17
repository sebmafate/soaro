import Foundation
import Testing
@testable import Soaro

/// Le groupe Android du modèle de l'outil « Simulators and emulators » (SL10 T9) : à côté d'iOS, jamais à sa place.
/// Faux lanceur, dossier personnel de bac à sable avec un faux SDK et des AVD, environnement injecté, `measure` écrit à la main.
@MainActor
@Suite(.serialized) struct AndroidGroupModelTests {
    static let u1 = "00000000-0000-4000-8000-000000000001"
    static let u2 = "00000000-0000-4000-8000-000000000002"
    let now = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!
    let present = SimulatorToolDetection(devicesFolderExists: true, simctlPath: "/fake/simctl")
    let absent = SimulatorToolDetection(devicesFolderExists: false, simctlPath: nil)
    static let simctlList = ["simctl", "list", "devices", "-j"]
    static let psArguments = ["-axww", "-o", "command="]
    static let big: UInt64 = 500_000_000

    struct AVD {
        let name: String
        let display: String
        /// Jours depuis la dernière utilisation (date de `emulator-user.ini`), `nil` : aucun fichier daté.
        let days: Double?
    }

    func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    /// Dossier personnel de bac à sable : un faux SDK (`Library/Android/sdk`) si `sdk`, et les AVD donnés.
    func home(_ avds: [AVD], sdk: Bool = true) throws -> Sandbox {
        let box = try Sandbox(insideHome: true)
        if sdk { try box.dir("Library/Android/sdk") }
        for avd in avds {
            try box.dir(".android/avd/\(avd.name).avd")
            try box.write(".android/avd/\(avd.name).ini", "path.rel=avd/\(avd.name).avd\n")
            try box.write(".android/avd/\(avd.name).avd/config.ini",
                          "avd.ini.displayname=\(avd.display)\nimage.sysdir.1=system-images/android-36/google_apis/arm64-v8a/\n")
            if let days = avd.days {
                let file = box.root.appendingPathComponent(".android/avd/\(avd.name).avd/emulator-user.ini")
                try Data(count: 3).write(to: file)
                try FileManager.default.setAttributes([.modificationDate: ago(days)], ofItemAtPath: file.path)
            }
        }
        return box
    }

    func runner(ios: [String] = [], ps: String = "", psOutcome: CommandOutcome? = nil) -> FakeCommandRunner {
        let fake = FakeCommandRunner()
        fake.script(.finished(stdout: SimulatorsModelTests.listJSON(ios)), executable: "/usr/bin/xcrun", arguments: Self.simctlList)
        fake.script(psOutcome ?? .finished(stdout: ps), executable: "/bin/ps", arguments: Self.psArguments)
        return fake
    }

    func model(_ runner: CommandRunner, home box: Sandbox, detection: SimulatorToolDetection? = nil, environment: [String: String] = [:],
               measure: ScriptedMeasure) -> SimulatorsModel {
        let detection = detection ?? present
        return SimulatorsModel(runner: runner, detect: { detection },
                               locateTool: { $0 == ToolLocator.processListCandidates ? "/bin/ps" : "/usr/bin/xcrun" },
                               environment: environment, home: box.root, now: { self.now },
                               measure: { measure.measure($0) }, demo: false, confirm: { _, _, _, _ in false },
                               deletionGate: SimulatorDeletionGate(), notify: { _ in })
    }

    func run(_ m: SimulatorsModel) async {
        m.scan()
        await m.scanTask?.value
    }

    let phone = AVD(name: "Test_Phone_A", display: "Test Phone A", days: 80)
    let tablet = AVD(name: "Test_Tablet_B", display: "Test Tablet B", days: 10)

    // MARK: Android caché : iOS comme avant

    @Test func withoutAnSdkTheAndroidGroupIsHiddenAndTheRunnerCallsAreTheIosOnes() async throws {
        let box = try home([phone], sdk: false)
        let fake = runner(ios: [Self.u1])
        let measure = ScriptedMeasure([Self.u1: Self.big])
        let m = model(fake, home: box, measure: measure)
        await run(m)
        #expect(m.androidPhase == .hidden)
        #expect(m.androidRows.isEmpty)
        #expect(m.phase == .listed)
        #expect(fake.calls.map(\.executable) == ["/usr/bin/xcrun"])
        #expect(fake.calls.first?.arguments == Self.simctlList)
        #expect(measure.calls == [Self.u1])
    }

    @Test func aMissingSdkRootHidesAndroidEvenWhenTheDefaultFolderExists() async throws {
        let box = try home([phone])   // le faux SDK par défaut existe
        let m = model(runner(ios: [Self.u1]), home: box, environment: ["ANDROID_SDK_ROOT": box.root.path + "/nonexistent"],
                      measure: ScriptedMeasure([:]))
        await run(m)
        #expect(m.androidPhase == .hidden)
        #expect(m.phase == .listed)
    }

    @Test func anSdkWithNoVirtualDeviceIsEmptyAndPsIsNotCalled() async throws {
        let box = try home([])
        let fake = runner(ios: [Self.u1])
        let m = model(fake, home: box, measure: ScriptedMeasure([:]))
        await run(m)
        #expect(m.androidPhase == .empty)
        #expect(fake.calls.map(\.executable) == ["/usr/bin/xcrun"])
    }

    // MARK: Appels et tailles dans l'ordre

    @Test func callsAreSimctlThenPsThenMeasuresIosFoldersThenAvdFoldersInDisplayOrder() async throws {
        let box = try home([tablet, phone])
        let fake = runner(ios: [Self.u1, Self.u2], ps: "/sbin/launchd\n")
        let measure = ScriptedMeasure([:])
        let m = model(fake, home: box, measure: measure)
        await run(m)
        #expect(fake.calls.map(\.executable) == ["/usr/bin/xcrun", "/bin/ps"])
        #expect(fake.calls[1].arguments == Self.psArguments)
        #expect(fake.calls[1].timeLimit == 10)
        #expect(fake.calls[1].outputLimit == 4 * 1024 * 1024)
        #expect(measure.calls == [Self.u1, Self.u2, "Test_Phone_A.avd", "Test_Tablet_B.avd"])
        #expect(m.androidPhase == .listed)
        #expect(!m.isMeasuring)
    }

    @Test func androidRowsAreListedBeforeTheirSizesAndSortedBySizeOnceKnown() async throws {
        let box = try home([phone, tablet])
        let measure = ScriptedMeasure(["Test_Phone_A.avd": 200_000_000, "Test_Tablet_B.avd": 900_000_000], gated: true)
        let m = model(runner(ps: ""), home: box, detection: absent, measure: measure)
        m.scan()
        await measure.started.wait()                     // la première mesure Android est en cours
        #expect(m.androidPhase == .listed)
        #expect(m.isMeasuring)
        #expect(m.androidRows.map(\.device.device.name) == ["Test_Phone_A", "Test_Tablet_B"], "ordre du listage pendant la mesure")
        #expect(m.androidRows.allSatisfy { m.size(of: $0) == nil })
        for _ in 0..<2 { measure.release.signal() }
        await m.scanTask?.value
        #expect(!m.isMeasuring)
        #expect(m.androidRows.map(\.device.device.name) == ["Test_Tablet_B", "Test_Phone_A"], "par taille décroissante")
        #expect(m.measuredSizeTotal == 1_100_000_000)
    }

    // MARK: Sélection

    @Test func anInactiveAvdIsPreSelectedAndARecentOneIsNot() async throws {
        let box = try home([phone, tablet])
        let m = model(runner(ps: ""), home: box, detection: absent, measure: ScriptedMeasure(["Test_Phone_A.avd": Self.big, "Test_Tablet_B.avd": Self.big]))
        await run(m)
        #expect(m.androidSelected == ["Test_Phone_A"])
        #expect(m.selectedCount == 1)
        #expect(m.selectedSize == Self.big)
    }

    @Test func aRunningAvdIsNeverSelectedAndToggleDoesNothing() async throws {
        let box = try home([phone, tablet])
        let m = model(runner(ps: "emulator -avd Test_Phone_A\n"), home: box, detection: absent,
                      measure: ScriptedMeasure(["Test_Phone_A.avd": Self.big, "Test_Tablet_B.avd": Self.big]))
        await run(m)
        let running = try #require(m.androidRows.first { $0.device.device.name == "Test_Phone_A" })
        #expect(running.isRunning)
        #expect(m.androidSelected.isEmpty, "l'AVD en cours d'exécution, inactif depuis 80 jours, n'est pas pré-sélectionné")
        m.toggle(running)
        #expect(m.androidSelected.isEmpty)
        let other = try #require(m.androidRows.first { $0.device.device.name == "Test_Tablet_B" })
        m.toggle(other)
        #expect(m.androidSelected == ["Test_Tablet_B"])
        m.toggle(other)
        #expect(m.androidSelected.isEmpty)
    }

    @Test func aLimitChangeRecomputesAndroidWithoutAnyRunnerCall() async throws {
        let fiftyFour = AVD(name: "Test_Phone_A", display: "Test Phone A", days: 54)
        let box = try home([fiftyFour])
        let fake = runner(ps: "")
        let m = model(fake, home: box, detection: absent, measure: ScriptedMeasure(["Test_Phone_A.avd": Self.big]))
        await run(m)
        #expect(m.androidSelected.isEmpty, "54 jours à la limite de 60 : listé, pas pré-sélectionné")
        #expect(m.androidRows.count == 1)
        let calls = fake.calls.count
        m.setLimit(30)
        #expect(m.androidSelected == ["Test_Phone_A"])
        m.setLimit(60)
        #expect(m.androidSelected.isEmpty)
        #expect(fake.calls.count == calls)
    }

    @Test func aSmallAvdLeavesTheListAndJoinsTheFooterCount() async throws {
        let box = try home([phone, tablet])
        let m = model(runner(ps: ""), home: box, detection: absent,
                      measure: ScriptedMeasure(["Test_Phone_A.avd": Self.big, "Test_Tablet_B.avd": 40_000_000]))
        await run(m)
        #expect(m.androidRows.map(\.device.device.name) == ["Test_Phone_A"])
        #expect(m.hiddenSmallCount == 1)
        #expect(m.hiddenSmallSize == 40_000_000)
    }

    @Test func theSharedTotalsAddBothGroups() async throws {
        let box = try home([phone])
        let m = model(runner(ios: [Self.u1], ps: ""), home: box,
                      measure: ScriptedMeasure([Self.u1: 700_000_000, "Test_Phone_A.avd": Self.big]))
        await run(m)
        #expect(m.rows.count == 1 && m.androidRows.count == 1)
        #expect(m.listedCount == 2)
        #expect(m.measuredSizeTotal == 1_200_000_000)
        // iOS : jamais utilisé (aucune date), donc rien de pré-sélectionné ; Android : 80 jours, pré-sélectionné.
        #expect(m.selectedCount == 1)
        #expect(m.selectedSize == Self.big)
        #expect(!m.showsNothingToSuggest)
    }

    @Test func nothingToSuggestNeedsAListedRowInEitherGroupAndNothingPreSelectedInBoth() async throws {
        let box = try home([tablet])
        let m = model(runner(ps: ""), home: box, detection: absent, measure: ScriptedMeasure(["Test_Tablet_B.avd": Self.big]))
        await run(m)
        #expect(m.showsNothingToSuggest, "une ligne Android listée, aucune pré-sélection nulle part")
        let none = try home([])
        let empty = model(runner(ps: ""), home: none, detection: absent, measure: ScriptedMeasure([:]))
        await run(empty)
        #expect(!empty.showsNothingToSuggest)
    }

    // MARK: Échec Android, iOS intact

    @Test func aTimedOutPsFailsAndroidWhileIosStaysListedAndUsable() async throws {
        let box = try home([phone])
        let m = model(runner(ios: [Self.u1], psOutcome: .timedOut), home: box, measure: ScriptedMeasure([Self.u1: Self.big]))
        await run(m)
        #expect(m.androidPhase == .failed(.couldNotRead))
        #expect(m.androidMessage == "Could not read the Android emulators.")
        #expect(m.androidRows.isEmpty)
        #expect(m.phase == .listed)
        #expect(m.rows.count == 1)
        #expect(m.canScanAgain)
        m.setLimit(30)
        let row = try #require(m.rows.first)
        m.toggle(row)
        #expect(m.selected == [Self.u1])
        #expect(m.canDelete)
    }

    // MARK: iOS caché

    @Test func withoutIosAndroidAloneIsListedAndSimctlIsNeverCalled() async throws {
        let box = try home([phone])
        let fake = runner(ps: "")
        let m = model(fake, home: box, detection: absent, measure: ScriptedMeasure(["Test_Phone_A.avd": Self.big]))
        await run(m)
        #expect(m.phase == .hidden)
        #expect(m.message == nil)
        #expect(m.androidPhase == .listed)
        #expect(fake.calls.map(\.executable) == ["/bin/ps"])
    }

    @Test func aDevicesFolderWithoutSimctlIsStillTheNeutralIosFailure() async throws {
        let box = try home([phone])
        let m = model(runner(ps: ""), home: box, detection: SimulatorToolDetection(devicesFolderExists: true, simctlPath: nil),
                      measure: ScriptedMeasure(["Test_Phone_A.avd": Self.big]))
        await run(m)
        #expect(m.phase == .failed(.couldNotRead))
        #expect(m.androidPhase == .listed)
    }

    // MARK: Suppression : iOS seulement

    @Test func deleteIsDisabledWhileAnAndroidRowIsCheckedAndEnabledOnceUnchecked() async throws {
        let box = try home([phone])
        let m = model(runner(ios: [Self.u1], ps: ""), home: box,
                      measure: ScriptedMeasure([Self.u1: Self.big, "Test_Phone_A.avd": Self.big]))
        await run(m)
        let ios = try #require(m.rows.first)
        m.toggle(ios)
        #expect(m.selected == [Self.u1])
        #expect(m.androidSelected == ["Test_Phone_A"], "l'AVD inactif est pré-sélectionné")
        #expect(!m.canDelete, "une ligne Android cochée désactive Delete")
        let android = try #require(m.androidRows.first)
        m.toggle(android)
        #expect(m.androidSelected.isEmpty)
        #expect(m.canDelete)
    }

    @Test(arguments: [
        (SimulatorsModel.Phase.listed, false, 1, false, 0, true),
        (.listed, false, 1, false, 1, false),
        (.listed, false, 0, false, 0, false),
        (.listed, true, 1, false, 0, false),
        (.listed, false, 1, true, 0, false),
        (.hidden, false, 0, false, 2, false),
    ])
    func theStaticRuleTakesTheAndroidSelectedCount(phase: SimulatorsModel.Phase, measuring: Bool, selected: Int, deleting: Bool,
                                                    android: Int, expected: Bool) {
        #expect(SimulatorsModel.canDelete(phase: phase, isMeasuring: measuring, selectedCount: selected, isDeleting: deleting,
                                          androidSelectedCount: android) == expected)
    }

    // MARK: Retour, nouveau scan

    @Test func backDuringTheAndroidMeasureAppliesNoAndroidSizeAfterwards() async throws {
        let box = try home([phone, tablet])
        let measure = ScriptedMeasure(["Test_Phone_A.avd": Self.big, "Test_Tablet_B.avd": Self.big], gated: true)
        let m = model(runner(ps: ""), home: box, detection: absent, measure: measure)
        m.scan()
        await measure.started.wait()
        m.cancel()
        for _ in 0..<2 { measure.release.signal() }
        await m.scanTask?.value
        #expect(m.androidPhase == .notScanned)
        #expect(m.androidRows.isEmpty)
        #expect(m.androidSelected.isEmpty)
        #expect(m.measuredSize(avd: "Test_Phone_A") == nil)
        #expect(measure.calls.count == 1, "aucune mesure Android de plus après Retour")
    }

    @Test func scanAgainIsUnavailableWhileAndroidIsListing() async throws {
        let box = try home([phone])
        let blocking = BlockingRunner(.finished(stdout: ""))
        let m = model(blocking, home: box, detection: absent, measure: ScriptedMeasure([:]))
        m.scan()
        await blocking.started.wait()                    // `ps` est en cours : Android liste
        #expect(m.androidPhase == .listing)
        #expect(!m.canScanAgain)
        blocking.release.signal()
        await m.scanTask?.value
        #expect(m.canScanAgain)
    }

    @Test func aSecondScanRelistsBothGroups() async throws {
        let box = try home([phone])
        let fake = runner(ios: [Self.u1], ps: "")
        let m = model(fake, home: box, measure: ScriptedMeasure([Self.u1: Self.big, "Test_Phone_A.avd": Self.big]))
        await run(m)
        await run(m)
        #expect(fake.calls.map(\.executable) == ["/usr/bin/xcrun", "/bin/ps", "/usr/bin/xcrun", "/bin/ps"])
        #expect(m.androidPhase == .listed)
    }

    @Test func androidMessageIsNilWhenNotFailed() async throws {
        let box = try home([phone])
        let m = model(runner(ps: ""), home: box, detection: absent, measure: ScriptedMeasure(["Test_Phone_A.avd": Self.big]))
        #expect(m.androidMessage == nil)
        await run(m)
        #expect(m.androidMessage == nil)
    }
}
