import Foundation
import Testing
@testable import Soaro

/// SL13 T4 (R10, D1, D2, ADR 0010) : les deux nettoyages, et rien d'autre. Aucun test ne lance un vrai `docker`.
@Suite struct DockerPruneTests {
    static let docker = "/usr/local/bin/docker"
    static let cacheArgs = ["builder", "prune", "-a", "-f"]
    static let imageArgs = ["image", "prune", "-f"]

    let runner = FakeCommandRunner()

    @Test func theBuildCachePruneIsExactlyBuilderPruneDashAF() {
        runner.script(.finished(stdout: "ID1\nID2\nTotal:\t22.46GB\n"), executable: Self.docker, arguments: Self.cacheArgs)
        let outcome = DockerScanner.prune(.buildCache, runner: runner, dockerPath: Self.docker)
        #expect(outcome == .pruned(reportedBytes: 22_460_000_000))
        #expect(runner.calls == [.init(executable: Self.docker, arguments: Self.cacheArgs, timeLimit: 300, outputLimit: 4 * 1024 * 1024)])
    }

    @Test func theUntaggedImagePruneIsExactlyImagePruneDashFWithoutDashA() {
        runner.script(.finished(stdout: "Deleted Images:\ndeleted: sha256:abc\n\nTotal reclaimed space: 397MB\n"),
                      executable: Self.docker, arguments: Self.imageArgs)
        let outcome = DockerScanner.prune(.untaggedImages, runner: runner, dockerPath: Self.docker)
        #expect(outcome == .pruned(reportedBytes: 397_000_000))
        #expect(runner.calls == [.init(executable: Self.docker, arguments: Self.imageArgs, timeLimit: 300, outputLimit: 4 * 1024 * 1024)])
    }

    @Test func eachPruneMapsToItsAllowlistedCommand() {
        #expect(DockerPrune.buildCache.command == .pruneBuildCache)
        #expect(DockerPrune.untaggedImages.command == .pruneUntaggedImages)
        #expect(DockerPrune.buildCache.command.isDestructive && DockerPrune.untaggedImages.command.isDestructive)
    }

    @Test func aSuccessWithoutAReadableTotalHasAnUnknownReportedFigure() {
        runner.script(.finished(stdout: "ID1\nID2\n"), executable: Self.docker, arguments: Self.cacheArgs)
        #expect(DockerScanner.prune(.buildCache, runner: runner, dockerPath: Self.docker) == .pruned(reportedBytes: nil))
    }

    @Test func aNonZeroCodeIsAFailureAndTheErrorOutputIsNotKept() {
        runner.script(.finished(exit: 1, stderr: "Error response from daemon: /Users/test-user/secret"),
                      executable: Self.docker, arguments: Self.cacheArgs)
        #expect(DockerScanner.prune(.buildCache, runner: runner, dockerPath: Self.docker) == .failed)
    }

    @Test func aSignalATruncatedOutputALaunchFailureAndARefusalAreFailures() {
        let cases: [CommandOutcome] = [
            .finished(exit: 9, termination: .signaled),
            .finished(exit: 0, stdout: "x", truncated: true),
            .finished(exit: 9, stdout: "x", truncated: true, termination: .signaled),
            .failedToLaunch,
            .refused(.shell),
        ]
        for outcome in cases {
            let fake = FakeCommandRunner()
            fake.script(outcome, executable: Self.docker, arguments: Self.imageArgs)
            #expect(DockerScanner.prune(.untaggedImages, runner: fake, dockerPath: Self.docker) == .failed, "\(outcome)")
        }
    }

    @Test func aTimeoutIsTimedOut() {
        runner.script(.timedOut, executable: Self.docker, arguments: Self.cacheArgs)
        #expect(DockerScanner.prune(.buildCache, runner: runner, dockerPath: Self.docker) == .timedOut)
    }

    @Test func withoutAnAbsoluteDockerPathNothingIsRun() {
        #expect(DockerScanner.prune(.buildCache, runner: runner, dockerPath: nil) == .toolNotFound)
        #expect(DockerScanner.prune(.untaggedImages, runner: runner, dockerPath: "docker") == .toolNotFound)
        #expect(DockerScanner.prune(.untaggedImages, runner: runner, dockerPath: "") == .toolNotFound)
        #expect(runner.calls.isEmpty)
    }

    @Test func aPruneNeverRunsAnythingElseNotEvenAListing() {
        runner.script(.finished(exit: 1), executable: Self.docker, arguments: Self.cacheArgs)
        _ = DockerScanner.prune(.buildCache, runner: runner, dockerPath: Self.docker)
        #expect(runner.calls.map(\.arguments) == [Self.cacheArgs])
    }
}
