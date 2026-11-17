import Foundation
import Testing
@testable import Soaro

@Suite struct CommandRunnerFakeTests {
    @Test func returnsTheScriptedOutcomePerCommand() {
        let fake = FakeCommandRunner()
        fake.script(.finished(stdout: "un"), executable: "/usr/bin/one", arguments: ["a"])
        fake.script(.timedOut, executable: "/usr/bin/two", arguments: [])
        fake.script(.refused(.notAbsolutePath), executable: "relative", arguments: [])

        #expect(fake.run(executable: "/usr/bin/one", arguments: ["a"], timeLimit: 1, outputLimit: 10) == .finished(stdout: "un"))
        #expect(fake.run(executable: "/usr/bin/two", arguments: [], timeLimit: 1, outputLimit: 10) == .timedOut)
        #expect(fake.run(executable: "relative", arguments: [], timeLimit: 1, outputLimit: 10) == .refused(.notAbsolutePath))
    }

    @Test func recordsEveryCallInOrderWithItsLimits() {
        let fake = FakeCommandRunner()
        fake.script(.finished(), executable: "/usr/bin/one", arguments: ["a", "b"])
        fake.script(.finished(), executable: "/usr/bin/two", arguments: [])

        _ = fake.run(executable: "/usr/bin/one", arguments: ["a", "b"], timeLimit: 60, outputLimit: 8_000_000)
        _ = fake.run(executable: "/usr/bin/two", arguments: [], timeLimit: 5, outputLimit: 100)

        #expect(fake.calls == [
            .init(executable: "/usr/bin/one", arguments: ["a", "b"], timeLimit: 60, outputLimit: 8_000_000),
            .init(executable: "/usr/bin/two", arguments: [], timeLimit: 5, outputLimit: 100),
        ])
        #expect(fake.unscriptedCalls.isEmpty)
    }

    @Test func anUnscriptedCallIsReportedAndNeverLaunchesAnything() {
        let fake = FakeCommandRunner()
        var reports: [String] = []
        fake.reportUnscripted = { reports.append($0) }

        let outcome = fake.run(executable: "/usr/bin/unknown", arguments: ["x"], timeLimit: 1, outputLimit: 1)

        #expect(outcome == .failedToLaunch)
        #expect(reports == ["/usr/bin/unknown x"])
        #expect(fake.unscriptedCalls.count == 1)
        #expect(fake.calls.count == 1)
    }

    @Test func sameExecutableWithOtherArgumentsIsNotScripted() {
        let fake = FakeCommandRunner()
        fake.script(.finished(), executable: "/usr/bin/one", arguments: ["a"])
        fake.reportUnscripted = { _ in }
        #expect(fake.run(executable: "/usr/bin/one", arguments: ["b"], timeLimit: 1, outputLimit: 1) == .failedToLaunch)
        #expect(fake.unscriptedCalls.count == 1)
    }

    // MARK: Résultats successifs (SL9 T1)

    @Test func aSequenceReturnsEachOutcomeInOrderThenRepeatsTheLastOne() {
        let fake = FakeCommandRunner()
        fake.script(sequence: [.finished(stdout: "1"), .finished(stdout: "2"), .finished(stdout: "3")],
                    executable: "/usr/bin/one", arguments: ["a"])

        let results = (0..<4).map { _ in fake.run(executable: "/usr/bin/one", arguments: ["a"], timeLimit: 1, outputLimit: 10) }

        #expect(results == [.finished(stdout: "1"), .finished(stdout: "2"), .finished(stdout: "3"), .finished(stdout: "3")])
        #expect(fake.calls.count == 4)
        #expect(fake.unscriptedCalls.isEmpty)
    }

    @Test func eachCommandHasItsOwnSequenceAndTheCallsAreRecordedInOrder() {
        let fake = FakeCommandRunner()
        fake.script(sequence: [.finished(stdout: "a1"), .timedOut], executable: "/usr/bin/one", arguments: [])
        fake.script(sequence: [.finished(stdout: "b1"), .finished(stdout: "b2")], executable: "/usr/bin/two", arguments: [])

        #expect(fake.run(executable: "/usr/bin/one", arguments: [], timeLimit: 1, outputLimit: 1) == .finished(stdout: "a1"))
        #expect(fake.run(executable: "/usr/bin/two", arguments: [], timeLimit: 2, outputLimit: 2) == .finished(stdout: "b1"))
        #expect(fake.run(executable: "/usr/bin/one", arguments: [], timeLimit: 3, outputLimit: 3) == .timedOut)
        #expect(fake.run(executable: "/usr/bin/two", arguments: [], timeLimit: 4, outputLimit: 4) == .finished(stdout: "b2"))

        #expect(fake.calls.map(\.executable) == ["/usr/bin/one", "/usr/bin/two", "/usr/bin/one", "/usr/bin/two"])
        #expect(fake.calls.map(\.timeLimit) == [1, 2, 3, 4])
    }

    @Test func aSingleScriptStillRepeatsAndScriptingAgainReplacesTheSequence() {
        let fake = FakeCommandRunner()
        fake.script(.finished(stdout: "x"), executable: "/usr/bin/one", arguments: [])
        #expect(fake.run(executable: "/usr/bin/one", arguments: [], timeLimit: 1, outputLimit: 1) == .finished(stdout: "x"))
        #expect(fake.run(executable: "/usr/bin/one", arguments: [], timeLimit: 1, outputLimit: 1) == .finished(stdout: "x"))

        fake.script(sequence: [.finished(stdout: "1"), .finished(stdout: "2")], executable: "/usr/bin/one", arguments: [])
        fake.script(.timedOut, executable: "/usr/bin/one", arguments: [])
        #expect(fake.run(executable: "/usr/bin/one", arguments: [], timeLimit: 1, outputLimit: 1) == .timedOut)
        #expect(fake.run(executable: "/usr/bin/one", arguments: [], timeLimit: 1, outputLimit: 1) == .timedOut)
    }

    @Test func anUnscriptedCallIsStillReportedWhenOtherCommandsHaveSequences() {
        let fake = FakeCommandRunner()
        fake.script(sequence: [.finished(), .timedOut], executable: "/usr/bin/one", arguments: [])
        var reports: [String] = []
        fake.reportUnscripted = { reports.append($0) }

        #expect(fake.run(executable: "/usr/bin/two", arguments: ["x"], timeLimit: 1, outputLimit: 1) == .failedToLaunch)
        #expect(reports == ["/usr/bin/two x"])
        #expect(fake.unscriptedCalls.count == 1)
    }
}
