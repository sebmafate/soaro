import Foundation

/// Vrai lanceur de commandes (ADR 0009). C'est le SEUL endroit du code neuf qui utilise `Process`.
///
/// - Chemin absolu obligatoire : jamais de PATH, jamais de shell, arguments passés un par un.
/// - Délai : au-delà, le processus reçoit SIGKILL et le résultat est `.timedOut`.
///   Limite connue : les processus petits-enfants d'un outil tué ne sont pas tués.
/// - Sortie : lue PENDANT l'exécution (pas d'interblocage de tube), bornée par flux ; au-delà de la borne
///   le processus est tué, la sortie coupée et `truncated` vaut `true`.
/// - Entrée standard : `/dev/null`.
struct RealCommandRunner: CommandRunner {
    /// Interpréteurs refusés, plus `env` (il cherche dans le PATH, donc il lancerait n'importe quoi).
    static let refusedNames: Set<String> = ["sh", "bash", "zsh", "dash", "ksh", "csh", "tcsh", "fish", "env"]

    /// Point d'observation pour les tests : appelé avec le pid juste après le lancement. Jamais utilisé en production.
    private let onLaunch: ((pid_t) -> Void)?

    init(onLaunch: ((pid_t) -> Void)? = nil) {
        self.onLaunch = onLaunch
    }

    /// Décide AVANT tout lancement si le chemin est acceptable.
    static func refusal(for executable: String) -> CommandRefusal? {
        guard executable.hasPrefix("/") else { return .notAbsolutePath }
        let standardized = URL(fileURLWithPath: executable).standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath()
        if refusedNames.contains(standardized.lastPathComponent) || refusedNames.contains(resolved.lastPathComponent) {
            return .shell
        }
        return nil
    }

    func run(executable: String, arguments: [String], timeLimit: TimeInterval, outputLimit: Int) -> CommandOutcome {
        if let reason = Self.refusal(for: executable) { return .refused(reason) }

        let url = URL(fileURLWithPath: executable).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: url.path) else { return .failedToLaunch }

        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let wake = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in wake.signal() }
        let out = StreamCapture(pipe: outPipe, limit: max(0, outputLimit), onOverflow: { wake.signal() })
        let err = StreamCapture(pipe: errPipe, limit: max(0, outputLimit), onOverflow: { wake.signal() })

        let deadline = DispatchTime.now() + timeLimit
        out.start()
        err.start()
        do {
            try process.run()
        } catch {
            out.stop(); err.stop()
            return .failedToLaunch
        }
        // Le parent ne garde que le côté lecture : sans cela on ne verrait jamais la fin des flux.
        try? outPipe.fileHandleForWriting.close()
        try? errPipe.fileHandleForWriting.close()
        let pid = process.processIdentifier
        onLaunch?(pid)

        func kill() {
            Foundation.kill(pid, SIGKILL)
            process.waitUntilExit()
        }

        if wake.wait(timeout: deadline) == .timedOut {
            kill()
            out.stop(); err.stop()
            return .timedOut
        }

        if out.overflowed || err.overflowed {
            kill()
            out.stop(); err.stop()
            return .completed(CommandOutput(exitCode: process.terminationStatus, stdout: out.data, stderr: err.data, truncated: true))
        }

        // Le processus est fini : on attend la fin des flux, dans le même délai global.
        // Si un petit-enfant garde le tube ouvert, le délai tranche.
        let drained = out.waitForEnd(until: deadline) && err.waitForEnd(until: deadline)
        out.stop(); err.stop()
        if !drained { return .timedOut }
        let truncated = out.overflowed || err.overflowed
        return .completed(CommandOutput(exitCode: process.terminationStatus, stdout: out.data, stderr: err.data, truncated: truncated))
    }
}

/// Lecture d'un tube pendant l'exécution, avec une borne en octets.
private final class StreamCapture {
    private let pipe: Pipe
    private let limit: Int
    private let onOverflow: () -> Void
    private let lock = NSLock()
    private var buffer = Data()
    private var overflow = false
    private var ended = false
    private let endGroup = DispatchGroup()

    init(pipe: Pipe, limit: Int, onOverflow: @escaping () -> Void) {
        self.pipe = pipe
        self.limit = limit
        self.onOverflow = onOverflow
    }

    var data: Data { lock.lock(); defer { lock.unlock() }; return buffer }
    var overflowed: Bool { lock.lock(); defer { lock.unlock() }; return overflow }

    func start() {
        endGroup.enter()
        pipe.fileHandleForReading.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            lock.lock()
            if chunk.isEmpty {
                // Fin du flux.
                finishLocked()
                handle.readabilityHandler = nil
                lock.unlock()
                return
            }
            let room = limit - buffer.count
            if chunk.count > room {
                buffer.append(chunk.prefix(max(0, room)))
                let first = !overflow
                overflow = true
                finishLocked()
                handle.readabilityHandler = nil
                lock.unlock()
                if first { onOverflow() }
                return
            }
            buffer.append(chunk)
            lock.unlock()
        }
    }

    private func finishLocked() {
        if !ended { ended = true; endGroup.leave() }
    }

    /// Attend la fin du flux ; `false` si l'échéance arrive avant.
    func waitForEnd(until deadline: DispatchTime) -> Bool {
        endGroup.wait(timeout: deadline) == .success
    }

    /// Arrête la lecture et ferme le tube (idempotent).
    func stop() {
        pipe.fileHandleForReading.readabilityHandler = nil
        lock.lock()
        finishLocked()
        lock.unlock()
        try? pipe.fileHandleForReading.close()
    }
}
