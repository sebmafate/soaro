import Foundation

/// Comment un processus s'est terminé.
enum CommandTermination: Equatable {
    /// Sortie ordinaire : `exitCode` est le code de sortie du programme.
    case exited
    /// Fin par un signal (tué par le lanceur, ou plantage) : `exitCode` contient alors le NUMÉRO du signal
    /// (9 pour SIGKILL), pas un code de sortie ordinaire.
    case signaled
}

/// Sortie d'une commande terminée. `truncated` : la sortie (standard ou d'erreur) a dépassé la borne et a été coupée
/// (le processus a alors été tué : `termination` vaut `.signaled`).
/// La sortie d'erreur ne doit jamais être montrée telle quelle à l'utilisateur.
struct CommandOutput: Equatable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
    let truncated: Bool
    let termination: CommandTermination

    init(exitCode: Int32, stdout: Data, stderr: Data, truncated: Bool, termination: CommandTermination = .exited) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.truncated = truncated
        self.termination = termination
    }
}

/// Raison pour laquelle un lanceur refuse de démarrer une commande (avant tout lancement).
enum CommandRefusal: Equatable {
    /// Chemin vide ou relatif : seuls les chemins absolus sont acceptés (ni PATH, ni dossier courant).
    case notAbsolutePath
    /// Interpréteur de commandes (`sh`, `bash`, `zsh`…) ou `env` (qui cherche dans le PATH).
    case shell
}

/// Résultat d'une commande.
enum CommandOutcome: Equatable {
    case completed(CommandOutput)
    case timedOut
    case failedToLaunch
    case refused(CommandRefusal)
}

/// Lance un programme externe, de façon synchrone, avec un délai et une sortie bornés (ADR 0009).
///
/// Il n'existe volontairement PAS de lanceur par défaut : un scanner ou un suppresseur reçoit
/// son lanceur sans valeur par défaut, pour qu'un test ne lance jamais un vrai outil par mégarde.
/// Le vrai lanceur n'est construit qu'à un seul endroit : `Diagnostics.scan` (puis l'application, plus tard).
protocol CommandRunner {
    /// - Parameters:
    ///   - executable: chemin ABSOLU du programme.
    ///   - arguments: arguments un par un, jamais assemblés dans une chaîne.
    ///   - timeLimit: durée maximale en secondes ; au-delà le processus est tué.
    ///   - outputLimit: nombre maximal d'octets conservés, par flux (standard, erreur).
    func run(executable: String, arguments: [String], timeLimit: TimeInterval, outputLimit: Int) -> CommandOutcome

    /// Comme `run`, sans transmettre au programme les variables d'environnement nommées dans `removingEnvironment` (SL16 : `DOCKER_HOST`…).
    /// Tout le reste de l'environnement de l'application est hérité, comme avant ; liste vide : exactement `run` à quatre arguments.
    /// La réalisation par défaut REFUSE de lancer quand la liste n'est pas vide (`.failedToLaunch`) : un lanceur qui ne sait pas retirer
    /// une variable ne la transmet jamais en silence. Seuls `RealCommandRunner` et le faux lanceur des tests la réalisent.
    func run(executable: String, arguments: [String], timeLimit: TimeInterval, outputLimit: Int,
             removingEnvironment: [String]) -> CommandOutcome
}

extension CommandRunner {
    func run(executable: String, arguments: [String], timeLimit: TimeInterval, outputLimit: Int,
             removingEnvironment: [String]) -> CommandOutcome {
        guard removingEnvironment.isEmpty else { return .failedToLaunch }
        return run(executable: executable, arguments: arguments, timeLimit: timeLimit, outputLimit: outputLimit)
    }
}
