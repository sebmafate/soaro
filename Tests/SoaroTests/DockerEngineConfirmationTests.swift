import Foundation
import Testing
@testable import Soaro

/// SL16 T4 (R8, R9, S4) : la confirmation nomme le moteur sur lequel le nettoyage va tourner, pour que l'utilisateur voie où.
@MainActor
@Suite(.serialized) struct DockerEngineConfirmationTests {
    static let en = Locale(identifier: "en")
    static let desktop = DockerEngine(contextName: "desktop-linux", socketPath: "/Users/test/.docker/run/docker.sock")
    static let home = URL(fileURLWithPath: "/Users/test")

    func line(_ engine: DockerEngine) -> String {
        DockerPresentation.engineLine(engine, home: Self.home, locale: Self.en)
    }

    // MARK: La ligne

    @Test func theLineNamesTheContextAndTheSocketWithTheHomeFolderAbbreviated() {
        #expect(line(Self.desktop) == "Docker engine: desktop-linux (~/.docker/run/docker.sock)")
    }

    @Test func aSocketOutsideTheHomeFolderIsWrittenInFull() {
        #expect(line(DockerEngine(contextName: "default", socketPath: "/var/run/docker.sock")) == "Docker engine: default (/var/run/docker.sock)")
    }

    @Test func theHomeFolderIsAbbreviatedOnAWholeFolderNameOnly() {
        // « /Users/test2 » n'est pas sous « /Users/test » ; le dossier lui-même s'écrit « ~ » ; une barre finale ne gêne pas ; « / » n'abbrège rien.
        #expect(DockerPresentation.displayPath("/Users/test2/.docker/run/docker.sock", home: Self.home) == "/Users/test2/.docker/run/docker.sock")
        #expect(DockerPresentation.displayPath("/Users/test", home: Self.home) == "~")
        #expect(DockerPresentation.displayPath("/Users/test/a", home: URL(fileURLWithPath: "/Users/test/")) == "~/a")
        #expect(DockerPresentation.displayPath("/var/run/docker.sock", home: URL(fileURLWithPath: "/")) == "/var/run/docker.sock")
    }

    // MARK: Le message

    @Test func theEngineLineComesAfterTheListAndBeforeTheClosingSentencesWhichAreUnchanged() {
        let targets = [DockerCleanable(prune: .buildCache, size: 21_190_000_000, count: nil),
                       DockerCleanable(prune: .untaggedImages, size: 397_000_000, count: 1)]
        let message = DockerPresentation.confirmationMessage(targets: targets, engine: Self.desktop, home: Self.home, locale: Self.en)
        #expect(message == "About \(Format.fileBytes(21_587_000_000, locale: Self.en)) will be removed:\n\n"
                + "• Build cache · \(Format.fileBytes(21_190_000_000, locale: Self.en))\n• Untagged images · \(Format.fileBytes(397_000_000, locale: Self.en))\n\n"
                + "Docker engine: desktop-linux (~/.docker/run/docker.sock)\n\n"
                + "The next build will be slower, because the cache is rebuilt. Containers, volumes and images with a tag are not touched.")
    }

    // MARK: Le modèle

    let gate = DockerCleanupGate()
    let runner = FakeCommandRunner()
    let confirm = RecordingConfirm(answer: false)

    func model(home: String = "/Users/test", demo: Bool = false) -> DockerModel {
        DockerModel(runner: runner, locate: { DockerEngineScanTests.docker }, home: URL(fileURLWithPath: home),
                    freeSpace: { 100 * DockerModelTests.gb }, wait: { _ in }, demo: demo, confirm: confirm.handler, gate: gate, notify: { _ in })
    }

    @Test func theRealConfirmationNamesTheEngineTheListWasReadOnAndCancelStaysTheDefault() async {
        runner.scriptLocalEngine()
        runner.script(.finished(stdout: DockerReportTests.realUsage), executable: DockerEngineScanTests.docker, arguments: DockerCommand.usage.arguments)
        runner.script(.finished(stdout: DockerOverviewTests.removable), executable: DockerEngineScanTests.docker, arguments: DockerCommand.untaggedImages.arguments)
        let m = model()
        m.scan()
        await m.scanTask?.value
        let before = runner.calls.count
        m.cleanSelected()
        #expect(confirm.asks.count == 1)
        let ask = confirm.asks[0]
        #expect(ask.message.contains("Docker engine: desktop-linux (~/.docker/run/docker.sock)"))
        #expect(ask.critical, "Annuler reste le bouton par défaut de l'alerte (R8)")
        #expect(runner.calls.count == before, "Annuler : rien ne tourne")
    }

    @Test func demoConfirmationAlsoNamesAMadeUpEngineAndStaysInert() {
        let m = model(demo: true)
        m.scan()
        m.cleanSelected()
        #expect(confirm.asks.count == 1)
        #expect(confirm.asks[0].message.contains("Docker engine: desktop-linux (/var/run/docker.sock)"))
        #expect(runner.calls.isEmpty, "mode démo : aucune lecture, aucun appel au lanceur")
    }
}
