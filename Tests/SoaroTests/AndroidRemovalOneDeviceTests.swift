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
}
