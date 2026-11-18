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
        /// SL16 : le contexte ou le constructeur courant n'est pas clairement LOCAL (tcp, ssh, npipe, autre pilote, réponse vide ou illisible).
        /// Soaro ne nettoie que Docker sur ce Mac : ni ligne, ni bouton, ni nettoyage.
        case notLocal
    }

    let status: Status
    let usage: DockerUsage?
    /// Images sans étiquette (toutes, y compris celles qu'un conteneur utilise : `isRemovable` tranche).
    let untagged: [DockerUntaggedImage]
    /// Le moteur local sur lequel on a listé (SL16) : celui que la confirmation nomme et que le nettoyage doit retrouver. `nil` hors de `.ok`.
    let engine: DockerEngine?

    init(status: Status, usage: DockerUsage? = nil, untagged: [DockerUntaggedImage] = [], engine: DockerEngine? = nil) {
        self.status = status
        self.usage = usage
        self.untagged = untagged
        self.engine = engine
    }
}

/// Lecture (et, T4, nettoyage) de Docker par la commande `docker`, jamais par ses fichiers (ADR 0010). SYNCHRONE : à appeler hors de
/// l'acteur principal. Le lanceur n'a pas de valeur par défaut (ADR 0009) : un test ne lance jamais un vrai `docker` par mégarde.
enum DockerScanner {
    /// L'UNIQUE endroit du code Docker qui appelle le lanceur : seules les six commandes de la liste blanche y passent, avec un chemin absolu,
    /// et TOUJOURS sans les variables d'environnement qui désignent un autre moteur ou un autre constructeur (SL16).
    fileprivate static func execute(_ command: DockerCommand, runner: CommandRunner, dockerPath: String) -> CommandOutcome {
        guard dockerPath.hasPrefix("/"), DockerCommand.isAllowed(command.arguments) else { return .refused(.notAbsolutePath) }
        return runner.run(executable: dockerPath, arguments: command.arguments, timeLimit: command.timeLimit, outputLimit: command.outputLimit,
                          removingEnvironment: DockerCommand.removedEnvironment)
    }

    /// Sortie d'une lecture du moteur : le texte, ou l'état qui explique pourquoi pas. Tout échec REFUSE (échec fermé) ; le seul délai garde son nom.
    private static func readEngineOutput(of command: DockerCommand, runner: CommandRunner, dockerPath: String) -> Result<Data, DockerEngineCheck> {
        switch execute(command, runner: runner, dockerPath: dockerPath) {
        case .failedToLaunch: return .failure(.toolNotFound)
        case .refused: return .failure(.notLocal)
        case .timedOut: return .failure(.timedOut)
        case .completed(let output):
            if output.truncated || output.termination == .signaled || output.exitCode != 0 { return .failure(.notLocal) }
            return .success(output.stdout)
        }
    }

    /// Lit le contexte puis le constructeur COURANTS (deux lectures seules) : seul un moteur local (prise `unix://`) avec un constructeur au pilote
    /// `docker` passe. Au premier refus, la seconde lecture n'a pas lieu. Un moteur local arrêté n'est PAS un refus : `.notRunning`.
    /// Ordre voulu : le contexte se lit dans des fichiers (il marche moteur arrêté), le constructeur dit ensuite si le moteur répond ; ainsi un
    /// moteur local arrêté garde le message « Docker is not running », et un moteur distant n'est jamais interrogé plus loin.
    static func checkEngine(runner: CommandRunner, dockerPath: String?) -> DockerEngineCheck {
        guard let dockerPath, dockerPath.hasPrefix("/") else { return .toolNotFound }
        let engine: DockerEngine
        switch readEngineOutput(of: .currentContext, runner: runner, dockerPath: dockerPath) {
        case .failure(let check): return check
        case .success(let data):
            guard let parsed = DockerEngineReport.parseContext(data) else { return .notLocal }
            engine = parsed
        }
        switch readEngineOutput(of: .currentBuilder, runner: runner, dockerPath: dockerPath) {
        case .failure(let check): return check
        case .success(let data):
            switch DockerEngineReport.parseBuilder(data, contextName: engine.contextName) {
            case .local: return .local(engine)
            case .notLocal: return .notLocal
            case .unreachable: return .notRunning
            }
        }
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

    /// Lecture seule : le moteur et le constructeur courants (SL16 : seul un moteur local passe), puis `docker system df`, puis la liste des images
    /// sans étiquette. Au premier échec, la suite n'est pas lancée et le scan est en échec en entier (jamais un usage partiel).
    /// - Parameters:
    ///   - runner: sans valeur par défaut.
    ///   - dockerPath: chemin ABSOLU trouvé par `ToolLocator.dockerPath` ; `nil` : rien n'est lancé.
    static func list(runner: CommandRunner, dockerPath: String?) -> DockerScan {
        guard let dockerPath, dockerPath.hasPrefix("/") else { return DockerScan(status: .toolNotFound) }

        let engine: DockerEngine
        switch checkEngine(runner: runner, dockerPath: dockerPath) {
        case .local(let found): engine = found
        case .notLocal: return DockerScan(status: .notLocal)
        case .notRunning: return DockerScan(status: .engineNotRunning)
        case .timedOut: return DockerScan(status: .timedOut)
        case .toolNotFound: return DockerScan(status: .toolNotFound)
        }

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
        return DockerScan(status: .ok, usage: usage, untagged: untagged, engine: engine)
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
    /// SL16 : juste avant le nettoyage, le moteur ou le constructeur n'est plus clairement local (ou illisible) : rien n'a été lancé.
    case notLocal
}

extension DockerScanner {
    /// Lance UN nettoyage, de façon synchrone (jamais sur l'acteur principal). À n'appeler qu'APRÈS la confirmation de l'utilisateur
    /// (R8) : c'est le modèle qui la demande. SL16 : JUSTE AVANT, le contexte et le constructeur courants sont relus (deux lectures seules) ;
    /// le nettoyage ne part que si le moteur est local ET le même que celui que la confirmation a nommé. Sinon rien n'est lancé :
    /// `.notLocal` (distant, illisible), `.timedOut`, `.toolNotFound`, ou `.failed` (moteur arrêté, ou un AUTRE moteur local). Rien après.
    /// - Parameters:
    ///   - runner: sans valeur par défaut (ADR 0009).
    ///   - dockerPath: chemin ABSOLU trouvé par `ToolLocator.dockerPath` ; `nil` : rien n'est lancé.
    ///   - expectedEngine: le moteur nommé dans la confirmation ; sans valeur par défaut (un appelant ne peut pas l'oublier).
    static func prune(_ prune: DockerPrune, runner: CommandRunner, dockerPath: String?, expectedEngine: DockerEngine) -> DockerPruneOutcome {
        guard let dockerPath, dockerPath.hasPrefix("/") else { return .toolNotFound }
        switch checkEngine(runner: runner, dockerPath: dockerPath) {
        case .local(let current): if current != expectedEngine { return .failed }
        case .notLocal: return .notLocal
        case .notRunning: return .failed
        case .timedOut: return .timedOut
        case .toolNotFound: return .failed
        }
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
