import Foundation
import Testing
@testable import Soaro

/// Tests d'intégration du vrai lanceur, avec des programmes inoffensifs uniquement
/// (`echo`, `sleep`, `yes`, `false`). Les marges de temps sont larges exprès (CI chargée).
@Suite struct CommandRunnerIntegrationTests {
    /// Lanceur de test qui note le pid du processus lancé (point d'observation, pas dans le protocole).
    private final class PidLog {
        var pids: [pid_t] = []
    }

    private func makeRunner(_ log: PidLog = PidLog()) -> RealCommandRunner {
        RealCommandRunner(onLaunch: { log.pids.append($0) })
    }

    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    /// Vrai si le processus n'existe plus (ESRCH), en attendant un court instant qu'il disparaisse.
    private func waitUntilGone(_ pid: pid_t, seconds: Double = 3) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if kill(pid, 0) == -1 && errno == ESRCH { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return kill(pid, 0) == -1 && errno == ESRCH
    }

    // MARK: Exécution normale

    @Test func echoReturnsItsArgumentsLiterallyWithoutAnyShellExpansion() {
        let runner = makeRunner()
        let tricky = "a; b $HOME $(x)"
        guard case .completed(let out) = runner.run(executable: "/bin/echo", arguments: [tricky], timeLimit: 10, outputLimit: 4096) else {
            Issue.record("echo n'a pas terminé"); return
        }
        #expect(out.exitCode == 0)
        #expect(text(out.stdout) == tricky + "\n")
        #expect(!out.truncated)
    }

    @Test func eachArgumentStaysSeparate() {
        let runner = makeRunner()
        guard case .completed(let out) = runner.run(executable: "/bin/echo", arguments: ["a;", "b", "$HOME", "$(x)"], timeLimit: 10, outputLimit: 4096) else {
            Issue.record("echo n'a pas terminé"); return
        }
        #expect(text(out.stdout) == "a; b $HOME $(x)\n")
    }

    @Test func nonZeroExitCodeIsReportedAsCompleted() {
        let runner = makeRunner()
        let outcome = runner.run(executable: "/usr/bin/false", arguments: [], timeLimit: 10, outputLimit: 4096)
        guard case .completed(let out) = outcome else { Issue.record("false n'a pas terminé"); return }
        #expect(out.exitCode == 1)
        #expect(!out.truncated)
    }

    // MARK: Délai

    @Test func timeLimitKillsTheProcessAndItIsReallyDead() {
        let log = PidLog()
        let runner = makeRunner(log)
        let start = Date()
        let outcome = runner.run(executable: "/bin/sleep", arguments: ["30"], timeLimit: 0.5, outputLimit: 4096)
        let elapsed = Date().timeIntervalSince(start)

        #expect(outcome == .timedOut)
        #expect(elapsed < 10, "doit rendre la main bien avant les 30 s de sleep")
        #expect(log.pids.count == 1)
        if let pid = log.pids.first { #expect(waitUntilGone(pid), "le processus doit avoir disparu") }
    }

    // MARK: Sortie bornée

    @Test func outputPastTheCapIsCutTruncatedAndTheProcessIsStopped() {
        let log = PidLog()
        let runner = makeRunner(log)
        let cap = 64 * 1024
        let start = Date()
        let outcome = runner.run(executable: "/usr/bin/yes", arguments: [], timeLimit: 30, outputLimit: cap)
        let elapsed = Date().timeIntervalSince(start)

        guard case .completed(let out) = outcome else { Issue.record("yes aurait dû rendre une sortie coupée, pas \(outcome)"); return }
        #expect(out.truncated)
        #expect(out.termination == .signaled, "tué par le lanceur : ce n'est pas une sortie ordinaire")
        #expect(out.stdout.count <= cap)
        #expect(out.stdout.count > 0)
        #expect(elapsed < 10)
        if let pid = log.pids.first { #expect(waitUntilGone(pid)) }
    }

    @Test func aNormalExitIsReportedAsExitedNotSignaled() {
        let runner = makeRunner()
        guard case .completed(let out) = runner.run(executable: "/usr/bin/false", arguments: [], timeLimit: 10, outputLimit: 4096) else {
            Issue.record("false n'a pas terminé"); return
        }
        #expect(out.termination == .exited)
    }

    /// De bout en bout avec le vrai lanceur : `yes` répète ses arguments sans fin (inoffensif). Le scanner reçoit une sortie
    /// coupée à 8 Mio et un processus tué : l'état doit être « sortie illisible », pas « échec avec le code 9 ».
    @Test func aRealOverflowReachesTheScannerAsOutputNotReadable() throws {
        let box = try Sandbox()
        let start = Date()
        let result = SimulatorScanner.scan(runner: makeRunner(), xcrunPath: "/usr/bin/yes", home: box.root)
        #expect(result.status == .outputNotReadable)
        #expect(result.devices.isEmpty)
        #expect(Date().timeIntervalSince(start) < 30)
    }

    /// `dd` écrit des zéros sur SA sortie d'erreur (`of=/dev/stderr`) : inoffensif, et seul moyen simple d'inonder stderr
    /// sans shell (`yes` n'écrit que sur la sortie standard).
    @Test func standardErrorIsBoundedLikeStandardOutput() {
        let log = PidLog()
        let runner = makeRunner(log)
        let cap = 4096
        let start = Date()
        let outcome = runner.run(executable: "/bin/dd", arguments: ["if=/dev/zero", "of=/dev/stderr", "bs=1024", "count=200000"],
                                 timeLimit: 30, outputLimit: cap)
        guard case .completed(let out) = outcome else { Issue.record("dd aurait dû rendre une sortie coupée, pas \(outcome)"); return }
        #expect(out.truncated, "le flot d'erreur dépassait la borne")
        #expect(out.stderr.count <= cap)
        #expect(out.stderr.count > 0)
        #expect(out.stdout.count <= cap)
        #expect(Date().timeIntervalSince(start) < 10, "dd (200 Mo) doit être arrêté bien avant la fin")
        if let pid = log.pids.first { #expect(waitUntilGone(pid)) }
    }

    /// L'entrée standard du programme est `/dev/null` : `cat` sans argument rend la main tout de suite, sans rien lire.
    /// Pour que le test échoue si l'entrée était héritée, on met d'abord sur l'entrée du test un tube dont l'écriture reste ouverte
    /// (un `cat` qui hériterait de ce tube attendrait jusqu'au délai), puis on la rétablit.
    @Test(.serialized) func standardInputIsDevNullSoACatReturnsAtOnce() {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { Issue.record("pipe impossible"); return }
        let saved = dup(0)
        defer { dup2(saved, 0); close(saved); close(fds[0]); close(fds[1]) }
        dup2(fds[0], 0)

        let runner = makeRunner()
        let start = Date()
        let outcome = runner.run(executable: "/bin/cat", arguments: [], timeLimit: 5, outputLimit: 4096)
        guard case .completed(let out) = outcome else { Issue.record("cat a attendu sur l'entrée : \(outcome)"); return }
        #expect(out.exitCode == 0)
        #expect(out.stdout.isEmpty)
        #expect(Date().timeIntervalSince(start) < 4)
    }

    // MARK: Lancement impossible

    @Test func missingPathDirectoryAndNonExecutableFailToLaunchWithoutCrashing() throws {
        let runner = makeRunner()
        let box = try Sandbox()
        let plain = try box.file("plain.txt")

        #expect(runner.run(executable: "/nonexistent/soaro-test-tool", arguments: [], timeLimit: 5, outputLimit: 10) == .failedToLaunch)
        #expect(runner.run(executable: "/usr/bin", arguments: [], timeLimit: 5, outputLimit: 10) == .failedToLaunch)
        #expect(runner.run(executable: plain.path, arguments: [], timeLimit: 5, outputLimit: 10) == .failedToLaunch)
    }

    // MARK: Refus avant tout lancement

    @Test func shellsAndEnvAreRefusedAndNothingIsLaunched() throws {
        let log = PidLog()
        let runner = makeRunner(log)
        let box = try Sandbox()
        let marker = box.root.appendingPathComponent("marker").path

        let shell = runner.run(executable: "/bin/sh", arguments: ["-c", "touch \(marker)"], timeLimit: 5, outputLimit: 10)
        #expect(shell == .refused(.shell))
        #expect(!FileManager.default.fileExists(atPath: marker), "le shell ne doit jamais avoir tourné")

        for path in ["/bin/zsh", "/bin/bash", "/usr/bin/env", "/bin/../bin/sh", "/bin//sh", "/bin/dash", "/bin/ksh", "/bin/csh", "/bin/tcsh"] {
            #expect(runner.run(executable: path, arguments: ["-c", "true"], timeLimit: 5, outputLimit: 10) == .refused(.shell), "\(path)")
        }
        #expect(log.pids.isEmpty, "aucun processus ne doit avoir été lancé")
    }

    @Test func aSymlinkToAShellIsRefused() throws {
        let log = PidLog()
        let runner = makeRunner(log)
        let box = try Sandbox()
        let link = box.root.appendingPathComponent("innocent-tool")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/bin/sh"))

        #expect(runner.run(executable: link.path, arguments: ["-c", "true"], timeLimit: 5, outputLimit: 10) == .refused(.shell))
        #expect(log.pids.isEmpty)
    }

    @Test func relativeAndEmptyPathsAreRefusedAndNothingIsLaunched() {
        let log = PidLog()
        let runner = makeRunner(log)
        for path in ["echo", "./x", "../bin/echo", "", "bin/echo", "~/x"] {
            #expect(runner.run(executable: path, arguments: [], timeLimit: 5, outputLimit: 10) == .refused(.notAbsolutePath), "«\(path)»")
        }
        #expect(log.pids.isEmpty)
    }
}
