import Foundation
import Testing
@testable import Soaro

/// SL16 T3 (R9, R10, S4) : le modèle de l'outil Docker devant un moteur ou un constructeur qui n'est pas local. Faux lanceur : aucun vrai `docker`.
@MainActor
@Suite(.serialized) struct DockerEngineModelTests {
    static let docker = DockerEngineScanTests.docker
    static let refusal = "Soaro only cleans Docker on this Mac. The selected Docker engine or builder is not local."

    let gate = DockerCleanupGate()
    let runner = FakeCommandRunner()
    let confirm = RecordingConfirm(answer: true)
    let toasts = DockerModelTests.ToastBox()

    func model() -> DockerModel {
        let toasts = toasts
        return DockerModel(runner: runner, locate: { Self.docker }, home: URL(fileURLWithPath: "/Users/test"),
                           freeSpace: { 100 * DockerModelTests.gb }, wait: { _ in }, demo: false, confirm: confirm.handler, gate: gate,
                           notify: { toasts.messages.append($0) })
    }

    func scripted(context: [CommandOutcome] = [.finished(stdout: DockerEngineReportTests.desktopContext)],
                  builder: [CommandOutcome] = [.finished(stdout: DockerEngineReportTests.runningBuilder())]) {
        runner.scriptLocalEngine(context: context, builder: builder)
        runner.script(.finished(stdout: DockerReportTests.realUsage), executable: Self.docker, arguments: DockerCommand.usage.arguments)
        runner.script(.finished(stdout: DockerOverviewTests.removable), executable: Self.docker, arguments: DockerCommand.untaggedImages.arguments)
        runner.script(.finished(stdout: "Total:\t21.19GB\n"), executable: Self.docker, arguments: DockerCommand.pruneBuildCache.arguments)
        runner.script(.finished(stdout: "Total reclaimed space: 397MB\n"), executable: Self.docker, arguments: DockerCommand.pruneUntaggedImages.arguments)
    }

    func scanned(_ m: DockerModel) async { m.scan(); await m.scanTask?.value }
    var prunesRan: Bool { runner.calls.contains { DockerCommand.isAllowed($0.arguments) && ["prune"].contains($0.arguments.dropFirst().first ?? "") } }

    @Test(arguments: ["tcp://10.0.0.5:2376", "ssh://user@build.example.invalid", "npipe:////./pipe/docker_engine"])
    func aRemoteContextShowsTheRefusalWithNoRowNoButtonAndNoPrune(host: String) async {
        scripted(context: [DockerEngineScanTests.contextOutcome(host, name: "team-builder")])
        let m = model()
        await scanned(m)
        #expect(m.phase == .failed(.notLocal))
        #expect(m.message == Self.refusal)
        #expect(m.overview == nil && m.selected.isEmpty && m.engine == nil)
        #expect(!m.canClean && !m.showsNothingToClean)
        #expect(DockerScreen.layout(phase: m.phase) == .hint(warning: true), "un message sur tout l'écran : ni ligne, ni barre d'action")
        m.cleanSelected()
        #expect(confirm.asks.isEmpty)
        #expect(!prunesRan)
        #expect(runner.calls.map(\.arguments) == [DockerCommand.currentContext.arguments])
    }

    @Test func aBuilderWithAnotherDriverShowsTheSameRefusal() async {
        scripted(builder: [.finished(stdout: DockerEngineReportTests.runningBuilder(name: "shared", driver: "docker-container", endpoint: "desktop-linux"))])
        let m = model()
        await scanned(m)
        #expect(m.phase == .failed(.notLocal) && m.message == Self.refusal && !m.canClean)
        #expect(!prunesRan)
    }

    @Test func unreadableAnswersShowTheRefusalNeverACrash() async {
        for answer in [CommandOutcome.finished(stdout: ""), .finished(stdout: "garbage"), .finished(exit: 1), .finished(exit: 9, termination: .signaled)] {
            let box = FakeCommandRunner()
            box.scriptLocalEngine(context: [answer])
            let m = DockerModel(runner: box, locate: { Self.docker }, home: URL(fileURLWithPath: "/Users/test"), freeSpace: { nil },
                                wait: { _ in }, demo: false, confirm: confirm.handler, gate: DockerCleanupGate(), notify: { _ in })
            await scanned(m)
            #expect(m.phase == .failed(.notLocal) && !m.canClean, "\(answer)")
        }
    }

    @Test func aStoppedLocalEngineStillSaysDockerIsNotRunning() async {
        scripted(builder: [.finished(stdout: DockerEngineReportTests.stoppedEngineBuilder)])
        let m = model()
        await scanned(m)
        #expect(m.phase == .failed(.notRunning))
        #expect(m.message == "Docker is not running. Start it, then scan again.")
        #expect(!runner.calls.contains { $0.arguments == DockerCommand.usage.arguments }, "l'usage n'est pas lu quand le moteur ne répond pas")
    }

    @Test func dockerNotFoundStillHidesTheToolAndReadsNothing() async {
        let m = DockerModel(runner: runner, locate: { nil }, home: URL(fileURLWithPath: "/Users/test"), freeSpace: { nil }, wait: { _ in },
                            demo: false, confirm: confirm.handler, gate: DockerCleanupGate(), notify: { _ in })
        await scanned(m)
        #expect(m.phase == .hidden && runner.calls.isEmpty)
    }

    @Test func aLocalEngineIsRememberedForTheConfirmationAndTheBatch() async {
        scripted()
        let m = model()
        await scanned(m)
        #expect(m.phase == .listed)
        #expect(m.engine == DockerEngineScanTests.engine)
    }

    @Test func anEndpointThatChangesBetweenTheScanAndTheConfirmationRunsNoPruneAndTheScreenSaysSo() async {
        // Le listage voit le moteur local ; entre la confirmation et le nettoyage le contexte courant devient distant.
        scripted(context: [.finished(stdout: DockerEngineReportTests.desktopContext),
                           DockerEngineScanTests.contextOutcome("ssh://user@build.example.invalid", name: "team-builder")])
        let m = model()
        await scanned(m)
        #expect(m.canClean)
        m.cleanSelected()
        await m.cleanTask?.value
        #expect(confirm.asks.count == 1, "la confirmation a bien eu lieu")
        #expect(!prunesRan, "aucun nettoyage n'est parti")
        #expect(toasts.messages == ["Cleanups that failed: 1"])
        #expect(m.phase == .failed(.notLocal), "le nouveau listage refuse lui aussi : le message d'écran dit pourquoi")
        #expect(!gate.isBusy)
    }

    @Test func theEngineIsForgottenWhenTheListIsLeft() async {
        scripted()
        let m = model()
        await scanned(m)
        m.cancel()
        m.scan()
        #expect(m.phase == .listing && m.engine == nil)
        await m.scanTask?.value
    }
}
