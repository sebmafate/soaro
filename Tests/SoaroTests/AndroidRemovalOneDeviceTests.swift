import Foundation
import Testing
@testable import Soaro

/// SL11 : la suppression d'UN appareil Android. Tout se passe dans le bac à sable `.soaro-test-<uuid>` (jamais le vrai `~/.android`),
/// avec le faux lanceur : le vrai `ps`, un émulateur, `avdmanager` et `adb` ne sont jamais lancés. Les lignes de `ps` sont écrites
/// à la main et anonymisées (risque 6 : le format réel d'une ligne d'émulateur reste une hypothèse).
@Suite(.serialized) struct AndroidRemovalOneDeviceTests {
    static let psArguments = ["-axww", "-o", "command="]

    /// Une ligne de `ps` d'émulateur (inventée) pour un nom donné.
    static func emulatorLine(_ avd: String) -> String {
        "/Users/test/Library/Android/sdk/emulator/qemu/darwin-aarch64/qemu-system-aarch64 -avd \(avd) -netdelay none -netspeed full"
    }

    static let nothingRunning = CommandOutcome.finished(stdout: "/usr/sbin/cfprefsd agent\n/Applications/Notes.app/Contents/MacOS/Notes\n")

    @discardableResult
    private func makeAVD(_ box: Sandbox, name: String, display: String? = nil, registration: String? = nil) throws -> URL {
        try box.dir(".android/avd/\(name).avd")
        let ini = registration ?? "avd.ini.encoding=UTF-8\npath=\(box.root.path)/.android/avd/\(name).avd\npath.rel=avd/\(name).avd\ntarget=android-36\n"
        try box.write(".android/avd/\(name).ini", ini)
        var config = "AvdId=\(name)\n"
        if let display { config += "avd.ini.displayname=\(display)\n" }
        config += "image.sysdir.1=system-images/android-36/google_apis_playstore/arm64-v8a/\n"
        try box.write(".android/avd/\(name).avd/config.ini", config)
        return box.root.appendingPathComponent(".android/avd/\(name).avd")
    }

    private func scanTarget(_ box: Sandbox, _ name: String) throws -> AndroidRemovalTarget {
        let device = try #require(AndroidEmulatorScanner.listAVDs(home: box.root).devices.first { $0.name == name })
        return AndroidRemovalTarget(name: device.name, folder: device.folder)
    }

    private func runner(ps outcome: CommandOutcome) -> FakeCommandRunner {
        let runner = FakeCommandRunner()
        runner.script(outcome, executable: "/bin/ps", arguments: Self.psArguments)
        return runner
    }

    private func check(_ box: Sandbox, _ runner: FakeCommandRunner, psPath: String? = "/bin/ps",
                       target: AndroidRemovalTarget) -> AndroidRemovalCheck {
        AndroidEmulatorScanner.checkBeforeRemoval(runner: runner, psPath: psPath, home: box.root, target: target)
    }

    private func intact(_ box: Sandbox, _ names: [String]) -> Bool {
        names.allSatisfy { box.exists(".android/avd/\($0).ini") && box.exists(".android/avd/\($0).avd/config.ini") }
    }

    // MARK: T2 : la vérification juste avant d'agir

    @Test func nothingRunningLetsTheRemovalGoOnWithThePlanAndOneFreshPs() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A", display: "Test Phone A")
        let target = try scanTarget(box, "Test_Phone_A")
        let fake = runner(ps: Self.nothingRunning)

        guard case .proceed(let plan) = check(box, fake, target: target) else { Issue.record("on devait continuer"); return }
        #expect(plan.names == ["Test_Phone_A"])
        // Exactement `/bin/ps -axww -o command=`, 10 s, 4 Mio, une seule fois.
        #expect(fake.calls == [FakeCommandRunner.Call(executable: "/bin/ps", arguments: Self.psArguments, timeLimit: 10, outputLimit: 4 * 1024 * 1024)])
    }

    @Test func anAvdStartedAfterTheScanIsRunningWithItsFreshDisplayNameAndFilesStayIntact() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A", display: "Test Phone A")
        let target = try scanTarget(box, "Test_Phone_A")
        // Le scan voit « rien ne tourne » ; à l'action, l'émulateur tourne.
        let fake = FakeCommandRunner()
        fake.script(sequence: [Self.nothingRunning, .finished(stdout: Self.emulatorLine("Test_Phone_A"))],
                    executable: "/bin/ps", arguments: Self.psArguments)
        // Le scan : rien ne tourne (consomme le premier résultat du script).
        #expect(AndroidEmulatorScanner.runningAVDNames(runner: fake, psPath: "/bin/ps") == [])

        #expect(check(box, fake, target: target) == .stop(.running(name: "Test Phone A")))
        #expect(fake.calls.count == 2)
        #expect(intact(box, ["Test_Phone_A"]))
    }

    @Test func onlyAnAliasRunningMakesTheDeviceRunning() throws {
        for line in [Self.emulatorLine("Test_Phone_B"), "/Users/test/Library/Android/sdk/emulator/emulator @Test_Phone_B"] {
            let box = try Sandbox(insideHome: true)
            let folder = try makeAVD(box, name: "Test_Phone_A", display: "Test Phone A")
            try box.write(".android/avd/Test_Phone_B.ini", "path=\(folder.path)\n")
            let target = try scanTarget(box, "Test_Phone_A")
            #expect(check(box, runner(ps: .finished(stdout: line)), target: target) == .stop(.running(name: "Test Phone A")))
            #expect(box.exists(".android/avd/Test_Phone_B.ini") && box.exists(".android/avd/Test_Phone_A.ini"))
        }
    }

    @Test func theNameIsComparedIgnoringCaseAndAsAWholeName() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A", display: "Test Phone A")
        let target = try scanTarget(box, "Test_Phone_A")
        #expect(check(box, runner(ps: .finished(stdout: Self.emulatorLine("test_phone_a"))), target: target) == .stop(.running(name: "Test Phone A")))
        // Un préfixe ne compte pas : `Test_Phone_AB` est un autre appareil.
        guard case .proceed = check(box, runner(ps: .finished(stdout: Self.emulatorLine("Test_Phone_AB"))), target: target) else {
            Issue.record("un préfixe ne doit pas compter comme « en cours d'exécution »")
            return
        }
    }

    @Test func eachPsFailureMeansCouldNotCheckAndNeverATimeOut() throws {
        let failures: [CommandOutcome] = [
            .timedOut, .failedToLaunch, .finished(exit: 1, stdout: Self.emulatorLine("Test_Tablet_B")),
            .finished(termination: .signaled), .finished(stdout: "x", truncated: true), .refused(.shell),
        ]
        for outcome in failures {
            let box = try Sandbox(insideHome: true)
            try makeAVD(box, name: "Test_Phone_A")
            let target = try scanTarget(box, "Test_Phone_A")
            #expect(check(box, runner(ps: outcome), target: target) == .stop(.couldNotCheck), "\(outcome)")
            #expect(intact(box, ["Test_Phone_A"]))
        }
    }

    @Test func noPsPathMeansCouldNotCheckWithZeroRunnerCalls() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A")
        let target = try scanTarget(box, "Test_Phone_A")
        let fake = FakeCommandRunner()
        #expect(check(box, fake, psPath: nil, target: target) == .stop(.couldNotCheck))
        #expect(fake.calls.isEmpty)
        #expect(intact(box, ["Test_Phone_A"]))
    }

    @Test func alreadyGoneOrRefusedStopsBeforePsWithZeroRunnerCalls() throws {
        // Déjà disparu.
        let gone = try Sandbox(insideHome: true)
        try makeAVD(gone, name: "Test_Phone_A")
        let goneTarget = try scanTarget(gone, "Test_Phone_A")
        try FileManager.default.removeItem(at: gone.root.appendingPathComponent(".android/avd/Test_Phone_A.ini"))
        try FileManager.default.removeItem(at: gone.root.appendingPathComponent(".android/avd/Test_Phone_A.avd"))
        let fakeGone = FakeCommandRunner()
        #expect(check(gone, fakeGone, target: goneTarget) == .stop(.alreadyGone))
        #expect(fakeGone.calls.isEmpty)

        // Refusé : le dossier a disparu mais l'inscription reste.
        let refused = try Sandbox(insideHome: true)
        try makeAVD(refused, name: "Test_Phone_A")
        let refusedTarget = try scanTarget(refused, "Test_Phone_A")
        try FileManager.default.removeItem(at: refused.root.appendingPathComponent(".android/avd/Test_Phone_A.avd"))
        let fakeRefused = FakeCommandRunner()
        #expect(check(refused, fakeRefused, target: refusedTarget) == .stop(.refused))
        #expect(fakeRefused.calls.isEmpty)

        // Illisible : rien non plus.
        let unreadable = try Sandbox(insideHome: true)
        try unreadable.write(".android/avd", "pas un dossier")
        let fakeUnreadable = FakeCommandRunner()
        let unreadableTarget = AndroidRemovalTarget(name: "Test_Phone_A", folder: unreadable.root.appendingPathComponent(".android/avd/Test_Phone_A.avd"))
        #expect(check(unreadable, fakeUnreadable, target: unreadableTarget) == .stop(.couldNotCheck))
        #expect(fakeUnreadable.calls.isEmpty)
    }

    // MARK: T3 : la suppression du couple et l'espace libéré

    static let gigabyte: UInt64 = 1_000_000_000

    /// Noteur de suppressions : garde l'ordre des appels et supprime pour de vrai, mais UNIQUEMENT dans un bac à sable
    /// `.soaro-test-` (sinon le test échoue et rien n'est supprimé). `failing` : noms de fichiers dont la suppression lève une erreur ;
    /// `deletes: false` : ne supprime rien (le dossier existe encore après).
    final class RemoveRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        var failing: Set<String> = []
        var deletes = true

        var calls: [String] { lock.lock(); defer { lock.unlock() }; return urls.map(\.lastPathComponent) }

        func remove(_ url: URL) throws {
            lock.lock(); urls.append(url); lock.unlock()
            if failing.contains(url.lastPathComponent) { throw CocoaError(.fileWriteNoPermission) }
            guard url.path.contains(".soaro-test-") else {
                Issue.record("suppression hors du bac à sable refusée par le test : \(url.lastPathComponent)")
                throw CocoaError(.fileWriteNoPermission)
            }
            if deletes { try FileManager.default.removeItem(at: url) }
        }
    }

    private func remove(_ box: Sandbox, _ fake: FakeCommandRunner, psPath: String? = "/bin/ps", measure: @escaping (URL) -> UInt64 = { _ in 0 },
                        removeFile: @escaping (URL) throws -> Void, target: AndroidRemovalTarget) throws -> SimulatorRemovalResult {
        try #require(box.root.path.contains(".soaro-test-"), "le test doit utiliser un bac à sable")
        return AndroidEmulatorScanner.remove(runner: fake, psPath: psPath, home: box.root, measure: measure, removeFile: removeFile, target: target)
    }

    @Test func removingOneOfTwoAvdsDeletesItsPairOnlyAndLeavesTheNeighbourAndStrayFiles() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A", display: "Test Phone A")
        try makeAVD(box, name: "Test_Tablet_B")
        try box.write(".android/avd/stray.txt", "x")
        try box.write(".android/adb_usb.ini", "x")
        let target = try scanTarget(box, "Test_Phone_A")

        // Le vrai suppresseur de l'application, dans le bac à sable.
        let result = try remove(box, runner(ps: Self.nothingRunning), removeFile: AndroidEmulatorRemover.removeFile, target: target)
        guard case .removed = result else { Issue.record("attendu : supprimé, reçu \(result)"); return }
        #expect(!box.exists(".android/avd/Test_Phone_A.ini"))
        #expect(!box.exists(".android/avd/Test_Phone_A.avd"))
        #expect(intact(box, ["Test_Tablet_B"]))
        #expect(box.exists(".android/avd/stray.txt"))
        #expect(box.exists(".android/adb_usb.ini"))
        #expect(box.exists(".android/avd"))
    }

    @Test func anAliasIsRemovedWithTheFolderAndTheNeighbourStays() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A", display: "Test Phone A")
        try box.write(".android/avd/Test_Phone_B.ini", "path=\(folder.path)\n")
        try makeAVD(box, name: "Test_Tablet_B")
        let target = try scanTarget(box, "Test_Phone_A")
        let recorder = RemoveRecorder()

        let result = try remove(box, runner(ps: Self.nothingRunning), removeFile: recorder.remove, target: target)
        guard case .removed = result else { Issue.record("attendu : supprimé, reçu \(result)"); return }
        #expect(!box.exists(".android/avd/Test_Phone_A.ini") && !box.exists(".android/avd/Test_Phone_B.ini"))
        #expect(!box.exists(".android/avd/Test_Phone_A.avd"))
        #expect(intact(box, ["Test_Tablet_B"]))
        // L'ordre : le dossier d'abord, puis les `.ini` (le principal, puis les alias par nom).
        #expect(recorder.calls == ["Test_Phone_A.avd", "Test_Phone_A.ini", "Test_Phone_B.ini"])
    }

    @Test func theFreedSpaceIsBeforeMinusAfterOverTheFolderAndEveryRegistration() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A")
        let target = try scanTarget(box, "Test_Phone_A")
        // Avant : dossier 5 Go, `.ini` 4 Ko ; après : 0 et 0.
        let measure = MeasureSequence([5 * Self.gigabyte, 4_096, 0, 0])
        let result = try remove(box, runner(ps: Self.nothingRunning), measure: measure.measure, removeFile: RemoveRecorder().remove, target: target)
        #expect(result == .removed(freed: 5 * Self.gigabyte + 4_096))
        #expect(measure.count == 4)
        #expect(measure.folders.map(\.lastPathComponent) == ["Test_Phone_A.avd", "Test_Phone_A.ini", "Test_Phone_A.avd", "Test_Phone_A.ini"])
    }

    @Test func anAfterSizeLargerThanTheBeforeSizeFreesZero() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A")
        let target = try scanTarget(box, "Test_Phone_A")
        let measure = MeasureSequence([1_000, 10, 5_000, 50])
        #expect(try remove(box, runner(ps: Self.nothingRunning), measure: measure.measure, removeFile: RemoveRecorder().remove, target: target)
                == .removed(freed: 0))
    }

    @Test func aFailureOnTheFolderFailsAndNoRegistrationIsTouched() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A")
        try box.write(".android/avd/Test_Phone_B.ini", "path=\(folder.path)\n")
        let target = try scanTarget(box, "Test_Phone_A")
        let recorder = RemoveRecorder()
        recorder.failing = ["Test_Phone_A.avd"]

        let measure = MeasureSequence([1_000])
        #expect(try remove(box, runner(ps: Self.nothingRunning), measure: measure.measure, removeFile: recorder.remove, target: target) == .failed)
        #expect(recorder.calls == ["Test_Phone_A.avd"])
        #expect(intact(box, ["Test_Phone_A"]) && box.exists(".android/avd/Test_Phone_B.ini"))
        // Pas de mesure « après » quand ça a échoué.
        #expect(measure.count == 3)
    }

    @Test func aFolderThatStillExistsAfterTheCallFailsAndNoRegistrationIsTouched() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A")
        let target = try scanTarget(box, "Test_Phone_A")
        let recorder = RemoveRecorder()
        recorder.deletes = false

        #expect(try remove(box, runner(ps: Self.nothingRunning), removeFile: recorder.remove, target: target) == .failed)
        #expect(recorder.calls == ["Test_Phone_A.avd"])
        #expect(intact(box, ["Test_Phone_A"]))
    }

    @Test func aFailureOnTheAliasFailsButThePrimaryRegistrationWasStillTried() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A")
        try box.write(".android/avd/Test_Phone_B.ini", "path=\(folder.path)\n")
        let target = try scanTarget(box, "Test_Phone_A")
        let recorder = RemoveRecorder()
        recorder.failing = ["Test_Phone_B.ini"]

        #expect(try remove(box, runner(ps: Self.nothingRunning), removeFile: recorder.remove, target: target) == .failed)
        #expect(recorder.calls == ["Test_Phone_A.avd", "Test_Phone_A.ini", "Test_Phone_B.ini"])
        #expect(!box.exists(".android/avd/Test_Phone_A.ini"))
        #expect(box.exists(".android/avd/Test_Phone_B.ini"))
    }

    @Test func aFailureOnThePrimaryRegistrationStillTriesTheAliasAndFails() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A")
        try box.write(".android/avd/Test_Phone_B.ini", "path=\(folder.path)\n")
        let target = try scanTarget(box, "Test_Phone_A")
        let recorder = RemoveRecorder()
        recorder.failing = ["Test_Phone_A.ini"]

        #expect(try remove(box, runner(ps: Self.nothingRunning), removeFile: recorder.remove, target: target) == .failed)
        #expect(recorder.calls == ["Test_Phone_A.avd", "Test_Phone_A.ini", "Test_Phone_B.ini"])
        #expect(!box.exists(".android/avd/Test_Phone_B.ini"))
    }

    @Test func runningRefusedCouldNotCheckOrAlreadyGoneNeverMeasuresNorDeletes() throws {
        // En cours d'exécution.
        let running = try Sandbox(insideHome: true)
        try makeAVD(running, name: "Test_Phone_A", display: "Test Phone A")
        let runningTarget = try scanTarget(running, "Test_Phone_A")
        var measure = MeasureSequence([1])
        var recorder = RemoveRecorder()
        #expect(try remove(running, runner(ps: .finished(stdout: Self.emulatorLine("Test_Phone_A"))), measure: measure.measure,
                           removeFile: recorder.remove, target: runningTarget) == .running(name: "Test Phone A"))
        #expect(measure.count == 0 && recorder.calls.isEmpty)
        #expect(intact(running, ["Test_Phone_A"]))

        // `ps` indisponible.
        measure = MeasureSequence([1]); recorder = RemoveRecorder()
        #expect(try remove(running, runner(ps: .timedOut), measure: measure.measure, removeFile: recorder.remove, target: runningTarget) == .couldNotCheck)
        #expect(measure.count == 0 && recorder.calls.isEmpty)

        // Refusé : le dossier a disparu, l'inscription reste.
        let refused = try Sandbox(insideHome: true)
        try makeAVD(refused, name: "Test_Phone_A")
        let refusedTarget = try scanTarget(refused, "Test_Phone_A")
        try FileManager.default.removeItem(at: refused.root.appendingPathComponent(".android/avd/Test_Phone_A.avd"))
        measure = MeasureSequence([1]); recorder = RemoveRecorder()
        #expect(try remove(refused, FakeCommandRunner(), measure: measure.measure, removeFile: recorder.remove, target: refusedTarget) == .refused)
        #expect(measure.count == 0 && recorder.calls.isEmpty)
        #expect(refused.exists(".android/avd/Test_Phone_A.ini"))

        // Déjà disparu.
        try FileManager.default.removeItem(at: refused.root.appendingPathComponent(".android/avd/Test_Phone_A.ini"))
        measure = MeasureSequence([1]); recorder = RemoveRecorder()
        #expect(try remove(refused, FakeCommandRunner(), measure: measure.measure, removeFile: recorder.remove, target: refusedTarget) == .alreadyGone)
        #expect(measure.count == 0 && recorder.calls.isEmpty)
    }

    @Test func onlyPsIsEverRunByTheRemoval() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A")
        let target = try scanTarget(box, "Test_Phone_A")
        let fake = runner(ps: Self.nothingRunning)
        _ = try remove(box, fake, removeFile: RemoveRecorder().remove, target: target)
        #expect(fake.calls.map(\.executable) == ["/bin/ps"])
        #expect(fake.unscriptedCalls.isEmpty)
    }

    // MARK: Le code source

    @Test func theRemoverSourceHasNoOtherWayToDeleteOrLaunchAnything() throws {
        let file = RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Cleanup/AndroidEmulatorRemover.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        for forbidden in ["trashItem(", "\"/bin/rm\"", "createFile(", "write(to:", "avdmanager", "Process("] {
            #expect(!text.contains(forbidden), "AndroidEmulatorRemover.swift contient \(forbidden)")
        }
        #expect(text.components(separatedBy: "removeItem(").count - 1 == 1, "un seul appel à removeItem( : le suppresseur réel")
    }
}
