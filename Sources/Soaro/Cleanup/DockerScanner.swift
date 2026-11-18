import Foundation

/// Résultat du listage de Docker. Un état autre que `.ok` n'a ni usage ni image : l'écran dit seulement ce qui se passe.
struct DockerScan: Equatable {
    enum Status: Equatable, Error {
        case ok
        /// `docker` absent, ou impossible à lancer.
        case toolNotFound
        /// Le moteur ne répond pas : code de sortie non nul (moteur arrêté), fin par un signal, commande refusée par le lanceur.
        /// Soaro ne démarre jamais le moteur.
        case engineNotRunning
        case timedOut
        /// Code 0 mais sortie tronquée ou illisible : jamais d'analyse partielle.
        case outputNotReadable
    }

    let status: Status
    let usage: DockerUsage?
    /// Images sans étiquette (toutes, y compris celles qu'un conteneur utilise : `isRemovable` tranche).
    let untagged: [DockerUntaggedImage]

    init(status: Status, usage: DockerUsage? = nil, untagged: [DockerUntaggedImage] = []) {
        self.status = status
        self.usage = usage
        self.untagged = untagged
    }
}

/// Lecture (et, T4, nettoyage) de Docker par la commande `docker`, jamais par ses fichiers (ADR 0010). SYNCHRONE : à appeler hors de
/// l'acteur principal. Le lanceur n'a pas de valeur par défaut (ADR 0009) : un test ne lance jamais un vrai `docker` par mégarde.
enum DockerScanner {
    /// L'UNIQUE endroit du code Docker qui appelle le lanceur : seules les quatre commandes de la liste blanche y passent, avec un chemin absolu.
    fileprivate static func execute(_ command: DockerCommand, runner: CommandRunner, dockerPath: String) -> CommandOutcome {
        guard dockerPath.hasPrefix("/"), DockerCommand.isAllowed(command.arguments) else { return .refused(.notAbsolutePath) }
        return runner.run(executable: dockerPath, arguments: command.arguments, timeLimit: command.timeLimit, outputLimit: command.outputLimit)
    }

    /// Sortie d'une lecture réussie (code 0, fin ordinaire, sortie entière), ou l'état qui explique pourquoi pas.
    private static func readOutput(of command: DockerCommand, runner: CommandRunner, dockerPath: String) -> Result<Data, DockerScan.Status> {
        switch execute(command, runner: runner, dockerPath: dockerPath) {
        case .failedToLaunch: return .failure(.toolNotFound)
        case .refused: return .failure(.engineNotRunning)
        case .timedOut: return .failure(.timedOut)
        case .completed(let output):
            // La sortie d'erreur n'est ni analysée ni gardée (elle peut contenir des chemins personnels).
            // Tronquée : le lanceur a tué le processus (signal), ce n'est pas un moteur arrêté.
            if output.truncated { return .failure(.outputNotReadable) }
            if output.termination == .signaled || output.exitCode != 0 { return .failure(.engineNotRunning) }
            return .success(output.stdout)
        }
    }

    /// Lecture seule : `docker system df` puis la liste des images sans étiquette. Au premier échec, la seconde commande n'est pas lancée
    /// et le scan est en échec en entier (jamais un usage partiel).
    /// - Parameters:
    ///   - runner: sans valeur par défaut.
    ///   - dockerPath: chemin ABSOLU trouvé par `ToolLocator.dockerPath` ; `nil` : rien n'est lancé.
    static func list(runner: CommandRunner, dockerPath: String?) -> DockerScan {
        guard let dockerPath, dockerPath.hasPrefix("/") else { return DockerScan(status: .toolNotFound) }

        let usageData: Data
        switch readOutput(of: .usage, runner: runner, dockerPath: dockerPath) {
        case .failure(let status): return DockerScan(status: status)
        case .success(let data): usageData = data
        }
        guard let usage = DockerReport.parseUsage(usageData) else { return DockerScan(status: .outputNotReadable) }

        let untaggedData: Data
        switch readOutput(of: .untaggedImages, runner: runner, dockerPath: dockerPath) {
        case .failure(let status): return DockerScan(status: status)
        case .success(let data): untaggedData = data
        }
        guard let untagged = DockerReport.parseUntaggedImages(untaggedData) else { return DockerScan(status: .outputNotReadable) }
        return DockerScan(status: .ok, usage: usage, untagged: untagged)
    }
}

// MARK: - Nettoyage (deux commandes, après la confirmation)

/// Les deux seuls nettoyages (D1, D2).
enum DockerPrune: Equatable {
    /// `docker builder prune -a -f`
    case buildCache
    /// `docker image prune -f` (jamais `-a` : les images avec étiquette ne sont pas touchées)
    case untaggedImages

    var command: DockerCommand {
        switch self {
        case .buildCache: .pruneBuildCache
        case .untaggedImages: .pruneUntaggedImages
        }
    }
}

/// Résultat d'UN nettoyage (aucune lecture de la sortie d'erreur).
enum DockerPruneOutcome: Equatable {
    /// Code 0, fin ordinaire, sortie entière. `reportedBytes` : le chiffre que Docker annonce (`nil` s'il n'est pas lisible).
    case pruned(reportedBytes: UInt64?)
    /// Tout le reste : code non nul, signal, sortie tronquée, lancement impossible, refus.
    case failed
    /// Le délai est dépassé (le lanceur a tué le processus).
    case timedOut
    /// Pas de chemin absolu vers `docker` : rien n'est lancé.
    case toolNotFound
}

extension DockerScanner {
    /// Lance UN nettoyage, de façon synchrone (jamais sur l'acteur principal). À n'appeler qu'APRÈS la confirmation de l'utilisateur
    /// (R8) : c'est le modèle qui la demande. Rien d'autre n'est lancé : ni lecture avant, ni lecture après.
    /// - Parameters:
    ///   - runner: sans valeur par défaut (ADR 0009).
    ///   - dockerPath: chemin ABSOLU trouvé par `ToolLocator.dockerPath` ; `nil` : rien n'est lancé.
    static func prune(_ prune: DockerPrune, runner: CommandRunner, dockerPath: String?) -> DockerPruneOutcome {
        guard let dockerPath, dockerPath.hasPrefix("/") else { return .toolNotFound }
        switch execute(prune.command, runner: runner, dockerPath: dockerPath) {
        case .timedOut: return .timedOut
        case .failedToLaunch, .refused: return .failed
        case .completed(let output):
            // Seul « code 0, fin ordinaire, sortie entière » vaut succès.
            guard output.exitCode == 0, output.termination == .exited, !output.truncated else { return .failed }
            return .pruned(reportedBytes: DockerReport.parsePruneTotal(output.stdout))
        }
    }
}
