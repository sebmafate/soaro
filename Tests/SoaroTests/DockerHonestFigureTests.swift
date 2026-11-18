import Foundation
import Testing
@testable import Soaro

/// Journal partagé entre le faux lanceur, le faux relevé d'espace libre et la fausse attente : l'ORDRE des événements est ce qu'on vérifie.
final class DockerEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ item: String) { lock.lock(); items.append(item); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

/// Lanceur qui note ses appels dans le journal, puis répond comme le faux lanceur écrit à la main.
final class LoggingDockerRunner: CommandRunner {
    let fake = FakeCommandRunner()
    let events: DockerEvents
    init(events: DockerEvents) { self.events = events }
    func run(executable: String, arguments: [String], timeLimit: TimeInterval, outputLimit: Int) -> CommandOutcome {
        run(executable: executable, arguments: arguments, timeLimit: timeLimit, outputLimit: outputLimit, removingEnvironment: [])
    }
    func run(executable: String, arguments: [String], timeLimit: TimeInterval, outputLimit: Int,
             removingEnvironment: [String]) -> CommandOutcome {
        events.add("run " + arguments.joined(separator: " "))
        return fake.run(executable: executable, arguments: arguments, timeLimit: timeLimit, outputLimit: outputLimit,
                        removingEnvironment: removingEnvironment)
    }
}

/// Espace libre scripté : une valeur par lecture, la dernière se répète.
final class ScriptedFreeSpace: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UInt64?]
    private let events: DockerEvents?
    private(set) var reads = 0
    init(_ values: [UInt64?], events: DockerEvents? = nil) { self.values = values; self.events = events }
    func read() -> UInt64? {
        lock.lock(); defer { lock.unlock() }
        events?.add("free")
        let value = values[min(reads, values.count - 1)]
        reads += 1
        return value
    }
}

/// SL13 T5 (R11, D3) : le chiffre honnête, avec un relevé d'espace libre et une attente injectés. Aucun test n'attend 60 s ni ne lance `docker`.
@Suite struct DockerHonestFigureTests {
    static let docker = "/usr/local/bin/docker"
    static let gb: UInt64 = 1_000_000_000
    static let cacheArgs = ["builder", "prune", "-a", "-f"]
    static let imageArgs = ["image", "prune", "-f"]

    let events = DockerEvents()
    let runner: LoggingDockerRunner

    init() { runner = LoggingDockerRunner(events: events) }

    func scriptCache(_ outcome: CommandOutcome = .finished(stdout: "ID1\nTotal:\t22.46GB\n")) {
        runner.fake.script(outcome, executable: Self.docker, arguments: Self.cacheArgs)
    }

    func scriptImages(_ outcome: CommandOutcome = .finished(stdout: "Total reclaimed space: 397MB\n")) {
        runner.fake.script(outcome, executable: Self.docker, arguments: Self.imageArgs)
    }

    func run(_ targets: [DockerCleanupTarget], free: ScriptedFreeSpace, waits: WaitRecorder = WaitRecorder()) async -> DockerCleanupResult {
        let events = events
        return await DockerCleanupFlow.run(targets: targets, runner: runner, dockerPath: Self.docker,
                                           freeSpace: { free.read() },
                                           beforeWait: { events.add("measuring") },
                                           wait: { seconds in events.add("wait \(Int(seconds))"); waits.add(seconds) })
    }

    final class WaitRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [TimeInterval] = []
        func add(_ value: TimeInterval) { lock.lock(); items.append(value); lock.unlock() }
        var all: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return items }
    }

    static let cache = DockerCleanupTarget(prune: .buildCache, announcedBytes: 21_190_000_000)
    static let images = DockerCleanupTarget(prune: .untaggedImages, announcedBytes: 397_000_000)

    // MARK: Ordre : relevé, nettoyage, attente de 60 s, relevé

    @Test func freeSpaceIsReadBeforeThePruneThenTheModelWaitsSixtySecondsThenReadsAgain() async {
        scriptCache()
        let free = ScriptedFreeSpace([100 * Self.gb, 119 * Self.gb], events: events)
        let waits = WaitRecorder()
        let result = await run([Self.cache], free: free, waits: waits)
        #expect(events.all == ["free", "run builder prune -a -f", "measuring", "wait 60", "free"])
        #expect(waits.all == [60])
        #expect(DockerCleanupFlow.measureDelay == 60)
        #expect(result.returnedBytes == 19 * Self.gb)
        #expect(result.dockerBytes == 22_460_000_000, "le chiffre de Docker : celui que le nettoyage a annoncé")
    }

    @Test func theGainIsFreeAfterMinusFreeBeforeAndNeverNegative() async {
        scriptCache()
        let lower = await run([Self.cache], free: ScriptedFreeSpace([100 * Self.gb, 98 * Self.gb]))
        #expect(lower.returnedBytes == 0, "plus bas après : zéro, jamais un nombre négatif")
        let same = await run([Self.cache], free: ScriptedFreeSpace([100 * Self.gb, 100 * Self.gb]))
        #expect(same.returnedBytes == 0)
    }

    @Test func twoPrunesAreRunInOrderWithOneWaitAndTheFiguresAreAdded() async {
        scriptCache(); scriptImages()
        let free = ScriptedFreeSpace([100 * Self.gb, 122 * Self.gb], events: events)
        let waits = WaitRecorder()
        let result = await run([Self.cache, Self.images], free: free, waits: waits)
        #expect(events.all == ["free", "run builder prune -a -f", "run image prune -f", "measuring", "wait 60", "free"])
        #expect(waits.all == [60])
        #expect(result.dockerBytes == 22_460_000_000 + 397_000_000)
        #expect(result.returnedBytes == 22 * Self.gb)
        #expect(result.succeededCount == 2 && result.failedCount == 0 && !result.timedOut)
    }

    @Test func aFigureDockerDidNotPrintFallsBackOnTheAnnouncedOne() async {
        scriptCache(.finished(stdout: "ID1\n"))
        let result = await run([Self.cache], free: ScriptedFreeSpace([100 * Self.gb, 110 * Self.gb]))
        #expect(result.dockerBytes == 21_190_000_000)
    }

    @Test func withNoFigureAtAllTheComparisonIsUnknown() async {
        scriptCache(.finished(stdout: "ID1\n"))
        let result = await run([DockerCleanupTarget(prune: .buildCache, announcedBytes: nil)],
                               free: ScriptedFreeSpace([100 * Self.gb, 110 * Self.gb]))
        #expect(result.dockerBytes == nil)
        #expect(result.returnedBytes == 10 * Self.gb)
    }

    // MARK: Échecs : rien d'autre ne tourne

    @Test func aFailedFirstPruneStopsTheBatchWithNoWaitAndNoSecondRead() async {
        scriptCache(.finished(exit: 1)); scriptImages()
        let free = ScriptedFreeSpace([100 * Self.gb, 120 * Self.gb], events: events)
        let result = await run([Self.cache, Self.images], free: free)
        #expect(events.all == ["free", "run builder prune -a -f"], "pas de seconde commande, pas d'attente, pas de seconde lecture")
        #expect(result.succeededCount == 0 && result.failedCount == 1 && !result.timedOut)
        #expect(result.returnedBytes == nil && result.dockerBytes == nil)
        #expect(result.toast(locale: Locale(identifier: "en")) == "Cleanups that failed: 1")
    }

    @Test func aTimeoutStopsTheBatchAndSaysDockerDidNotAnswer() async {
        scriptCache(.timedOut); scriptImages()
        let result = await run([Self.cache, Self.images], free: ScriptedFreeSpace([100 * Self.gb], events: events))
        #expect(events.all == ["free", "run builder prune -a -f"])
        #expect(result.timedOut)
        #expect(result.toast(locale: Locale(identifier: "en")) == "Docker did not answer. Try again in a moment.")
    }

    @Test func aSecondPruneThatFailsAfterASuccessStillMeasuresWhatCameBack() async {
        scriptCache(); scriptImages(.finished(exit: 1))
        let free = ScriptedFreeSpace([100 * Self.gb, 119 * Self.gb], events: events)
        let result = await run([Self.cache, Self.images], free: free)
        #expect(events.all == ["free", "run builder prune -a -f", "run image prune -f", "measuring", "wait 60", "free"])
        #expect(result.succeededCount == 1 && result.failedCount == 1)
        #expect(result.dockerBytes == 22_460_000_000)
        #expect(result.toast(locale: Locale(identifier: "en")).hasSuffix(" · Cleanups that failed: 1"))
    }

    @Test func unreadableFreeSpaceMeansUnmeasuredNotZero() async {
        scriptCache()
        let beforeMissing = await run([Self.cache], free: ScriptedFreeSpace([nil, 120 * Self.gb]))
        #expect(beforeMissing.returnedBytes == nil)
        let afterMissing = await run([Self.cache], free: ScriptedFreeSpace([100 * Self.gb, nil]))
        #expect(afterMissing.returnedBytes == nil)
        #expect(afterMissing.toast(locale: Locale(identifier: "en"))
                == "Docker reported 22.46 GB. The space returned to this Mac could not be measured.")
    }

    // MARK: Texte (pur)

    func text(docker: UInt64?, returned: UInt64?, succeeded: Int = 1) -> String {
        DockerCleanupResult(succeededCount: succeeded, failedCount: 0, timedOut: false, dockerBytes: docker, returnedBytes: returned)
            .toast(locale: Locale(identifier: "en"))
    }

    @Test func atLeastHalfBackIsSaidPlainly() {
        #expect(text(docker: 22_460_000_000, returned: 20_150_000_000) == "20.15 GB returned to this Mac (Docker reported 22.46 GB).")
        // Exactement la moitié : pas « sous la moitié ».
        #expect(text(docker: 10 * Self.gb, returned: 5 * Self.gb) == "5 GB returned to this Mac (Docker reported 10 GB).")
    }

    @Test func underHalfBackSaysTheDiskImageDidNotGiveTheSpaceBack() {
        #expect(text(docker: 10 * Self.gb, returned: 4_999_999_999)
                == "5 GB returned to this Mac, but Docker reported 10 GB: Docker’s disk image did not give the space back.")
        let zero = text(docker: 22_460_000_000, returned: 0)
        #expect(zero.hasPrefix("Zero KB returned") || zero.hasPrefix("0 bytes returned"), "\(zero)")
        #expect(zero.contains("did not give the space back"))
        #expect(!zero.contains("-"))
    }

    @Test func zeroIsWrittenAsTheFormatterWritesZeroAndNeverNegative() {
        let zero = Format.fileBytes(0, locale: Locale(identifier: "en"))
        #expect(text(docker: 0, returned: 0) == "\(zero) returned to this Mac (Docker reported \(zero)).")
    }

    @Test func withoutDockersFigureThereIsNoComparisonAndNoHalfRule() {
        #expect(text(docker: nil, returned: 3 * Self.gb) == "3 GB returned to this Mac.")
        #expect(text(docker: nil, returned: nil) == "The space returned to this Mac could not be measured.")
    }

    @Test func noSuccessNoFailureAndNoTimeoutGivesNoText() {
        let none = DockerCleanupResult(succeededCount: 0, failedCount: 0, timedOut: false, dockerBytes: nil, returnedBytes: nil)
        #expect(none.toast(locale: Locale(identifier: "en")).isEmpty)
    }

    // MARK: Relevé réel de l'espace libre

    @Test func theRealReaderGivesTheFreeSpaceOfAVolumeAndNothingForAMissingFolder() {
        #expect((DockerFreeSpace.available(at: URL(fileURLWithPath: NSHomeDirectory())) ?? 0) > 0)
        #expect(DockerFreeSpace.available(at: URL(fileURLWithPath: "/definitely/not/a/folder-\(UUID().uuidString)")) == nil)
    }
}
