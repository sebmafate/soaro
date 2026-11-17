import Foundation
import Testing
@testable import Soaro

/// Enregistre les confirmations, les nettoyages et les démarrages. Les nettoyages arrivent hors de l'acteur principal.
private final class FlowRecorder: @unchecked Sendable {
    struct Ask: Equatable { let title: String; let message: String; let button: String; let critical: Bool }

    private let lock = NSLock()
    private var _cleaned: [CleanupKind] = []
    private(set) var asks: [Ask] = []
    private(set) var started = 0

    var cleaned: [CleanupKind] { lock.withLock { _cleaned } }

    /// Confirmation injectée.
    @MainActor func confirm(_ answer: Bool) -> ConfirmHandler {
        { [self] title, message, button, critical in
            asks.append(Ask(title: title, message: message, button: button, critical: critical))
            return answer
        }
    }

    /// Nettoyage injecté : jamais sur le disque.
    func clean(_ result: CleanupResult) -> @Sendable (CleanupKind) -> CleanupResult {
        { [self] kind in lock.withLock { _cleaned.append(kind) }; return result }
    }

    /// Nettoyage qui ne doit jamais être appelé (mode démo, annulation).
    func neverClean() -> @Sendable (CleanupKind) -> CleanupResult {
        { [self] kind in
            lock.withLock { _cleaned.append(kind) }
            Issue.record("clean(\(kind)) ne doit pas être appelé")
            return CleanupResult(freed: 0, failures: 0, error: nil)
        }
    }

    @MainActor func willStart() -> @MainActor () -> Void { { [self] in started += 1 } }
}

@MainActor
@Suite struct CacheCleanupFlowTests {
    private let gb: UInt64 = 1_000_000_000

    // MARK: Texte de la confirmation (inchangé)

    @Test func nugetAloneAsksTheExactConfirmation() async {
        let rec = FlowRecorder()
        let task = CacheCleanupFlow.run(
            kinds: [.nugetCache], sizes: [.nugetCache: 13 * gb], demo: false,
            confirm: rec.confirm(false), clean: rec.neverClean(), willStart: rec.willStart())
        #expect(task == nil)
        #expect(rec.asks == [.init(
            title: "Clean “NuGet packages”?",
            message: "• NuGet packages\n\nAbout \(Format.fileBytes(13 * gb)) will be freed.",
            button: "Clean", critical: false)])
    }

    @Test func quickCleanAsksOnceForSeveralKinds() {
        let rec = FlowRecorder()
        _ = CacheCleanupFlow.run(
            kinds: [.caches, .logs, .derivedData], sizes: [.caches: gb, .logs: gb / 10, .derivedData: 2 * gb], demo: false,
            confirm: rec.confirm(false), clean: rec.neverClean(), willStart: rec.willStart())
        #expect(rec.asks == [.init(
            title: "Run the quick clean?",
            message: "• App caches\n• Logs\n• Xcode DerivedData\n\nAbout \(Format.fileBytes(3 * gb + gb / 10)) will be freed.",
            button: "Clean", critical: false)])
    }

    @Test func trashIsCriticalAndSaysItIsPermanent() {
        let rec = FlowRecorder()
        _ = CacheCleanupFlow.run(
            kinds: [.trash], sizes: [.trash: gb], demo: false,
            confirm: rec.confirm(false), clean: rec.neverClean(), willStart: rec.willStart())
        #expect(rec.asks == [.init(
            title: "Clean “Trash”?",
            message: "• Trash\n\nAbout \(Format.fileBytes(gb)) will be freed.\nEmptying the Trash is permanent.",
            button: "Clean", critical: true)])
    }

    @Test func aSizeOfZeroOrUnknownHasNoAboutLine() {
        let rec = FlowRecorder()
        _ = CacheCleanupFlow.run(
            kinds: [.nugetCache], sizes: [.nugetCache: 0], demo: false,
            confirm: rec.confirm(false), clean: rec.neverClean(), willStart: rec.willStart())
        _ = CacheCleanupFlow.run(
            kinds: [.nugetCache], sizes: [:], demo: false,
            confirm: rec.confirm(false), clean: rec.neverClean(), willStart: rec.willStart())
        #expect(rec.asks.map(\.message) == ["• NuGet packages", "• NuGet packages"])
    }

    // MARK: Annulation

    @Test func cancellingCleansNothingAndStartsNothing() {
        let rec = FlowRecorder()
        let task = CacheCleanupFlow.run(
            kinds: [.nugetCache], sizes: [.nugetCache: 13 * gb], demo: false,
            confirm: rec.confirm(false), clean: rec.neverClean(), willStart: rec.willStart())
        #expect(task == nil)                 // pas de nettoyage, donc pas d'info à afficher
        #expect(rec.cleaned.isEmpty)
        #expect(rec.started == 0)
        #expect(rec.asks.count == 1)
    }

    // MARK: Confirmé

    @Test func confirmedCleansEachKindOnceInOrderAndReportsTheFreedSpace() async throws {
        let rec = FlowRecorder()
        let task = try #require(CacheCleanupFlow.run(
            kinds: [.nugetCache], sizes: [.nugetCache: 13 * gb], demo: false,
            confirm: rec.confirm(true), clean: rec.clean(CleanupResult(freed: 13 * gb, failures: 0, error: nil)),
            willStart: rec.willStart()))
        #expect(rec.started == 1)
        let toast = await task.value
        #expect(rec.cleaned == [.nugetCache])
        #expect(toast == "\(Format.fileBytes(13 * gb)) freed")
    }

    @Test func severalKindsAreCleanedInTheGivenOrderAndSummed() async throws {
        let rec = FlowRecorder()
        let task = try #require(CacheCleanupFlow.run(
            kinds: [.derivedData, .caches, .logs], sizes: [:], demo: false,
            confirm: rec.confirm(true), clean: rec.clean(CleanupResult(freed: gb, failures: 0, error: nil)),
            willStart: rec.willStart()))
        let toast = await task.value
        #expect(rec.cleaned == [.derivedData, .caches, .logs])
        #expect(toast == "\(Format.fileBytes(3 * gb)) freed")
    }

    @Test func skippedItemsAreAppendedToTheToast() async throws {
        let rec = FlowRecorder()
        let task = try #require(CacheCleanupFlow.run(
            kinds: [.nugetCache], sizes: [.nugetCache: 13 * gb], demo: false,
            confirm: rec.confirm(true), clean: rec.clean(CleanupResult(freed: 12 * gb, failures: 2, error: nil)),
            willStart: rec.willStart()))
        #expect(await task.value == "\(Format.fileBytes(12 * gb)) freed (2 items in use were skipped)")
    }

    @Test func theFirstErrorReplacesTheFreedMessage() async throws {
        let rec = FlowRecorder()
        let task = try #require(CacheCleanupFlow.run(
            kinds: [.nugetCache], sizes: [.nugetCache: 13 * gb], demo: false,
            confirm: rec.confirm(true), clean: rec.clean(CleanupResult(freed: 0, failures: 0, error: "Folder not accessible")),
            willStart: rec.willStart()))
        #expect(await task.value == "NuGet packages : Folder not accessible")
    }

    // MARK: Mode démo

    @Test func demoConfirmedNeverCleansAndReportsTheDemoSizes() async throws {
        let rec = FlowRecorder()
        let task = try #require(CacheCleanupFlow.run(
            kinds: [.nugetCache, .npmCache], sizes: DemoData.cleanupSizes, demo: true,
            confirm: rec.confirm(true), clean: rec.neverClean(), willStart: rec.willStart()))
        let toast = await task.value
        let sum = ((DemoData.cleanupSizes[.nugetCache] ?? nil) ?? 0) + ((DemoData.cleanupSizes[.npmCache] ?? nil) ?? 0)
        #expect(toast == "\(Format.fileBytes(sum)) freed")
        #expect(rec.cleaned.isEmpty)
        #expect(rec.started == 0)
        #expect(rec.asks.count == 1)         // la confirmation reste demandée
    }

    @Test func demoCancelledDoesNothingAtAll() {
        let rec = FlowRecorder()
        let task = CacheCleanupFlow.run(
            kinds: [.nugetCache], sizes: DemoData.cleanupSizes, demo: true,
            confirm: rec.confirm(false), clean: rec.neverClean(), willStart: rec.willStart())
        #expect(task == nil)
        #expect(rec.cleaned.isEmpty)
        #expect(rec.started == 0)
    }
}
