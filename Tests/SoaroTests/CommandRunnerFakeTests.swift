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
}
