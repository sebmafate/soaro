import Foundation
import Testing
@testable import Soaro

/// SL13 T3 (R10, R6, ADR 0009) : le listage de Docker, en lecture seule, par le lanceur. Aucun test ne lance un vrai `docker` :
/// le lanceur est le faux écrit à la main.
@Suite struct DockerScannerTests {
    static let docker = "/usr/local/bin/docker"
    static let usageArgs = DockerCommand.usage.arguments
    static let untaggedArgs = DockerCommand.untaggedImages.arguments

    let runner = FakeCommandRunner()
    /// SL16 : le moteur est lu avant l'usage.
    static let check: [[String]] = [DockerCommand.currentContext.arguments, DockerCommand.currentBuilder.arguments]

    init() { runner.scriptLocalEngine() }

    func script(usage: CommandOutcome, untagged: CommandOutcome? = nil) {
        runner.script(usage, executable: Self.docker, arguments: Self.usageArgs)
        if let untagged { runner.script(untagged, executable: Self.docker, arguments: Self.untaggedArgs) }
    }

    func allCallsAreAllowlistedAndReadOnly(sourceLocation: SourceLocation = #_sourceLocation) {
        for call in runner.calls {
            #expect(call.executable == Self.docker, sourceLocation: sourceLocation)
            #expect(DockerCommand.isAllowed(call.arguments), "\(call.arguments)", sourceLocation: sourceLocation)
            #expect(call.arguments != DockerCommand.pruneBuildCache.arguments && call.arguments != DockerCommand.pruneUntaggedImages.arguments,
                    "un listage ne nettoie jamais", sourceLocation: sourceLocation)
        }
    }

    // MARK: Cas nominal

    @Test func listingRunsTheEngineReadsThenTheTwoReadOnlyCommandsInOrderWithTheirLimits() {
        script(usage: .finished(stdout: DockerReportTests.realUsage),
               untagged: .finished(stdout: DockerReportTests.untagged(id: "aaaaaaaaaaaa", size: "397MB", containers: "0")))
        let scan = DockerScanner.list(runner: runner, dockerPath: Self.docker)
        #expect(scan.status == .ok)
        #expect(scan.usage?.buildCache?.size == 22_460_000_000)
        #expect(scan.untagged == [DockerUntaggedImage(id: "aaaaaaaaaaaa", size: 397_000_000, containerCount: 0)])
        let env = DockerCommand.removedEnvironment
        #expect(runner.calls.map(\.arguments) == Self.check + [Self.usageArgs, Self.untaggedArgs])
        #expect(Array(runner.calls.suffix(2)) == [
            .init(executable: Self.docker, arguments: Self.usageArgs, timeLimit: 30, outputLimit: 1024 * 1024, removedEnvironment: env),
            .init(executable: Self.docker, arguments: Self.untaggedArgs, timeLimit: 30, outputLimit: 1024 * 1024, removedEnvironment: env),
        ])
        allCallsAreAllowlistedAndReadOnly()
    }

    @Test func noUntaggedImageIsAnOkScanWithAnEmptyList() {
        script(usage: .finished(stdout: DockerReportTests.realUsage), untagged: .finished(stdout: ""))
        let scan = DockerScanner.list(runner: runner, dockerPath: Self.docker)
        #expect(scan.status == .ok)
        #expect(scan.untagged.isEmpty)
    }

    // MARK: docker absent

    @Test func withoutADockerPathNothingIsRun() {
        let scan = DockerScanner.list(runner: runner, dockerPath: nil)
        #expect(scan == DockerScan(status: .toolNotFound))
        #expect(runner.calls.isEmpty)
    }

    @Test func aDockerThatCannotBeLaunchedIsToolNotFoundAndNothingElseRuns() {
        script(usage: .failedToLaunch)
        #expect(DockerScanner.list(runner: runner, dockerPath: Self.docker).status == .toolNotFound)
        #expect(runner.calls.count == 3, "le moteur est lu, puis `docker system df` ne se lance pas : rien d'autre")
    }

    @Test func aRelativePathIsNeverHandedToTheRunner() {
        let scan = DockerScanner.list(runner: runner, dockerPath: "docker")
        #expect(scan.status == .toolNotFound)
        #expect(runner.calls.isEmpty)
    }

    // MARK: Moteur arrêté ou muet

    @Test func aStoppedEngineIsReportedAndNothingElseRuns() {
        // Sortie d'erreur réelle d'un moteur arrêté : elle contient un chemin personnel, elle n'est ni lue ni gardée.
        script(usage: .finished(exit: 1, stderr: "Cannot connect to the Docker daemon at unix:///Users/test-user/.docker/run/docker.sock. Is the docker daemon running?"))
        let scan = DockerScanner.list(runner: runner, dockerPath: Self.docker)
        #expect(scan == DockerScan(status: .engineNotRunning))
        #expect(runner.calls.map(\.arguments) == Self.check + [Self.usageArgs], "la seconde lecture n'a pas lieu")
        allCallsAreAllowlistedAndReadOnly()
    }

    @Test func aSecondCommandThatFailsFailsTheWholeScanWithoutUsage() {
        script(usage: .finished(stdout: DockerReportTests.realUsage), untagged: .finished(exit: 1))
        let scan = DockerScanner.list(runner: runner, dockerPath: Self.docker)
        #expect(scan == DockerScan(status: .engineNotRunning), "jamais un usage partiel")
    }

    @Test func aTimeoutIsTimedOutOnEitherCommand() {
        script(usage: .timedOut)
        #expect(DockerScanner.list(runner: runner, dockerPath: Self.docker) == DockerScan(status: .timedOut))
        #expect(runner.calls.count == 3)

        let second = FakeCommandRunner()
        second.scriptLocalEngine()
        second.script(.finished(stdout: DockerReportTests.realUsage), executable: Self.docker, arguments: Self.usageArgs)
        second.script(.timedOut, executable: Self.docker, arguments: Self.untaggedArgs)
        #expect(DockerScanner.list(runner: second, dockerPath: Self.docker) == DockerScan(status: .timedOut))
    }

    @Test func aProcessEndedBySignalOrRefusedByTheRunnerIsNotRunning() {
        script(usage: .finished(exit: 9, termination: .signaled))
        #expect(DockerScanner.list(runner: runner, dockerPath: Self.docker).status == .engineNotRunning)
        let refusing = FakeCommandRunner()
        refusing.scriptLocalEngine()
        refusing.script(.refused(.shell), executable: Self.docker, arguments: Self.usageArgs)
        #expect(DockerScanner.list(runner: refusing, dockerPath: Self.docker).status == .engineNotRunning)
    }

    // MARK: Sortie illisible

    @Test func aTruncatedOutputIsNotReadableWhateverTheCode() {
        script(usage: .finished(exit: 9, stdout: DockerReportTests.realUsage, truncated: true, termination: .signaled))
        #expect(DockerScanner.list(runner: runner, dockerPath: Self.docker).status == .outputNotReadable)
    }

    @Test func garbageOnStandardOutputWithCodeZeroIsNotReadable() {
        script(usage: .finished(stdout: "Server: not what you expect"))
        #expect(DockerScanner.list(runner: runner, dockerPath: Self.docker) == DockerScan(status: .outputNotReadable))

        let second = FakeCommandRunner()
        second.scriptLocalEngine()
        second.script(.finished(stdout: DockerReportTests.realUsage), executable: Self.docker, arguments: Self.usageArgs)
        second.script(.finished(stdout: "Server: not what you expect"), executable: Self.docker, arguments: Self.untaggedArgs)
        #expect(DockerScanner.list(runner: second, dockerPath: Self.docker) == DockerScan(status: .outputNotReadable))
    }

    @Test func aTruncatedUntaggedListIsNotReadable() {
        script(usage: .finished(stdout: DockerReportTests.realUsage),
               untagged: .finished(exit: 9, stdout: DockerReportTests.untagged(), truncated: true, termination: .signaled))
        #expect(DockerScanner.list(runner: runner, dockerPath: Self.docker).status == .outputNotReadable)
    }
}
