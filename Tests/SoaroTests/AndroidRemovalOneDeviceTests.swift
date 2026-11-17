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

    private func intact(_ box: Sandbox, _ names: [String]) -> Bool {
        names.allSatisfy { box.exists(".android/avd/\($0).ini") && box.exists(".android/avd/\($0).avd/config.ini") }
    }

    // MARK: T2 : la vérification des processus, juste avant de supprimer

    /// Appelle `remove` avec une mesure et un suppresseur notés ; le suppresseur supprime pour de vrai dans le bac à sable.
    private func act(_ box: Sandbox, _ fake: FakeCommandRunner, psPath: String? = "/bin/ps", target: AndroidRemovalTarget,
                     sizes: [UInt64] = [1], recorder: RemoveRecorder = RemoveRecorder())
        throws -> (result: SimulatorRemovalResult, measure: MeasureSequence, removals: [String]) {
        let measure = MeasureSequence(sizes, runnerCallCount: { fake.calls.count })
        let result = try remove(box, fake, psPath: psPath, measure: measure.measure, removeFile: recorder.remove, target: target)
        return (result, measure, recorder.calls)
    }

    @Test func nothingRunningLetsTheRemovalGoOnWithOneFreshPs() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A", display: "Test Phone A")
        let target = try scanTarget(box, "Test_Phone_A")
        let fake = runner(ps: Self.nothingRunning)

        let run = try act(box, fake, target: target)
        guard case .removed = run.result else { Issue.record("attendu : supprimé, reçu \(run.result)"); return }
        // Exactement `/bin/ps -axww -o command=`, 10 s, 4 Mio, une seule fois.
        #expect(fake.calls == [FakeCommandRunner.Call(executable: "/bin/ps", arguments: Self.psArguments, timeLimit: 10, outputLimit: 4 * 1024 * 1024)])
    }

    @Test func psIsRunAfterTheMeasureBeforeAndBeforeTheDeletionThenTheMeasureAfter() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A")
        let target = try scanTarget(box, "Test_Phone_A")
        let fake = runner(ps: Self.nothingRunning)

        let run = try act(box, fake, target: target, sizes: [5, 1, 0, 0])
        // Les deux mesures d'avant (dossier, `.ini`) voient zéro appel à `ps` ; les deux d'après en voient un : un émulateur lancé
        // PENDANT la mesure est vu par `ps`, qui passe juste avant la suppression.
        #expect(run.measure.callCountsOfTheRunner == [0, 0, 1, 1])
        #expect(run.removals == ["Test_Phone_A.avd", "Test_Phone_A.ini"])
        #expect(run.result == .removed(freed: 6))
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

        let run = try act(box, fake, target: target)
        #expect(run.result == .running(name: "Test Phone A"))
        #expect(fake.calls.count == 2)
        #expect(run.removals.isEmpty, "aucune suppression")
        #expect(run.measure.count == 2, "seule la mesure d'avant (dossier et `.ini`, lecture seule) a eu lieu avant le refus")
        #expect(intact(box, ["Test_Phone_A"]))
    }

    @Test func onlyAnAliasRunningMakesTheDeviceRunning() throws {
        for line in [Self.emulatorLine("Test_Phone_B"), "/Users/test/Library/Android/sdk/emulator/emulator @Test_Phone_B"] {
            let box = try Sandbox(insideHome: true)
            let folder = try makeAVD(box, name: "Test_Phone_A", display: "Test Phone A")
            try box.write(".android/avd/Test_Phone_B.ini", "path=\(folder.path)\n")
            let target = try scanTarget(box, "Test_Phone_A")
            let run = try act(box, runner(ps: .finished(stdout: line)), target: target)
            #expect(run.result == .running(name: "Test Phone A"))
            #expect(run.removals.isEmpty)
            #expect(box.exists(".android/avd/Test_Phone_B.ini") && box.exists(".android/avd/Test_Phone_A.ini"))
        }
    }

    @Test func theNameIsComparedIgnoringCaseAndAsAWholeName() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A", display: "Test Phone A")
        let target = try scanTarget(box, "Test_Phone_A")
        let lower = try act(box, runner(ps: .finished(stdout: Self.emulatorLine("test_phone_a"))), target: target)
        #expect(lower.result == .running(name: "Test Phone A"))
        // Un préfixe ne compte pas : `Test_Phone_AB` est un autre appareil.
        let prefix = try act(box, runner(ps: .finished(stdout: Self.emulatorLine("Test_Phone_AB"))), target: target)
        guard case .removed = prefix.result else { Issue.record("un préfixe ne doit pas compter comme « en cours d'exécution »"); return }
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
            let run = try act(box, runner(ps: outcome), target: target)
            #expect(run.result == .couldNotCheck, "\(outcome)")
            #expect(run.removals.isEmpty)
            #expect(intact(box, ["Test_Phone_A"]))
        }
    }

    @Test func noPsPathMeansCouldNotCheckWithZeroRunnerCalls() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, name: "Test_Phone_A")
        let target = try scanTarget(box, "Test_Phone_A")
        let fake = FakeCommandRunner()
        let run = try act(box, fake, psPath: nil, target: target)
        #expect(run.result == .couldNotCheck)
        #expect(fake.calls.isEmpty)
        #expect(run.removals.isEmpty)
        #expect(intact(box, ["Test_Phone_A"]))
    }

    @Test func alreadyGoneRefusedOrUnreadableStopsBeforePsAndBeforeAnyMeasure() throws {
        // Déjà disparu.
        let gone = try Sandbox(insideHome: true)
        try makeAVD(gone, name: "Test_Phone_A")
        let goneTarget = try scanTarget(gone, "Test_Phone_A")
        try FileManager.default.removeItem(at: gone.root.appendingPathComponent(".android/avd/Test_Phone_A.ini"))
        try FileManager.default.removeItem(at: gone.root.appendingPathComponent(".android/avd/Test_Phone_A.avd"))
        let fakeGone = FakeCommandRunner()
        let goneRun = try act(gone, fakeGone, target: goneTarget)
        #expect(goneRun.result == .alreadyGone)
        #expect(fakeGone.calls.isEmpty && goneRun.measure.count == 0 && goneRun.removals.isEmpty)

        // Refusé : le dossier a disparu mais l'inscription reste.
        let refused = try Sandbox(insideHome: true)
        try makeAVD(refused, name: "Test_Phone_A")
        let refusedTarget = try scanTarget(refused, "Test_Phone_A")
        try FileManager.default.removeItem(at: refused.root.appendingPathComponent(".android/avd/Test_Phone_A.avd"))
        let fakeRefused = FakeCommandRunner()
        let refusedRun = try act(refused, fakeRefused, target: refusedTarget)
        #expect(refusedRun.result == .refused)
        #expect(fakeRefused.calls.isEmpty && refusedRun.measure.count == 0 && refusedRun.removals.isEmpty)

        // Illisible : rien non plus.
        let unreadable = try Sandbox(insideHome: true)
        try unreadable.write(".android/avd", "pas un dossier")
        let fakeUnreadable = FakeCommandRunner()
        let unreadableTarget = AndroidRemovalTarget(name: "Test_Phone_A", folder: unreadable.root.appendingPathComponent(".android/avd/Test_Phone_A.avd"))
        let unreadableRun = try act(unreadable, fakeUnreadable, target: unreadableTarget)
        #expect(unreadableRun.result == .couldNotCheck)
        #expect(fakeUnreadable.calls.isEmpty && unreadableRun.measure.count == 0 && unreadableRun.removals.isEmpty)
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

    @Test func runningAndCouldNotCheckNeverDeleteAndRefusedOrAlreadyGoneNeverMeasure() throws {
        // En cours d'exécution.
        let running = try Sandbox(insideHome: true)
        try makeAVD(running, name: "Test_Phone_A", display: "Test Phone A")
        let runningTarget = try scanTarget(running, "Test_Phone_A")
        var measure = MeasureSequence([1])
        var recorder = RemoveRecorder()
        #expect(try remove(running, runner(ps: .finished(stdout: Self.emulatorLine("Test_Phone_A"))), measure: measure.measure,
                           removeFile: recorder.remove, target: runningTarget) == .running(name: "Test Phone A"))
        #expect(measure.count == 2 && recorder.calls.isEmpty, "la mesure d'avant (lecture seule) précède `ps` ; aucune suppression")
        #expect(intact(running, ["Test_Phone_A"]))

        // `ps` indisponible.
        measure = MeasureSequence([1]); recorder = RemoveRecorder()
        #expect(try remove(running, runner(ps: .timedOut), measure: measure.measure, removeFile: recorder.remove, target: runningTarget) == .couldNotCheck)
        #expect(measure.count == 2 && recorder.calls.isEmpty)

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

    // MARK: Le suppresseur réel revérifie juste avant de supprimer

    @Test func theRealRemoverRemovesAnAvdFolderWithItsConfigAndARegistrationFile() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A")
        try #require(folder.path.contains(".soaro-test-"))
        try AndroidEmulatorRemover.removeFile(folder.resolvingSymlinksInPath())
        try AndroidEmulatorRemover.removeFile(box.root.appendingPathComponent(".android/avd/Test_Phone_A.ini"))
        #expect(!box.exists(".android/avd/Test_Phone_A.avd") && !box.exists(".android/avd/Test_Phone_A.ini"))
    }

    @Test func theRealRemoverRefusesAFolderSwappedForASymlinkAfterThePlan() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeAVD(box, name: "Test_Phone_A")
        try box.write("Other.avd/config.ini", "AvdId=Other\n")
        let target = try scanTarget(box, "Test_Phone_A")
        try #require(box.root.path.contains(".soaro-test-"))
        // Le lien est posé PENDANT la mesure : après le plan, avant la suppression.
        var swapped = false
        let swap: (URL) -> UInt64 = { _ in
            if !swapped {
                swapped = true
                try? FileManager.default.removeItem(at: folder)
                try? FileManager.default.createSymbolicLink(at: folder, withDestinationURL: box.root.appendingPathComponent("Other.avd"))
            }
            return 0
        }

        let result = try remove(box, runner(ps: Self.nothingRunning), measure: swap, removeFile: AndroidEmulatorRemover.removeFile, target: target)

        #expect(result == .failed)
        #expect(box.exists("Other.avd/config.ini"), "le dossier visé par le lien n'est pas supprimé")
        #expect(box.exists(".android/avd/Test_Phone_A.ini"), "aucune inscription n'est supprimée quand le dossier échoue")
    }

    @Test func theRealRemoverRefusesAParentThatIsASymlinkAndAFolderWithoutConfig() throws {
        let box = try Sandbox(insideHome: true)
        try box.write("Real/Test_Phone_A.avd/config.ini", "AvdId=A\n")
        try FileManager.default.createSymbolicLink(at: box.root.appendingPathComponent("Link"),
                                                   withDestinationURL: box.root.appendingPathComponent("Real"))
        try box.write("NoConfig.avd/data.bin", "x")
        try box.write("Other.dir/config.ini", "x")
        try #require(box.root.path.contains(".soaro-test-"))

        #expect(throws: (any Error).self) { try AndroidEmulatorRemover.removeFile(box.root.appendingPathComponent("Link/Test_Phone_A.avd")) }
        #expect(throws: (any Error).self) { try AndroidEmulatorRemover.removeFile(box.root.appendingPathComponent("NoConfig.avd")) }
        #expect(throws: (any Error).self) { try AndroidEmulatorRemover.removeFile(box.root.appendingPathComponent("Other.dir")) }
        #expect(box.exists("Real/Test_Phone_A.avd/config.ini") && box.exists("NoConfig.avd/data.bin") && box.exists("Other.dir/config.ini"))
    }

    @Test func theRealRemoverRefusesAPathOutsideTheRealHome() throws {
        let outside = try Sandbox(insideHome: false)
        try outside.write("Test_Phone_A.avd/config.ini", "x")
        try outside.write("Test_Phone_A.ini", "x")
        #expect(throws: (any Error).self) { try AndroidEmulatorRemover.removeFile(outside.root.appendingPathComponent("Test_Phone_A.avd")) }
        #expect(throws: (any Error).self) { try AndroidEmulatorRemover.removeFile(outside.root.appendingPathComponent("Test_Phone_A.ini")) }
        #expect(outside.exists("Test_Phone_A.avd/config.ini") && outside.exists("Test_Phone_A.ini"))
    }

    @Test func theRealRemoverRefusesADirectoryNamedLikeARegistrationAndALinkToAFileOutsideTheHome() throws {
        let box = try Sandbox(insideHome: true)
        try box.write("Test_Phone_A.ini/precious.txt", "x")
        let outside = try Sandbox(insideHome: false)
        try outside.write("real.ini", "x")
        let link = box.root.appendingPathComponent("Test_Phone_B.ini")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside.root.appendingPathComponent("real.ini"))
        try #require(box.root.path.contains(".soaro-test-"))

        #expect(throws: (any Error).self) { try AndroidEmulatorRemover.removeFile(box.root.appendingPathComponent("Test_Phone_A.ini")) }
        #expect(throws: (any Error).self) { try AndroidEmulatorRemover.removeFile(link) }
        #expect(box.exists("Test_Phone_A.ini/precious.txt") && outside.exists("real.ini"))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil, "le lien est toujours là")
    }

    @Test func theRealRemoverRemovesALinkToAFileInsideTheHomeButNotItsTarget() throws {
        let box = try Sandbox(insideHome: true)
        try box.write("elsewhere/real.ini", "x")
        let link = box.root.appendingPathComponent("Test_Phone_B.ini")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: box.root.appendingPathComponent("elsewhere/real.ini"))
        try #require(box.root.path.contains(".soaro-test-"))
        try AndroidEmulatorRemover.removeFile(link)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == nil)
        #expect(box.exists("elsewhere/real.ini"))
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
