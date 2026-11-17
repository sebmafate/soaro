import Foundation
import Testing
@testable import Soaro

/// Signal « démarré » qu'un test attend SANS bloquer de fil (un test qui bloquerait un fil du pool coopératif affamerait les
/// tâches détachées des autres tests, qui tournent en parallèle). Compteur : un signal envoyé avant l'attente n'est pas perdu.
final class AsyncSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        lock.lock()
        if waiters.isEmpty {
            count += 1
            lock.unlock()
        } else {
            let waiter = waiters.removeFirst()
            lock.unlock()
            waiter.resume()
        }
    }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if count > 0 {
                count -= 1
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }
}

/// Faux lanceur à crochet : comme `FakeCommandRunner` mais il peut attendre, pour tester l'annulation en plein listage
/// sans jamais dormir (deux sémaphores, aucun délai).
final class BlockingRunner: CommandRunner, @unchecked Sendable {
    let started = AsyncSignal()
    let release = DispatchSemaphore(value: 0)
    private let outcome: CommandOutcome
    private let lock = NSLock()
    private var recorded: [FakeCommandRunner.Call] = []

    init(_ outcome: CommandOutcome) { self.outcome = outcome }

    var calls: [FakeCommandRunner.Call] { lock.lock(); defer { lock.unlock() }; return recorded }

    func run(executable: String, arguments: [String], timeLimit: TimeInterval, outputLimit: Int) -> CommandOutcome {
        lock.lock()
        recorded.append(.init(executable: executable, arguments: arguments, timeLimit: timeLimit, outputLimit: outputLimit))
        lock.unlock()
        started.signal()
        release.wait()
        return outcome
    }
}

/// Modèle de l'outil « Simulators and emulators » : états, listage, échecs (T5).
@MainActor
@Suite(.serialized) struct SimulatorsModelTests {
    static let u1 = "00000000-0000-4000-8000-000000000001"
    static let u2 = "00000000-0000-4000-8000-000000000002"
    let now = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!
    let present = SimulatorToolDetection(devicesFolderExists: true, simctlPath: "/fake/simctl")

    static func listJSON(_ udids: [String]) -> String {
        let entries = udids.map { "{\"udid\": \"\($0)\", \"name\": \"Device \($0.suffix(1))\", \"state\": \"Shutdown\"}" }
        return "{\"devices\": {\"com.apple.CoreSimulator.SimRuntime.iOS-26-2\": [\(entries.joined(separator: ","))]}}"
    }

    func fake(_ outcome: CommandOutcome) -> FakeCommandRunner {
        let fake = FakeCommandRunner()
        fake.script(outcome, executable: "/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "-j"])
        return fake
    }

    func model(_ runner: CommandRunner, detection: SimulatorToolDetection? = nil,
               measure: @escaping (URL) -> UInt64 = { _ in 500_000_000 }) -> SimulatorsModel {
        let detection = detection ?? present
        return SimulatorsModel(runner: runner,
                               detect: { detection },
                               locateXcrun: { _ in "/usr/bin/xcrun" },
                               home: URL(fileURLWithPath: "/home-fake/user-x"),
                               now: { self.now },
                               measure: measure,
                               demo: false,
                               confirm: { _, _, _, _ in false }, notify: { _ in })
    }

    /// Attend que le lanceur bloquant ait démarré, SANS bloquer l'acteur principal (la tâche du scan en a besoin pour démarrer).
    func waitUntilRunning(_ runner: BlockingRunner) async {
        await runner.started.wait()
    }

    func run(_ model: SimulatorsModel) async {
        model.scan()
        await model.scanTask?.value
    }

    // MARK: Départ

    @Test func startsNotScannedAndLaunchesNothing() {
        let runner = FakeCommandRunner()
        let m = model(runner)
        #expect(m.phase == .notScanned)
        #expect(m.message == nil)
        #expect(runner.calls.isEmpty)
    }

    @Test func scanShowsTheListingStateImmediately() async {
        let runner = BlockingRunner(.finished(stdout: Self.listJSON([Self.u1])))
        let m = model(runner)
        m.scan()
        #expect(m.phase == .listing)
        #expect(m.message == "Looking for simulators and emulators…")
        await waitUntilRunning(runner)
        runner.release.signal()
        await m.scanTask?.value
    }

    // MARK: Échecs

    @Test(arguments: [
        ("failed to launch", CommandOutcome.failedToLaunch),
        ("refused", .refused(.shell)),
        ("non-zero exit", .finished(exit: 72, stdout: "{}", stderr: "boom /Users/someone/secret")),
        ("signalled", .finished(exit: 11, termination: .signaled)),
        ("truncated", .finished(stdout: "{\"devices\":", truncated: true)),
        ("malformed", .finished(stdout: "not json")),
    ])
    func eachReadFailureShowsTheNeutralMessage(label: String, outcome: CommandOutcome) async {
        let m = model(fake(outcome))
        await run(m)
        #expect(m.phase == .failed(.couldNotRead), "\(label)")
        #expect(m.message == "Could not read the iOS Simulators.", "\(label)")
        #expect(m.rows.isEmpty)
    }

    @Test func timedOutHasItsOwnMessage() async {
        let m = model(fake(.timedOut))
        await run(m)
        #expect(m.phase == .failed(.notAnswering))
        #expect(m.message == "Xcode’s simulator service did not answer. Try again in a moment.")
    }

    @Test func noMessageEverShowsAnExitCodeStderrOrPath() async {
        for outcome in [CommandOutcome.finished(exit: 72, stderr: "xcrun: error /Users/someone/x"), .timedOut, .failedToLaunch] {
            let m = model(fake(outcome))
            await run(m)
            let text = m.message ?? ""
            #expect(!text.contains("72") && !text.contains("/") && !text.contains("xcrun"))
        }
    }

    @Test func emptyListShowsTheEmptyState() async {
        let m = model(fake(.finished(stdout: "{\"devices\": {}}")))
        await run(m)
        #expect(m.phase == .empty)
        #expect(m.message == "No simulator or emulator found.")
    }

    // MARK: Outil absent

    @Test func toolNotFoundMakesZeroRunnerCallsAndShowsTheNeutralMessage() async {
        let runner = FakeCommandRunner()
        let m = model(runner, detection: SimulatorToolDetection(devicesFolderExists: true, simctlPath: nil))
        await run(m)
        #expect(runner.calls.isEmpty)
        #expect(m.phase == .failed(.couldNotRead))
        #expect(m.message == "Could not read the iOS Simulators.")
    }

    @Test func xcrunMissingAlsoMakesZeroRunnerCalls() async {
        let runner = FakeCommandRunner()
        let m = SimulatorsModel(runner: runner, detect: { self.present }, locateXcrun: { _ in nil },
                                home: URL(fileURLWithPath: "/home-fake/user-x"), now: { self.now }, measure: { _ in 0 },
                                demo: false, confirm: { _, _, _, _ in false }, notify: { _ in })
        await run(m)
        #expect(runner.calls.isEmpty)
        #expect(m.phase == .failed(.couldNotRead))
    }

    // MARK: Commande exacte

    @Test func theRunnerReceivesExactlyTheDocumentedCommand() async {
        let runner = fake(.finished(stdout: Self.listJSON([Self.u1])))
        let m = model(runner)
        await run(m)
        #expect(runner.calls == [.init(executable: "/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "-j"],
                                       timeLimit: 60, outputLimit: 8 * 1024 * 1024)])
        #expect(runner.unscriptedCalls.isEmpty)
    }

    @Test func aSuccessfulListGivesTheListedState() async {
        let m = model(fake(.finished(stdout: Self.listJSON([Self.u1, Self.u2]))))
        await run(m)
        #expect(m.phase == .listed)
        #expect(m.message == nil)
        #expect(m.rows.count == 2)
    }

    // MARK: Annulation et nouveau scan

    @Test func cancellingDuringTheListingNeverAppliesTheResult() async {
        let runner = BlockingRunner(.finished(stdout: Self.listJSON([Self.u1])))
        let m = model(runner)
        m.scan()
        await waitUntilRunning(runner)  // le lanceur tourne
        m.cancel()                     // bouton Retour
        runner.release.signal()
        await m.scanTask?.value
        #expect(m.phase == .notScanned)
        #expect(m.rows.isEmpty)
        #expect(runner.calls.count == 1)
    }

    @Test func scanAgainWhileListingIsIgnoredAndRunsOnlyOneCommand() async {
        let runner = BlockingRunner(.finished(stdout: Self.listJSON([Self.u1])))
        let m = model(runner)
        #expect(m.canScanAgain)
        m.scan()
        #expect(!m.canScanAgain, "« Scan again » est désactivé pendant le listage")
        await waitUntilRunning(runner)
        let task = m.scanTask
        m.scan()                       // déclenchement répété : ignoré
        m.scan()
        #expect(m.scanTask == task)
        runner.release.signal()
        await m.scanTask?.value
        #expect(runner.calls.count == 1, "un seul `simctl list`")
        #expect(m.phase == .listed)
        #expect(m.rows.count == 1)
        #expect(m.canScanAgain)
    }

    @Test func scanAgainIsAllowedAfterACancelDuringListing() async {
        let runner = BlockingRunner(.finished(stdout: Self.listJSON([Self.u1])))
        let m = model(runner)
        m.scan()
        await waitUntilRunning(runner)
        m.cancel()
        #expect(m.canScanAgain)
        runner.release.signal()
        await m.scanTask?.value
        #expect(m.phase == .notScanned)
    }

    @Test func scanAgainAfterAFailureSucceeds() async {
        let runner = FakeCommandRunner()
        runner.script(.timedOut, executable: "/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "-j"])
        let m = model(runner)
        await run(m)
        #expect(m.phase == .failed(.notAnswering))

        runner.script(.finished(stdout: Self.listJSON([Self.u1])), executable: "/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "-j"])
        await run(m)
        #expect(m.phase == .listed)
        #expect(m.rows.count == 1)
        #expect(m.message == nil)
    }

    @Test func cancelWithoutAScanChangesNothing() {
        let m = model(FakeCommandRunner())
        m.cancel()
        #expect(m.phase == .notScanned)
    }

    // MARK: Textes (R12)

    @Test func stateMessagesAreInTheCatalogInNineLanguages() throws {
        let catalog = try TranslationCatalog.loadCatalog(TranslationCatalogTests.localizable)
        let strings = try #require(catalog["strings"] as? [String: Any])
        for key in ["Looking for simulators and emulators…", "Could not read the iOS Simulators.",
                    "Xcode’s simulator service did not answer. Try again in a moment.", "No simulator or emulator found."] {
            let entry = try #require(strings[key] as? [String: Any], "clé absente : \(key)")
            let localizations = try #require(entry["localizations"] as? [String: Any])
            for language in TranslationCatalog.requiredTranslations {
                let unit = try #require((localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any], "\(key) / \(language)")
                #expect(!((unit["value"] as? String) ?? "").isEmpty)
            }
        }
    }
}
