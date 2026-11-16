import Foundation

/// Sortie d'une commande terminée. `truncated` : la sortie (standard ou d'erreur) a dépassé la borne et a été coupée.
/// La sortie d'erreur ne doit jamais être montrée telle quelle à l'utilisateur.
struct CommandOutput: Equatable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
    let truncated: Bool
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
}
