import Foundation
import Testing
@testable import Soaro

/// SL13 QA : des tailles absurdes (« 17999PB », sous le plafond de l'analyseur) ne font jamais déborder une somme : la somme se plafonne
/// à `UInt64.max` (choix : sommes saturantes, plafond de l'analyseur inchangé). Sans cela une addition de deux tailles arrêterait le programme.
@MainActor
@Suite(.serialized) struct DockerSaturationTests {
    static let docker = "/usr/local/bin/docker"
    static let huge = "17999PB"
    static let hugeBytes: UInt64 = 17_999_000_000_000_000_000

    static var hugeUsage: String {
        """
        {"Active":"0","Reclaimable":"\(huge)","Size":"\(huge)","TotalCount":"9","Type":"Build Cache"}
        {"Active":"0","Reclaimable":"\(huge)","Size":"\(huge)","TotalCount":"9","Type":"Images"}
        """
    }

    static var hugeUntagged: [String] {
        [DockerReportTests.untagged(id: "aaaaaaaaaaaa", size: huge, containers: "0"),
         DockerReportTests.untagged(id: "bbbbbbbbbbbb", size: huge, containers: "0")]
    }

    // MARK: L'aide

    @Test func theSaturatingSumAddsAndStopsAtTheLargestValue() {
        #expect(DockerSize.saturatingSum([UInt64]()) == 0)
        #expect(DockerSize.saturatingSum([1, 2, 3]) == 6)
        #expect(DockerSize.saturatingSum([UInt64.max, 1]) == UInt64.max)
        #expect(DockerSize.saturatingSum([Self.hugeBytes, Self.hugeBytes]) == UInt64.max)
        #expect(DockerSize.saturatingSum([UInt64.max - 1, 1]) == UInt64.max)
        #expect(DockerSize.saturatingSum([UInt64.max, 0, 5, UInt64.max]) == UInt64.max)
    }

    @Test func theParserStillReadsTheHugeSizeExactly() {
        #expect(DockerSize.parse(Self.huge) == Self.hugeBytes)
    }

    // MARK: Aperçu

    @Test func twoHugeUntaggedImagesAndAHugeCacheGiveAValidOverview() throws {
        let usage = try #require(DockerReport.parseUsage(Data(Self.hugeUsage.utf8)))
        let untagged = try #require(DockerReport.parseUntaggedImages(Data(Self.hugeUntagged.joined(separator: "\n").utf8)))
        let overview = DockerOverview.make(DockerScan(status: .ok, usage: usage, untagged: untagged))
        #expect(overview.cleanables.map(\.prune) == [.buildCache, .untaggedImages])
        #expect(overview.cleanables[0].size == Self.hugeBytes)
        #expect(overview.cleanables[1].size == UInt64.max, "deux images énormes : la somme est plafonnée")
        #expect(overview.cleanableTotal == UInt64.max)
        #expect(overview.otherUnusedImages == nil || overview.otherUnusedImages?.size != nil, "la ligne des autres images reste valide")
    }

    @Test func theConfirmationOfHugeSizesIsValidText() {
        let targets = [DockerCleanable(prune: .buildCache, size: Self.hugeBytes, count: nil),
                       DockerCleanable(prune: .untaggedImages, size: UInt64.max, count: 2)]
        let message = DockerPresentation.confirmationMessage(targets: targets, locale: Locale(identifier: "en"))
        #expect(message.hasPrefix("About "))
        #expect(message.contains("• Build cache · ") && message.contains("• Untagged images · "))
        #expect(message.contains("The next build will be slower"))
    }

    // MARK: Modèle (listage, sélection, confirmation) et lot

    @Test func aModelOnHugeSizesListsSelectsAndAsksWithoutCrashing() async {
        let runner = FakeCommandRunner()
        runner.scriptLocalEngine()
        runner.script(.finished(stdout: Self.hugeUsage), executable: Self.docker, arguments: DockerCommand.usage.arguments)
        runner.script(.finished(stdout: Self.hugeUntagged.joined(separator: "\n")), executable: Self.docker, arguments: DockerCommand.untaggedImages.arguments)
        let confirm = RecordingConfirm(answer: false)
        let m = DockerModel(runner: runner, locate: { Self.docker }, home: URL(fileURLWithPath: "/home-fake/user-x"),
                            freeSpace: { nil }, wait: { _ in }, demo: false, confirm: confirm.handler, gate: DockerCleanupGate(), notify: { _ in })
        m.scan()
        await m.scanTask?.value
        #expect(m.phase == .listed && m.selectedCount == 2)
        #expect(m.selectedSize == UInt64.max)
        m.cleanSelected()
        #expect(confirm.asks.count == 1 && confirm.asks[0].message.hasPrefix("About "))
    }

    @Test func hugePruneTotalsAddUpToAValidFigureAndToast() async {
        let runner = FakeCommandRunner()
        runner.scriptLocalEngine()
        runner.script(.finished(stdout: "Total:\t\(Self.huge)\n"), executable: Self.docker, arguments: DockerCommand.pruneBuildCache.arguments)
        runner.script(.finished(stdout: "Total reclaimed space: \(Self.huge)\n"), executable: Self.docker, arguments: DockerCommand.pruneUntaggedImages.arguments)
        let free = ScriptedFreeSpace([100, UInt64.max])
        let result = await DockerCleanupFlow.run(
            targets: [DockerCleanupTarget(prune: .buildCache, announcedBytes: Self.hugeBytes),
                      DockerCleanupTarget(prune: .untaggedImages, announcedBytes: Self.hugeBytes)],
            runner: runner, dockerPath: Self.docker, expectedEngine: DockerEngineScanTests.engine,
            freeSpace: { free.read() }, beforeWait: {}, wait: { _ in })
        #expect(result.dockerBytes == UInt64.max)
        #expect(result.returnedBytes == UInt64.max - 100)
        #expect(!result.toast(locale: Locale(identifier: "en")).isEmpty)
    }

    @Test func theHalfRuleNeverOverflowsOnHugeReturnedSpace() {
        let result = DockerCleanupResult(succeededCount: 1, failedCount: 0, timedOut: false, dockerBytes: UInt64.max, returnedBytes: UInt64.max)
        #expect(result.toast(locale: Locale(identifier: "en")).contains("returned to this Mac (Docker reported "))
        let under = DockerCleanupResult(succeededCount: 1, failedCount: 0, timedOut: false, dockerBytes: UInt64.max, returnedBytes: UInt64.max / 2 - 1)
        #expect(under.toast(locale: Locale(identifier: "en")).contains("did not give the space back"))
    }
}
