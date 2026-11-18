import Foundation
import Testing
@testable import Soaro

/// SL13 T6 : le modèle de l'outil Docker : listage, sélection, confirmation, lot, honnêteté du chiffre. Faux lanceur, faux relevé d'espace
/// libre et fausse attente : aucun test n'appelle un vrai `docker`, aucun n'attend 60 s.
@MainActor
@Suite(.serialized) struct DockerModelTests {
    nonisolated static let docker = "/usr/local/bin/docker"
    nonisolated static let gb: UInt64 = 1_000_000_000
    static let usageArgs = DockerCommand.usage.arguments
    static let untaggedArgs = DockerCommand.untaggedImages.arguments
    static let cacheArgs = DockerCommand.pruneBuildCache.arguments
    static let imageArgs = DockerCommand.pruneUntaggedImages.arguments
    /// SL16 : les deux lectures du moteur, avant le listage et avant chaque nettoyage.
    static let check: [[String]] = [DockerCommand.currentContext.arguments, DockerCommand.currentBuilder.arguments]

    /// Une porte PAR TEST (jamais la porte partagée du processus) : les suites tournent en parallèle.
    let gate = DockerCleanupGate()
    let runner = FakeCommandRunner()
    let confirm = RecordingConfirm(answer: true)
    let toasts = ToastBox()
    let counters = Counters()

    init() { runner.scriptLocalEngine() }

    final class ToastBox { var messages: [String] = [] }

    final class Counters: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var locates = 0, frees = 0, waits = 0
        private var values: [UInt64?] = [100 * DockerModelTests.gb, 119 * DockerModelTests.gb]
        func locate() { lock.lock(); locates += 1; lock.unlock() }
        func setFree(_ values: [UInt64?]) { lock.lock(); self.values = values; lock.unlock() }
        func free() -> UInt64? {
            lock.lock(); defer { lock.unlock() }
            let value = values[min(frees, values.count - 1)]
            frees += 1
            return value
        }
        func wait() { lock.lock(); waits += 1; lock.unlock() }
    }

    func scriptList(untagged: [String] = [DockerOverviewTests.removable, DockerOverviewTests.inUse]) {
        runner.script(.finished(stdout: DockerReportTests.realUsage), executable: Self.docker, arguments: Self.usageArgs)
        runner.script(.finished(stdout: untagged.joined(separator: "\n")), executable: Self.docker, arguments: Self.untaggedArgs)
    }

    func scriptPrunes() {
        runner.script(.finished(stdout: "ID1\nTotal:\t21.19GB\n"), executable: Self.docker, arguments: Self.cacheArgs)
        runner.script(.finished(stdout: "Total reclaimed space: 397MB\n"), executable: Self.docker, arguments: Self.imageArgs)
    }

    func model(_ runner: CommandRunner? = nil, locate: String? = docker, wait: (@Sendable (TimeInterval) async -> Void)? = nil,
               gate: DockerCleanupGate? = nil, demo: Bool = false) -> DockerModel {
        let toasts = toasts, counters = counters
        return DockerModel(runner: runner ?? self.runner,
                           locate: { counters.locate(); return locate },
                           home: URL(fileURLWithPath: "/home-fake/user-x"),
                           freeSpace: { counters.free() },
                           wait: wait ?? { _ in counters.wait() },
                           demo: demo,
                           confirm: confirm.handler,
                           gate: gate ?? self.gate,
                           notify: { toasts.messages.append($0) })
    }

    func scanned(_ m: DockerModel) async {
        m.scan()
        await m.scanTask?.value
    }

    func callArguments() -> [[String]] { runner.calls.map(\.arguments) }

    // MARK: Listage

    @Test func scanningRunsOnlyTheTwoReadOnlyCommandsAndPreSelectsBuildCacheAndUntaggedImages() async {
        scriptList()
        let m = model()
        await scanned(m)
        #expect(m.phase == .listed)
        #expect(callArguments() == Self.check + [Self.usageArgs, Self.untaggedArgs])
        #expect(runner.calls.allSatisfy { $0.executable == Self.docker })
        #expect(m.overview?.cleanables.map(\.prune) == [.buildCache, .untaggedImages])
        #expect(m.selected == [.buildCache, .untaggedImages])
        #expect(m.selectedCount == 2)
        #expect(m.selectedSize == 21_190_000_000 + 397_000_000)
        #expect(m.message == nil)
    }

    @Test func dockerNotFoundHidesTheToolAndRunsNothing() async {
        let m = model(locate: nil)
        await scanned(m)
        #expect(m.phase == .hidden)
        #expect(runner.calls.isEmpty)
        #expect(m.message == "Docker was not found on this Mac.")
        #expect(!m.canClean)
    }

    @Test func aStoppedEngineSaysSoShowsNoRowAndAllowsNoCleanup() async {
        runner.script(.finished(exit: 1, stderr: "Cannot connect to the Docker daemon"), executable: Self.docker, arguments: Self.usageArgs)
        let m = model()
        await scanned(m)
        #expect(m.phase == .failed(.notRunning))
        #expect(m.message == "Docker is not running. Start it, then scan again.")
        #expect(m.overview == nil && m.selected.isEmpty && !m.canClean)
        #expect(callArguments() == Self.check + [Self.usageArgs], "ni seconde lecture ni nettoyage, et Docker n'est jamais démarré")
        m.cleanSelected()
        #expect(confirm.asks.isEmpty)
        #expect(callArguments() == Self.check + [Self.usageArgs])
    }

    @Test func anEngineThatDoesNotAnswerAndAnUnreadableOutputHaveTheirOwnMessage() async {
        runner.script(.timedOut, executable: Self.docker, arguments: Self.usageArgs)
        let slow = model()
        await scanned(slow)
        #expect(slow.phase == .failed(.notAnswering))
        #expect(slow.message == "Docker did not answer. Try again in a moment.")

        let other = FakeCommandRunner()
        other.scriptLocalEngine()
        other.script(.finished(stdout: "garbage"), executable: Self.docker, arguments: Self.usageArgs)
        let unreadable = model(other)
        await scanned(unreadable)
        #expect(unreadable.phase == .failed(.couldNotRead))
        #expect(unreadable.message == "Could not read Docker’s disk usage.")
    }

    @Test func rescanningAfterAFailureCanSucceed() async {
        runner.script(sequence: [.finished(exit: 1), .finished(stdout: DockerReportTests.realUsage)], executable: Self.docker, arguments: Self.usageArgs)
        runner.script(.finished(stdout: ""), executable: Self.docker, arguments: Self.untaggedArgs)
        let m = model()
        await scanned(m)
        #expect(m.phase == .failed(.notRunning) && m.canScanAgain)
        await scanned(m)
        #expect(m.phase == .listed)
    }

    @Test func nothingToCleanIsListedWithNoSelection() async {
        runner.script(.finished(stdout: "{\"Active\":\"0\",\"Reclaimable\":\"0B\",\"Size\":\"0B\",\"TotalCount\":\"0\",\"Type\":\"Build Cache\"}"),
                      executable: Self.docker, arguments: Self.usageArgs)
        runner.script(.finished(stdout: ""), executable: Self.docker, arguments: Self.untaggedArgs)
        let m = model()
        await scanned(m)
        #expect(m.phase == .listed && m.selected.isEmpty && !m.canClean)
        #expect(m.showsNothingToClean)
    }

    // MARK: Sélection

    @Test func aRowCanBeUncheckedAndCheckedAgainAndSelectAllFollowsTheRule() async {
        scriptList()
        let m = model()
        await scanned(m)
        #expect(m.selectAllState == .all)
        m.toggle(.untaggedImages)
        #expect(m.selected == [.buildCache] && m.selectedSize == 21_190_000_000)
        #expect(m.selectAllState == .some)
        m.toggleAll()
        #expect(m.selected == [.buildCache, .untaggedImages], "mixte : tout cocher")
        m.toggleAll()
        #expect(m.selected.isEmpty && m.selectAllState == .none && !m.canClean)
        m.toggle(.buildCache)
        #expect(m.selected == [.buildCache])
    }

    @Test func aRowThatIsNotListedCannotBeChecked() async {
        runner.script(.finished(stdout: DockerReportTests.realUsage), executable: Self.docker, arguments: Self.usageArgs)
        runner.script(.finished(stdout: ""), executable: Self.docker, arguments: Self.untaggedArgs)
        let m = model()
        await scanned(m)
        m.toggle(.untaggedImages)
        #expect(m.selected == [.buildCache])
    }

    // MARK: Confirmation (R8)

    @Test func theConfirmationNamesWhatIsRemovedWithItsSizeAndSaysTheNextBuildIsSlower() async {
        scriptList()
        let m = model()
        await scanned(m)
        confirm.answer = false
        m.cleanSelected()
        #expect(confirm.asks.count == 1)
        let ask = confirm.asks[0]
        #expect(ask.title == "Clean the selected Docker items? (2)")
        let total = Format.fileBytes(21_587_000_000)
        #expect(ask.message == "About \(total) will be removed:\n\n• Build cache · \(Format.fileBytes(21_190_000_000))\n"
                + "• Untagged images · \(Format.fileBytes(397_000_000))\n\n"
                + "Docker engine: desktop-linux (/Users/test/.docker/run/docker.sock)\n\n"
                + "The next build will be slower, because the cache is rebuilt. Containers, volumes and images with a tag are not touched.")
        #expect(ask.button == "Clean")
        #expect(ask.critical, "bouton destructif ; Annuler est le bouton par défaut de l'alerte (R8)")
    }

    @Test func withoutTheBuildCacheTheConfirmationDoesNotPromiseASlowerBuild() async {
        scriptList()
        let m = model()
        await scanned(m)
        m.toggle(.buildCache)
        confirm.answer = false
        m.cleanSelected()
        let ask = confirm.asks[0]
        #expect(ask.title == "Clean the selected Docker items? (1)")
        #expect(ask.message.contains("• Untagged images · "))
        #expect(!ask.message.contains("Build cache") && !ask.message.contains("slower"))
        #expect(ask.message.hasSuffix("Containers, volumes and images with a tag are not touched."))
    }

    @Test func anUnknownSizeIsNeverInventedInTheConfirmation() async {
        scriptList(untagged: [DockerReportTests.untagged(id: "aaaaaaaaaaaa", size: "huge", containers: "0")])
        let m = model()
        await scanned(m)
        m.toggle(.buildCache)
        confirm.answer = false
        m.cleanSelected()
        let ask = confirm.asks[0]
        #expect(ask.message.hasPrefix("These will be removed:\n\n• Untagged images · unknown size\n"))
    }

    @Test func cancellingTheConfirmationRunsNothingKeepsTheSelectionAndShowsNothing() async {
        scriptList()
        let m = model()
        await scanned(m)
        let before = runner.calls.count
        confirm.answer = false
        m.cleanSelected()
        await m.cleanTask?.value
        #expect(runner.calls.count == before, "aucun nettoyage, aucun relevé")
        #expect(m.selected == [.buildCache, .untaggedImages])
        #expect(toasts.messages.isEmpty && m.lastResult == nil)
        #expect(counters.frees == 0 && counters.waits == 0)
        #expect(!gate.isBusy)
    }

    @Test func nothingSelectedAsksNothing() async {
        scriptList()
        let m = model()
        await scanned(m)
        m.toggleAll()
        m.cleanSelected()
        #expect(confirm.asks.isEmpty)
    }

    // MARK: Lot confirmé

    @Test func aConfirmedBatchRunsExactlyTheTwoPrunesInOrderThenMeasuresThenToastsThenRescans() async {
        scriptList(); scriptPrunes()
        let m = model()
        await scanned(m)
        let afterScan = runner.calls.count
        m.cleanSelected()
        await m.cleanTask?.value

        let calls = Array(runner.calls.dropFirst(afterScan))
        #expect(calls.map(\.arguments) == Self.check + [Self.cacheArgs] + Self.check + [Self.imageArgs] + Self.check + [Self.usageArgs, Self.untaggedArgs],
                "le moteur relu avant chacun des deux nettoyages exacts, puis le nouveau listage ; rien d'autre")
        #expect(calls.filter { DockerCommand.allCases.filter(\.isDestructive).map(\.arguments).contains($0.arguments) }
            .allSatisfy { $0.timeLimit == 300 && $0.outputLimit == 4 * 1024 * 1024 })
        #expect(counters.frees == 2 && counters.waits == 1)
        let reported = Format.fileBytes(21_190_000_000 + 397_000_000)
        #expect(toasts.messages == ["\(Format.fileBytes(19 * Self.gb)) returned to this Mac (Docker reported \(reported))."])
        #expect(m.lastResult == toasts.messages.first)
        #expect(!gate.isBusy && gate.stage == .idle)
        #expect(m.phase == .listed)
    }

    @Test func onlyTheCheckedRowIsPruned() async {
        scriptList(); scriptPrunes()
        let m = model()
        await scanned(m)
        m.toggle(.untaggedImages)
        let afterScan = runner.calls.count
        m.cleanSelected()
        await m.cleanTask?.value
        #expect(Array(runner.calls.dropFirst(afterScan)).map(\.arguments) == Self.check + [Self.cacheArgs] + Self.check + [Self.usageArgs, Self.untaggedArgs])

        let second = FakeCommandRunner()
        second.scriptLocalEngine()
        second.script(.finished(stdout: DockerReportTests.realUsage), executable: Self.docker, arguments: Self.usageArgs)
        second.script(.finished(stdout: DockerOverviewTests.removable), executable: Self.docker, arguments: Self.untaggedArgs)
        second.script(.finished(stdout: "Total reclaimed space: 397MB"), executable: Self.docker, arguments: Self.imageArgs)
        let images = model(second)
        await scanned(images)
        images.toggle(.buildCache)
        let before = second.calls.count
        images.cleanSelected()
        await images.cleanTask?.value
        #expect(Array(second.calls.dropFirst(before)).map(\.arguments) == Self.check + [Self.imageArgs] + Self.check + [Self.usageArgs, Self.untaggedArgs])
    }

    @Test func aFailedPruneStopsTheBatchAndIsCountedAndTheListIsReadAgain() async {
        scriptList()
        runner.script(.finished(exit: 1, stderr: "denied"), executable: Self.docker, arguments: Self.cacheArgs)
        runner.script(.finished(stdout: "Total reclaimed space: 397MB"), executable: Self.docker, arguments: Self.imageArgs)
        let m = model()
        await scanned(m)
        let afterScan = runner.calls.count
        m.cleanSelected()
        await m.cleanTask?.value
        #expect(Array(runner.calls.dropFirst(afterScan)).map(\.arguments) == Self.check + [Self.cacheArgs] + Self.check + [Self.usageArgs, Self.untaggedArgs],
                "le second nettoyage n'a pas lieu")
        #expect(toasts.messages == ["Cleanups that failed: 1"])
        #expect(counters.waits == 0 && counters.frees == 1, "rien n'a réussi : pas d'attente, pas de second relevé")
        #expect(!gate.isBusy)
    }

    @Test func aTimedOutPruneSaysDockerDidNotAnswer() async {
        scriptList()
        runner.script(.timedOut, executable: Self.docker, arguments: Self.cacheArgs)
        let m = model()
        await scanned(m)
        m.cleanSelected()
        await m.cleanTask?.value
        #expect(toasts.messages == ["Docker did not answer. Try again in a moment."])
        #expect(!runner.calls.contains { $0.arguments == Self.imageArgs })
    }

    @Test func halfOrLessComingBackIsSaidPlainly() async {
        scriptList(); scriptPrunes()
        counters.setFree([100 * Self.gb, 100 * Self.gb])
        let m = model()
        await scanned(m)
        m.cleanSelected()
        await m.cleanTask?.value
        let zero = Format.fileBytes(0)
        #expect(toasts.messages == ["\(zero) returned to this Mac, but Docker reported \(Format.fileBytes(21_587_000_000)): Docker’s disk image did not give the space back."])
    }

    @Test func everyCallOfEveryTestStaysInsideTheAllowlist() async {
        scriptList(); scriptPrunes()
        let m = model()
        await scanned(m)
        m.cleanSelected()
        await m.cleanTask?.value
        #expect(!runner.calls.isEmpty)
        #expect(runner.calls.allSatisfy { DockerCommand.isAllowed($0.arguments) && $0.executable == Self.docker })
    }

    // MARK: Un lot à la fois, Retour, modèle détruit

    @Test func whileTheBatchWaitsTheScreenIsBusyAndNothingElseCanStart() async {
        scriptList(); scriptPrunes()
        let release = AsyncSignal()
        let reached = AsyncSignal()
        let m = model(wait: { _ in reached.signal(); await release.wait() })
        let other = model()
        await scanned(m)
        m.cleanSelected()
        await reached.wait()                              // les nettoyages sont finis, l'attente de 60 s est en cours
        #expect(gate.stage == .measuring && m.isBusy && other.isBusy, "tous les modèles voient le lot")
        #expect(!m.canClean && !m.canScanAgain)
        let before = runner.calls.count
        m.scan()
        other.cleanSelected()
        m.toggle(.buildCache)
        #expect(runner.calls.count == before, "ni listage ni second lot pendant le lot")
        #expect(confirm.asks.count == 1, "un second modèle ne demande même pas de confirmation")
        #expect(m.selected == [.buildCache, .untaggedImages], "une ligne ne se bascule pas pendant le lot")
        release.signal()
        await m.cleanTask?.value
        #expect(!gate.isBusy && toasts.messages.count == 1)
    }

    @Test func backDuringTheBatchLetsItFinishWithItsToastAndTheNextOpeningScansAtTheEnd() async {
        scriptList(); scriptPrunes()
        let release = AsyncSignal(), reached = AsyncSignal()
        let m = model(wait: { _ in reached.signal(); await release.wait() })
        await scanned(m)
        m.cleanSelected()
        await reached.wait()
        m.cancel()                                        // bouton Retour
        #expect(m.phase == .notScanned, "jamais une liste périmée")
        m.scan()                                          // l'écran est rouvert : le listage est retenu
        #expect(m.phase == .notScanned)
        release.signal()
        await m.cleanTask?.value
        #expect(toasts.messages.count == 1, "le toast arrive quand même")
        #expect(!gate.isBusy)
        await m.scanTask?.value
        #expect(m.phase == .listed, "le listage retenu part à la fin du lot")
    }

    @Test func aBatchStillEndsWithItsToastAndFreesTheGateWhenTheModelIsDestroyed() async {
        scriptList(); scriptPrunes()
        let release = AsyncSignal(), reached = AsyncSignal()
        var m: DockerModel? = model(wait: { _ in reached.signal(); await release.wait() })
        await scanned(m!)
        m!.cleanSelected()
        let task = m!.cleanTask
        await reached.wait()
        m = nil
        release.signal()
        await task?.value
        #expect(toasts.messages.count == 1)
        #expect(!gate.isBusy)
    }

    // MARK: Fabrique de la porte

    @Test func aModelBuiltWithoutAGateUsesTheSharedOne() {
        let withDefault = DockerModel(runner: runner, locate: { nil }, home: URL(fileURLWithPath: "/home-fake/user-x"),
                                      freeSpace: { nil }, wait: { _ in }, demo: true, confirm: confirm.handler, notify: { _ in })
        #expect(withDefault.gate === DockerCleanupGate.shared)
        #expect(model().gate === gate)
    }
}

/// SL13 QA : Retour efface la ligne de résultat quand aucun lot ne tourne ; pendant un lot, le résultat arrive quand même.
@MainActor
@Suite(.serialized) struct DockerResultLineTests {
    let gate = DockerCleanupGate()
    let runner = FakeCommandRunner()
    let confirm = RecordingConfirm(answer: true)
    let toasts = DockerModelTests.ToastBox()

    init() { runner.scriptLocalEngine() }

    func model(wait: @escaping @Sendable (TimeInterval) async -> Void = { _ in }) -> DockerModel {
        let toasts = toasts
        let docker = DockerModelTests.docker
        runner.script(.finished(stdout: DockerReportTests.realUsage), executable: docker, arguments: DockerCommand.usage.arguments)
        runner.script(.finished(stdout: ""), executable: docker, arguments: DockerCommand.untaggedImages.arguments)
        runner.script(.finished(stdout: "Total:\t21.19GB\n"), executable: docker, arguments: DockerCommand.pruneBuildCache.arguments)
        return DockerModel(runner: runner, locate: { docker }, home: URL(fileURLWithPath: "/home-fake/user-x"),
                           freeSpace: { 100 * DockerModelTests.gb }, wait: wait, demo: false, confirm: confirm.handler, gate: gate,
                           notify: { toasts.messages.append($0) })
    }

    @Test func backClearsTheResultLineWhenNoBatchRuns() async {
        let m = model()
        m.scan()
        await m.scanTask?.value
        m.cleanSelected()
        await m.cleanTask?.value
        #expect(m.lastResult != nil)
        m.cancel()
        #expect(m.lastResult == nil)
        #expect(toasts.messages.count == 1, "le toast déjà montré n'est pas retiré ni répété")
    }

    @Test func backDuringABatchKeepsItsResultComingAfterwards() async {
        let release = AsyncSignal(), reached = AsyncSignal()
        let m = model(wait: { _ in reached.signal(); await release.wait() })
        m.scan()
        await m.scanTask?.value
        m.cleanSelected()
        await reached.wait()
        m.cancel()
        release.signal()
        await m.cleanTask?.value
        #expect(m.lastResult != nil && m.lastResult == toasts.messages.first, "le résultat du lot arrive malgré Retour")
    }
}
