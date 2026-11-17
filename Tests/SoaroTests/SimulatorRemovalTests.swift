import Foundation
import Testing
@testable import Soaro

/// Suppression d'un simulateur : une seule commande, `xcrun simctl delete <udid>` (SL9 T2).
@Suite(.serialized) struct SimulatorRemovalTests {
    static let udid = "00000000-0000-4000-8000-000000000001"
    static let xcrun = "/usr/bin/xcrun"
    static let args = ["simctl", "delete", udid]

    func fake(_ outcome: CommandOutcome) -> FakeCommandRunner {
        let fake = FakeCommandRunner()
        fake.script(outcome, executable: Self.xcrun, arguments: Self.args)
        return fake
    }

    @Test func theRunnerReceivesExactlyTheDeleteCommandWithItsLimits() {
        let runner = fake(.finished())
        let result = SimulatorScanner.delete(runner: runner, xcrunPath: Self.xcrun, udid: Self.udid)
        #expect(result == .removed)
        #expect(runner.calls == [.init(executable: "/usr/bin/xcrun",
                                       arguments: ["simctl", "delete", "00000000-0000-4000-8000-000000000001"],
                                       timeLimit: 60, outputLimit: 1_048_576)])
    }

    @Test func theDeleteValuesAreTheOnlyOnesInTheCode() {
        #expect(SimulatorScanner.deleteTimeLimit == 60)
        #expect(SimulatorScanner.deleteOutputLimit == 1024 * 1024)
        #expect(SimulatorScanner.deleteArguments(udid: Self.udid) == Self.args)
    }

    @Test(arguments: [
        ("exit 0", CommandOutcome.finished(), SimulatorDeleteOutcome.removed),
        ("exit 0 with a message on stdout", .finished(stdout: "done"), .removed),
        ("exit 1", .finished(exit: 1), .failed),
        ("exit 72", .finished(exit: 72, stderr: "boom /Users/someone/secret"), .failed),
        ("signalled, number 0", .finished(exit: 0, termination: .signaled), .failed),
        ("signalled, number 9", .finished(exit: 9, termination: .signaled), .failed),
        ("truncated output, exit 0", .finished(exit: 0, stdout: "xxxx", truncated: true), .failed),
        ("truncated output, signalled", .finished(exit: 9, truncated: true, termination: .signaled), .failed),
        ("timed out", .timedOut, .timedOut),
        ("failed to launch", .failedToLaunch, .failed),
        ("refused: not absolute", .refused(.notAbsolutePath), .failed),
        ("refused: shell", .refused(.shell), .failed),
    ])
    func eachRunnerOutcomeMapsToOneRemovalOutcome(label: String, outcome: CommandOutcome, expected: SimulatorDeleteOutcome) {
        let result = SimulatorScanner.delete(runner: fake(outcome), xcrunPath: Self.xcrun, udid: Self.udid)
        #expect(result == expected, "\(label)")
    }

    @Test(arguments: ["../x", "", "not-a-uuid", "00000000-0000-4000-8000-00000000000", "../../00000000-0000-4000-8000-000000000001",
                      "00000000-0000-4000-8000-000000000001 ", "00000000-0000-4000-8000-000000000001\n", "-all", "all"])
    func anInvalidUDIDLaunchesNothing(udid: String) {
        let runner = FakeCommandRunner()           // un appel non prévu ferait échouer le test
        let result = SimulatorScanner.delete(runner: runner, xcrunPath: Self.xcrun, udid: udid)
        #expect(result == .failed)
        #expect(runner.calls.isEmpty)
    }

    @Test func aMissingXcrunPathLaunchesNothing() {
        let runner = FakeCommandRunner()
        #expect(SimulatorScanner.delete(runner: runner, xcrunPath: nil, udid: Self.udid) == .toolNotFound)
        #expect(runner.calls.isEmpty)
    }

    @Test func theCommandIsAlwaysOneUDIDAndNeverAShell() {
        let runner = fake(.finished())
        _ = SimulatorScanner.delete(runner: runner, xcrunPath: Self.xcrun, udid: Self.udid)
        let call = runner.calls[0]
        #expect(call.executable.hasPrefix("/"))
        #expect(call.arguments.count == 3)
        #expect(!call.arguments.contains { $0.contains(" ") })
    }

    // MARK: Règle de sources (R4, ADR 0009 règle 8)

    @Test func noSimulatorSourceDeletesAFolderByHand() throws {
        let folder = RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Cleanup")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("Simulator") && $0.pathExtension == "swift" }
        #expect(files.count >= 5, "les fichiers des simulateurs sont bien trouvés")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for forbidden in ["removeItem(", "trashItem(", "\"/bin/rm\""] {
                #expect(!text.contains(forbidden), "\(forbidden) ne doit pas apparaître dans \(file.lastPathComponent)")
            }
        }
    }
}

/// Mesure scriptée qui rend les tailles dans l'ordre (la dernière se répète) et note chaque dossier demandé,
/// avec le nombre d'appels déjà faits au lanceur à ce moment-là (pour vérifier l'ordre « avant, suppression, après »).
final class MeasureSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var sizes: [UInt64]
    private var recorded: [URL] = []
    private var runnerCalls: [Int] = []
    private let runnerCallCount: () -> Int

    init(_ sizes: [UInt64], runnerCallCount: @escaping () -> Int = { 0 }) {
        self.sizes = sizes
        self.runnerCallCount = runnerCallCount
    }

    var folders: [URL] { lock.lock(); defer { lock.unlock() }; return recorded }
    var callCountsOfTheRunner: [Int] { lock.lock(); defer { lock.unlock() }; return runnerCalls }
    var count: Int { folders.count }

    func measure(_ folder: URL) -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        let index = recorded.count
        recorded.append(folder)
        runnerCalls.append(runnerCallCount())
        return sizes[min(index, sizes.count - 1)]
    }
}

/// Suppression d'un appareil après vérifications (SL9 T3) : état revérifié, dossier du dossier personnel seulement,
/// mesure avant et après.
@Suite(.serialized) struct SimulatorRemovalOneDeviceTests {
    static let udid = "00000000-0000-4000-8000-000000000001"
    static let other = "00000000-0000-4000-8000-000000000002"
    static let xcrun = "/usr/bin/xcrun"
    static let listArgs = ["simctl", "list", "devices", "-j"]
    static let deleteArgs = ["simctl", "delete", udid]
    static let gigabyte: UInt64 = 1_000_000_000

    /// Sortie de `simctl list` : un appareil par couple (udid, nom, état) ; `state` nil : pas de clé d'état.
    static func listJSON(_ devices: [(udid: String, name: String, state: String?)]) -> String {
        let entries = devices.map { device -> String in
            let state = device.state.map { ", \"state\": \"\($0)\"" } ?? ""
            return "{\"udid\": \"\(device.udid)\", \"name\": \"\(device.name)\"\(state)}"
        }
        return "{\"devices\": {\"com.apple.CoreSimulator.SimRuntime.iOS-26-2\": [\(entries.joined(separator: ","))]}}"
    }

    static func list(state: String? = "Shutdown", name: String = "iPhone 15") -> CommandOutcome {
        .finished(stdout: listJSON([(udid, name, state)]))
    }

    func fake(list: CommandOutcome = SimulatorRemovalOneDeviceTests.list(), delete: CommandOutcome = .finished()) -> FakeCommandRunner {
        let fake = FakeCommandRunner()
        fake.script(list, executable: Self.xcrun, arguments: Self.listArgs)
        fake.script(delete, executable: Self.xcrun, arguments: Self.deleteArgs)
        return fake
    }

    func deleteCalls(_ runner: FakeCommandRunner) -> [FakeCommandRunner.Call] {
        runner.calls.filter { $0.arguments.contains("delete") }
    }

    func remove(_ runner: FakeCommandRunner, home: URL, measure: MeasureSequence, xcrun: String? = Self.xcrun) -> SimulatorRemovalResult {
        SimulatorScanner.remove(runner: runner, xcrunPath: xcrun, home: home, measure: { measure.measure($0) }, udid: Self.udid)
    }

    // MARK: Chemin normal

    @Test func happyPathListsThenDeletesAndFreesTheMeasuredDifference() throws {
        let box = try Sandbox(insideHome: true)
        let runner = fake()
        let measure = MeasureSequence([5 * Self.gigabyte, 0], runnerCallCount: { runner.calls.count })

        let result = remove(runner, home: box.root, measure: measure)

        #expect(result == .removed(freed: 5 * Self.gigabyte))
        #expect(runner.calls.map(\.arguments) == [Self.listArgs, Self.deleteArgs])
        #expect(runner.calls.allSatisfy { $0.executable == "/usr/bin/xcrun" })
        // Même commande et mêmes bornes que SL8 pour la liste, 60 s et 1 Mio pour la suppression.
        #expect(runner.calls[0].timeLimit == 60 && runner.calls[0].outputLimit == 8 * 1024 * 1024)
        #expect(runner.calls[1].timeLimit == 60 && runner.calls[1].outputLimit == 1024 * 1024)
        // Mesure avant (après la liste, avant la suppression), puis après la suppression ; toujours le dossier de l'appareil.
        let expected = box.root.appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(Self.udid)", isDirectory: true)
        #expect(measure.folders.map(\.path) == [expected.path, expected.path])
        #expect(measure.callCountsOfTheRunner == [1, 2])
    }

    @Test func theFolderIsNeverTouchedWhenTheToolRemovesTheDevice() throws {
        // Le faux outil ne supprime rien : le dossier réel doit rester (le code n'efface jamais à la main).
        let box = try Sandbox(insideHome: true)
        try box.file("Library/Developer/CoreSimulator/Devices/\(Self.udid)/data/file.bin")
        let runner = fake()
        _ = remove(runner, home: box.root, measure: MeasureSequence([10, 0]))
        #expect(box.exists("Library/Developer/CoreSimulator/Devices/\(Self.udid)/data/file.bin"))
    }

    // MARK: Appareil en cours d'exécution (R5)

    @Test func aDeviceBootedAfterTheScanIsRefusedWithItsNameAndNothingIsMeasured() throws {
        let box = try Sandbox(insideHome: true)
        let runner = fake(list: Self.list(state: "Booted", name: "Café “Pro” 15"))
        let measure = MeasureSequence([Self.gigabyte])

        let result = remove(runner, home: box.root, measure: measure)

        #expect(result == .running(name: "Café “Pro” 15"), "le nom est celui de la liste fraîche, tel quel")
        #expect(deleteCalls(runner).isEmpty)
        #expect(measure.count == 0)
    }

    @Test(arguments: (["Booted", "Booting", "Shutting Down", "Creating", "SHUTDOWN", "shutdown", "", "Unknown"] as [String?]) + [nil])
    func anyStateOtherThanShutdownCountsAsRunning(state: String?) throws {
        let box = try Sandbox(insideHome: true)
        let runner = fake(list: Self.list(state: state))
        let measure = MeasureSequence([Self.gigabyte])

        let result = remove(runner, home: box.root, measure: measure)

        #expect(result == .running(name: "iPhone 15"), "état \(state ?? "absent")")
        #expect(deleteCalls(runner).isEmpty)
        #expect(measure.count == 0)
    }

    // MARK: Déjà disparu, liste impossible

    @Test func aDeviceMissingFromTheFreshListIsAlreadyGoneAndNothingIsDeleted() throws {
        let box = try Sandbox(insideHome: true)
        let runner = fake(list: .finished(stdout: Self.listJSON([(Self.other, "iPad", "Shutdown")])))
        let measure = MeasureSequence([Self.gigabyte])

        #expect(remove(runner, home: box.root, measure: measure) == .alreadyGone)
        #expect(deleteCalls(runner).isEmpty)
        #expect(measure.count == 0)
    }

    @Test func aTimedOutRecheckStopsWithoutDeleting() throws {
        let box = try Sandbox(insideHome: true)
        let runner = fake(list: .timedOut)
        #expect(remove(runner, home: box.root, measure: MeasureSequence([1])) == .timedOut)
        #expect(deleteCalls(runner).isEmpty)
    }

    @Test(arguments: [
        ("non-zero exit", CommandOutcome.finished(exit: 1)),
        ("failed to launch", .failedToLaunch),
        ("refused", .refused(.shell)),
        ("signalled", .finished(exit: 11, termination: .signaled)),
        ("truncated", .finished(stdout: "{\"devices\":", truncated: true)),
        ("malformed", .finished(stdout: "not json")),
    ])
    func anyOtherRecheckFailureMeansCouldNotCheckAndNothingIsDeleted(label: String, outcome: CommandOutcome) throws {
        let box = try Sandbox(insideHome: true)
        let runner = fake(list: outcome)
        let measure = MeasureSequence([1])
        #expect(remove(runner, home: box.root, measure: measure) == .couldNotCheck, "\(label)")
        #expect(deleteCalls(runner).isEmpty, "\(label)")
        #expect(measure.count == 0, "\(label)")
    }

    @Test func aMissingXcrunPathCouldNotCheckAndLaunchesNothing() throws {
        let box = try Sandbox(insideHome: true)
        let runner = FakeCommandRunner()
        #expect(remove(runner, home: box.root, measure: MeasureSequence([1]), xcrun: nil) == .couldNotCheck)
        #expect(runner.calls.isEmpty)
    }

    // MARK: Portée (ADR 0006)

    @Test func aHomeOutsideTheRealHomeIsRefusedAndNoDeleteIsLaunched() {
        let runner = fake()
        let measure = MeasureSequence([Self.gigabyte])

        let result = remove(runner, home: URL(fileURLWithPath: "/Users/test"), measure: measure)

        #expect(result == .refused)
        #expect(deleteCalls(runner).isEmpty)
        #expect(measure.count == 0)
    }

    @Test func aHomeAtTheRootOfTheDiskIsRefused() {
        let runner = fake()
        let result = remove(runner, home: URL(fileURLWithPath: "/"), measure: MeasureSequence([1]))
        #expect(result == .refused)
        #expect(deleteCalls(runner).isEmpty)
    }

    // MARK: Échec de l'outil : jamais de repli

    @Test func aFailingDeleteIsReportedAndTheRealFolderStays() throws {
        let box = try Sandbox(insideHome: true)
        try box.file("Library/Developer/CoreSimulator/Devices/\(Self.udid)/data/file.bin")
        let runner = fake(delete: .finished(exit: 1, stderr: "boom /Users/someone/secret"))
        let measure = MeasureSequence([Self.gigabyte])

        #expect(remove(runner, home: box.root, measure: measure) == .failed)

        #expect(deleteCalls(runner).count == 1)
        #expect(measure.count == 1, "seule la mesure d'avant : rien n'est mesuré après un échec")
        #expect(box.exists("Library/Developer/CoreSimulator/Devices/\(Self.udid)"))
        #expect(box.exists("Library/Developer/CoreSimulator/Devices/\(Self.udid)/data/file.bin"))
    }

    @Test func aDeleteTimeoutIsPassedThrough() throws {
        let box = try Sandbox(insideHome: true)
        let runner = fake(delete: .timedOut)
        let measure = MeasureSequence([Self.gigabyte])
        #expect(remove(runner, home: box.root, measure: measure) == .timedOut)
        #expect(measure.count == 1)
    }

    @Test(arguments: [CommandOutcome.failedToLaunch, .refused(.shell), .finished(exit: 9, termination: .signaled),
                      .finished(stdout: "x", truncated: true)])
    func everyOtherDeleteFailureIsFailed(outcome: CommandOutcome) throws {
        let box = try Sandbox(insideHome: true)
        #expect(remove(fake(delete: outcome), home: box.root, measure: MeasureSequence([1])) == .failed)
    }

    // MARK: Espace réellement libéré (R7)

    @Test func aFolderThatStillHoldsDataAfterwardsFreesOnlyTheDifference() throws {
        let box = try Sandbox(insideHome: true)
        let measure = MeasureSequence([5 * Self.gigabyte, Self.gigabyte])
        #expect(remove(fake(), home: box.root, measure: measure) == .removed(freed: 4 * Self.gigabyte))
    }

    @Test func anAfterLargerThanBeforeFreesNothing() throws {
        let box = try Sandbox(insideHome: true)
        let measure = MeasureSequence([Self.gigabyte, 3 * Self.gigabyte])
        #expect(remove(fake(), home: box.root, measure: measure) == .removed(freed: 0))
    }
}
