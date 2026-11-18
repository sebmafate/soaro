import Foundation
import Testing
@testable import Soaro

/// SL13 T6 : le mode démo reste INERTE (CLAUDE.md, TESTING.md) : lignes inventées, même confirmation, aucun lanceur, aucune recherche de
/// `docker`, aucun relevé d'espace libre, aucune attente, rien d'écrit.
@MainActor
@Suite(.serialized) struct DockerDemoTests {
    let gate = DockerCleanupGate()
    let runner = FakeCommandRunner()           // un appel non prévu fait échouer le test
    let confirm = RecordingConfirm(answer: true)
    let toasts = DockerModelTests.ToastBox()
    let counters = DockerModelTests.Counters()

    func demoModel(home: URL = URL(fileURLWithPath: "/home-fake/user-x")) -> DockerModel {
        let toasts = toasts, counters = counters
        return DockerModel(runner: runner, locate: { counters.locate(); return "/usr/local/bin/docker" }, home: home,
                           freeSpace: { counters.free() }, wait: { _ in counters.wait() }, demo: true,
                           confirm: confirm.handler, gate: gate, notify: { toasts.messages.append($0) })
    }

    func noSideEffect(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(runner.calls.isEmpty, sourceLocation: sourceLocation)
        #expect(counters.locates == 0 && counters.frees == 0 && counters.waits == 0, sourceLocation: sourceLocation)
    }

    @Test func demoListArrivesAtOnceFromMadeUpDataWithoutLauncherLocatorOrMeasure() async {
        let m = demoModel()
        m.scan()                                   // sans attendre : tout est déjà là
        #expect(m.phase == .listed)
        #expect(m.overview?.cleanables.map(\.prune) == [.buildCache, .untaggedImages])
        #expect(m.selected == [.buildCache, .untaggedImages])
        #expect(m.overview?.containers.total != nil && m.overview?.volumes.total != nil)
        #expect(m.overview?.otherUnusedImages != nil)
        await m.scanTask?.value
        noSideEffect()
    }

    @Test func demoDataIsMadeUpAndNeverTheAuthorsOwn() throws {
        let scan = DemoData.docker()
        #expect(scan.status == .ok)
        let text = try String(contentsOf: RepositoryRoot.url().appendingPathComponent("Sources/Soaro/DemoData.swift"), encoding: .utf8)
        #expect(!text.contains("cocardo"))
        #expect(scan.untagged.allSatisfy { $0.id.hasPrefix("0000") })
    }

    @Test func demoConfirmationIsTheSameAndCleaningRemovesTheRowsAtOnceWithAMadeUpToast() async {
        let m = demoModel()
        m.scan()
        m.cleanSelected()
        #expect(confirm.asks.count == 1)
        #expect(confirm.asks[0].title == "Clean the selected Docker items? (2)")
        #expect(confirm.asks[0].critical && confirm.asks[0].button == "Clean")
        await m.cleanTask?.value
        #expect(m.overview?.cleanables.isEmpty == true && m.selected.isEmpty)
        #expect(m.showsNothingToClean)
        #expect(toasts.messages.count == 1 && toasts.messages[0].contains("returned to this Mac"))
        #expect(m.lastResult == toasts.messages.first)
        #expect(!gate.isBusy)
        noSideEffect()
    }

    @Test func demoCancelChangesNothing() {
        let m = demoModel()
        m.scan()
        confirm.answer = false
        m.cleanSelected()
        #expect(m.selected.count == 2 && m.overview?.cleanables.count == 2)
        #expect(toasts.messages.isEmpty)
        noSideEffect()
    }

    @Test func demoOnlyTheCheckedRowLeaves() {
        let m = demoModel()
        m.scan()
        m.toggle(.untaggedImages)
        m.cleanSelected()
        #expect(m.overview?.cleanables.map(\.prune) == [.untaggedImages])
        #expect(m.selected.isEmpty)
        noSideEffect()
    }

    @Test func demoScanAgainRestoresTheMadeUpRowsStillWithoutAnyCall() {
        let m = demoModel()
        m.scan()
        m.cleanSelected()
        m.scan()
        #expect(m.overview?.cleanables.count == 2)
        noSideEffect()
    }

    @Test func demoWritesNothingAndReadsNoFile() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("soaro-demo-\(UUID().uuidString)")
        let m = demoModel(home: missing)
        m.scan()
        m.cleanSelected()
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        noSideEffect()
    }
}
