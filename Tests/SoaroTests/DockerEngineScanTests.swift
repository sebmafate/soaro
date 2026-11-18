import Foundation
import Testing
@testable import Soaro

extension FakeCommandRunner {
    /// SL16 : script du moteur LOCAL de Docker Desktop (sorties réelles anonymisées de `DockerEngineReportTests`). `context` et `builder` peuvent être
    /// des suites : un appel rend le résultat suivant (le moteur change entre le listage et le nettoyage).
    func scriptLocalEngine(docker: String = DockerEngineScanTests.docker,
                           context: [CommandOutcome] = [.finished(stdout: DockerEngineReportTests.desktopContext)],
                           builder: [CommandOutcome] = [.finished(stdout: DockerEngineReportTests.runningBuilder())]) {
        script(sequence: context, executable: docker, arguments: DockerCommand.currentContext.arguments)
        script(sequence: builder, executable: docker, arguments: DockerCommand.currentBuilder.arguments)
    }
}

/// SL16 T3 (R9, R10) : Soaro ne liste et ne nettoie que le Docker de CE Mac. Avant tout listage et juste avant chaque nettoyage, le contexte
/// et le constructeur courants sont lus ; si le moteur n'est pas clairement local, rien d'autre ne tourne. Faux lanceur : aucun vrai `docker`.
@Suite struct DockerEngineScanTests {
    static let docker = "/usr/local/bin/docker"
    static let engine = DockerEngine(contextName: "desktop-linux", socketPath: "/Users/test/.docker/run/docker.sock")
    static let contextArgs = DockerCommand.currentContext.arguments
    static let builderArgs = DockerCommand.currentBuilder.arguments
    static let usageArgs = DockerCommand.usage.arguments
    static let untaggedArgs = DockerCommand.untaggedImages.arguments
    static let cacheArgs = DockerCommand.pruneBuildCache.arguments
    static let imageArgs = DockerCommand.pruneUntaggedImages.arguments

    let runner = FakeCommandRunner()

    func scriptListing() {
        runner.script(.finished(stdout: DockerReportTests.realUsage), executable: Self.docker, arguments: Self.usageArgs)
        runner.script(.finished(stdout: ""), executable: Self.docker, arguments: Self.untaggedArgs)
    }

    func scriptPrunes() {
        runner.script(.finished(stdout: "ID1\nTotal:\t22.46GB\n"), executable: Self.docker, arguments: Self.cacheArgs)
        runner.script(.finished(stdout: "Total reclaimed space: 397MB\n"), executable: Self.docker, arguments: Self.imageArgs)
    }

    func list() -> DockerScan { DockerScanner.list(runner: runner, dockerPath: Self.docker) }
    func args() -> [[String]] { runner.calls.map(\.arguments) }

    static func contextOutcome(_ host: String, name: String = "default") -> CommandOutcome {
        .finished(stdout: DockerEngineReportTests.contextWithHost(host, name: name))
    }

    // MARK: Listage : le moteur est lu AVANT l'usage

    @Test func aLocalEngineIsCheckedBeforeTheUsageIsListedAndTheScanCarriesTheEngine() {
        runner.scriptLocalEngine(); scriptListing()
        let scan = list()
        #expect(scan.status == .ok)
        #expect(scan.engine == Self.engine)
        #expect(args() == [Self.contextArgs, Self.builderArgs, Self.usageArgs, Self.untaggedArgs])
        #expect(runner.calls.allSatisfy { $0.executable == Self.docker && DockerCommand.isAllowed($0.arguments) })
    }

    @Test func everyDockerCallRemovesTheFiveEnvironmentVariablesThatSelectAnEngineOrABuilder() {
        runner.scriptLocalEngine(); scriptListing(); scriptPrunes()
        _ = list()
        _ = DockerScanner.prune(.buildCache, runner: runner, dockerPath: Self.docker, expectedEngine: Self.engine)
        _ = DockerScanner.prune(.untaggedImages, runner: runner, dockerPath: Self.docker, expectedEngine: Self.engine)
        #expect(runner.calls.count == 4 + 3 + 3)
        let wanted = ["DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_CERT_PATH", "DOCKER_TLS_VERIFY", "BUILDX_BUILDER"]
        for call in runner.calls { #expect(call.removedEnvironment == wanted, "\(call.arguments)") }
    }

    @Test(arguments: ["tcp://10.0.0.5:2376", "tcp://build.example.invalid:2375", "ssh://user@build.example.invalid", "npipe:////./pipe/docker_engine", ""])
    func aRemoteContextIsRefusedAndNothingElseRuns(host: String) {
        runner.script(Self.contextOutcome(host), executable: Self.docker, arguments: Self.contextArgs)
        let scan = list()
        #expect(scan == DockerScan(status: .notLocal))
        #expect(args() == [Self.contextArgs], "ni constructeur, ni usage, ni images")
    }

    @Test func theRealRemoteContextMadeByDockerHostIsRefused() {
        // Sortie réelle de `docker context inspect` avec DOCKER_HOST=ssh://… dans l'environnement : exactement la fuite que le retrait des variables ferme,
        // et que cette lecture refuserait encore si une variable passait.
        runner.script(.finished(stdout: DockerEngineReportTests.contextWithHost("ssh://user@build.example.invalid")), executable: Self.docker, arguments: Self.contextArgs)
        #expect(list().status == .notLocal)
    }

    @Test(arguments: ["docker-container", "kubernetes", "remote", "cloud"])
    func aBuilderWithAnotherDriverIsRefusedAfterTheContextAndBeforeTheUsage(driver: String) {
        runner.scriptLocalEngine(builder: [.finished(stdout: DockerEngineReportTests.runningBuilder(name: "shared", driver: driver, endpoint: "ssh://user@build.example.invalid"))])
        scriptListing()
        let scan = list()
        #expect(scan == DockerScan(status: .notLocal))
        #expect(args() == [Self.contextArgs, Self.builderArgs])
    }

    @Test func aStoppedLocalEngineStillSaysDockerIsNotRunningAndLaunchesNothingElse() {
        // Sortie réelle moteur arrêté : le contexte est lisible (fichiers), le constructeur a un pilote vide et une erreur.
        runner.scriptLocalEngine(builder: [.finished(stdout: DockerEngineReportTests.stoppedEngineBuilder)])
        scriptListing()
        #expect(list() == DockerScan(status: .engineNotRunning))
        #expect(args() == [Self.contextArgs, Self.builderArgs])
    }

    @Test func unreadableAnswersFailClosedWhateverTheWay() {
        let broken: [CommandOutcome] = [
            .finished(stdout: ""), .finished(stdout: "garbage"), .finished(exit: 1, stderr: "boom"), .finished(exit: 9, termination: .signaled),
            .finished(stdout: DockerEngineReportTests.desktopContext, truncated: true), .refused(.shell),
        ]
        for outcome in broken {
            // contexte illisible : rien d'autre ne tourne
            let one = FakeCommandRunner()
            one.script(outcome, executable: Self.docker, arguments: Self.contextArgs)
            #expect(DockerScanner.list(runner: one, dockerPath: Self.docker) == DockerScan(status: .notLocal), "contexte \(outcome)")
            #expect(one.calls.map(\.arguments) == [Self.contextArgs])
            // constructeur illisible : pas d'usage
            let two = FakeCommandRunner()
            two.scriptLocalEngine(builder: [outcome])
            #expect(DockerScanner.list(runner: two, dockerPath: Self.docker) == DockerScan(status: .notLocal), "constructeur \(outcome)")
            #expect(two.calls.map(\.arguments) == [Self.contextArgs, Self.builderArgs])
        }
    }

    @Test func aDockerThatCannotBeLaunchedIsToolNotFoundAndTheTimeoutsAreTimedOut() {
        let one = FakeCommandRunner()
        one.script(.failedToLaunch, executable: Self.docker, arguments: Self.contextArgs)
        #expect(DockerScanner.list(runner: one, dockerPath: Self.docker) == DockerScan(status: .toolNotFound))

        let two = FakeCommandRunner()
        two.script(.timedOut, executable: Self.docker, arguments: Self.contextArgs)
        #expect(DockerScanner.list(runner: two, dockerPath: Self.docker) == DockerScan(status: .timedOut))

        let three = FakeCommandRunner()
        three.scriptLocalEngine(builder: [.timedOut])
        #expect(DockerScanner.list(runner: three, dockerPath: Self.docker) == DockerScan(status: .timedOut))
        #expect(three.calls.map(\.arguments) == [Self.contextArgs, Self.builderArgs])
    }

    @Test func withoutAnAbsoluteDockerPathTheEngineIsNotReadEither() {
        #expect(DockerScanner.list(runner: runner, dockerPath: nil) == DockerScan(status: .toolNotFound))
        #expect(DockerScanner.list(runner: runner, dockerPath: "docker") == DockerScan(status: .toolNotFound))
        #expect(runner.calls.isEmpty)
    }

    // MARK: Nettoyage : le moteur est relu JUSTE AVANT, et doit être celui qui a été confirmé

    @Test func aPruneReadsTheEngineAgainRightBeforeItAndThenRunsExactlyTheMeasuredCommand() {
        runner.scriptLocalEngine(); scriptPrunes()
        let outcome = DockerScanner.prune(.buildCache, runner: runner, dockerPath: Self.docker, expectedEngine: Self.engine)
        #expect(outcome == .pruned(reportedBytes: 22_460_000_000))
        #expect(args() == [Self.contextArgs, Self.builderArgs, ["builder", "prune", "-a", "-f"]])
        #expect(runner.calls.last == .init(executable: Self.docker, arguments: Self.cacheArgs, timeLimit: 300, outputLimit: 4 * 1024 * 1024,
                                           removedEnvironment: DockerCommand.removedEnvironment))

        let images = FakeCommandRunner()
        images.scriptLocalEngine()
        images.script(.finished(stdout: "Total reclaimed space: 397MB\n"), executable: Self.docker, arguments: Self.imageArgs)
        #expect(DockerScanner.prune(.untaggedImages, runner: images, dockerPath: Self.docker, expectedEngine: Self.engine) == .pruned(reportedBytes: 397_000_000))
        #expect(images.calls.map(\.arguments) == [Self.contextArgs, Self.builderArgs, ["image", "prune", "-f"]])
    }

    @Test func anEndpointThatBecameRemoteBetweenTheScanAndThePruneRunsNothing() {
        // Le listage voit le moteur local ; à la confirmation le contexte courant est devenu distant (`docker context use` depuis un terminal).
        runner.scriptLocalEngine(context: [.finished(stdout: DockerEngineReportTests.desktopContext),
                                           Self.contextOutcome("ssh://user@build.example.invalid", name: "team-builder")])
        scriptListing(); scriptPrunes()
        let scan = list()
        #expect(scan.status == .ok)
        let outcome = DockerScanner.prune(.buildCache, runner: runner, dockerPath: Self.docker, expectedEngine: scan.engine ?? Self.engine)
        #expect(outcome == .notLocal)
        #expect(!args().contains(Self.cacheArgs) && !args().contains(Self.imageArgs), "aucun nettoyage n'est parti")
        #expect(args().suffix(1) == [Self.contextArgs], "la relecture s'arrête au contexte distant")
    }

    @Test func aBuilderThatBecameRemoteBetweenTheScanAndThePruneRunsNothing() {
        runner.scriptLocalEngine(builder: [.finished(stdout: DockerEngineReportTests.runningBuilder()),
                                           .finished(stdout: DockerEngineReportTests.runningBuilder(name: "shared", driver: "docker-container", endpoint: "ssh://user@build.example.invalid"))])
        scriptListing(); scriptPrunes()
        #expect(list().status == .ok)
        #expect(DockerScanner.prune(.buildCache, runner: runner, dockerPath: Self.docker, expectedEngine: Self.engine) == .notLocal)
        #expect(!args().contains(Self.cacheArgs))
    }

    @Test func aLocalEngineOtherThanTheOneThatWasConfirmedRunsNothing() {
        runner.scriptLocalEngine(context: [.finished(stdout: DockerEngineReportTests.contextWithHost("unix:///Users/test/.orbstack/run/docker.sock", name: "orbstack"))],
                                builder: [.finished(stdout: DockerEngineReportTests.runningBuilder(name: "orbstack", endpoint: "orbstack"))])
        scriptPrunes()
        #expect(DockerScanner.prune(.buildCache, runner: runner, dockerPath: Self.docker, expectedEngine: Self.engine) == .failed)
        #expect(!args().contains(Self.cacheArgs))
    }

    @Test func unreadableOrStoppedEngineRightBeforeThePruneRunsNothing() {
        let cases: [(CommandOutcome, DockerPruneOutcome)] = [
            (.finished(stdout: ""), .notLocal), (.finished(stdout: "garbage"), .notLocal), (.finished(exit: 1), .notLocal),
            (.finished(stdout: DockerEngineReportTests.desktopContext, truncated: true), .notLocal), (.timedOut, .timedOut), (.failedToLaunch, .failed),
        ]
        for (answer, expected) in cases {
            let fake = FakeCommandRunner()
            fake.scriptLocalEngine(context: [answer])
            fake.script(.finished(stdout: "Total: 1GB"), executable: Self.docker, arguments: Self.cacheArgs)
            #expect(DockerScanner.prune(.buildCache, runner: fake, dockerPath: Self.docker, expectedEngine: Self.engine) == expected, "contexte \(answer)")
            #expect(!fake.calls.map(\.arguments).contains(Self.cacheArgs))

            let two = FakeCommandRunner()
            two.scriptLocalEngine(builder: [answer])
            two.script(.finished(stdout: "Total: 1GB"), executable: Self.docker, arguments: Self.cacheArgs)
            #expect(DockerScanner.prune(.buildCache, runner: two, dockerPath: Self.docker, expectedEngine: Self.engine) == expected, "constructeur \(answer)")
            #expect(!two.calls.map(\.arguments).contains(Self.cacheArgs))
        }
        let stopped = FakeCommandRunner()
        stopped.scriptLocalEngine(builder: [.finished(stdout: DockerEngineReportTests.stoppedEngineBuilder)])
        stopped.script(.finished(stdout: "Total: 1GB"), executable: Self.docker, arguments: Self.cacheArgs)
        #expect(DockerScanner.prune(.buildCache, runner: stopped, dockerPath: Self.docker, expectedEngine: Self.engine) == .failed)
        #expect(!stopped.calls.map(\.arguments).contains(Self.cacheArgs))
    }

    @Test func withoutAnAbsoluteDockerPathAPruneReadsAndRunsNothing() {
        #expect(DockerScanner.prune(.buildCache, runner: runner, dockerPath: nil, expectedEngine: Self.engine) == .toolNotFound)
        #expect(DockerScanner.prune(.buildCache, runner: runner, dockerPath: "docker", expectedEngine: Self.engine) == .toolNotFound)
        #expect(runner.calls.isEmpty)
    }

    // MARK: Le lot : le moteur est relu avant CHAQUE nettoyage

    @Test func aBatchReadsTheEngineBeforeEachOfItsTwoPrunesAndStopsWhenTheSecondCheckRefuses() async {
        let remote = Self.contextOutcome("tcp://10.0.0.5:2376", name: "team-builder")
        runner.scriptLocalEngine(context: [.finished(stdout: DockerEngineReportTests.desktopContext), remote])
        scriptPrunes()
        let result = await DockerCleanupFlow.run(
            targets: [DockerCleanupTarget(prune: .buildCache, announcedBytes: 1), DockerCleanupTarget(prune: .untaggedImages, announcedBytes: 1)],
            runner: runner, dockerPath: Self.docker, expectedEngine: Self.engine,
            freeSpace: { 100 }, beforeWait: {}, wait: { _ in })
        #expect(result.succeededCount == 1 && result.failedCount == 1)
        #expect(args() == [Self.contextArgs, Self.builderArgs, Self.cacheArgs, Self.contextArgs],
                "relecture, nettoyage du cache, relecture refusée : le nettoyage des images ne part pas")
    }
}
