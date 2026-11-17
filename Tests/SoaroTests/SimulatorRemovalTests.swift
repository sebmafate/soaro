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
