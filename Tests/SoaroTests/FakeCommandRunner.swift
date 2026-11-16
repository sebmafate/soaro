import Foundation
import Testing
@testable import Soaro

/// Faux lanceur écrit à la main (pas de bibliothèque de mocks) : il rend le résultat prévu
/// pour chaque commande, note chaque appel, et ne lance JAMAIS de vrai processus.
/// « Délai dépassé » est rendu tout de suite, sans dormir.
/// Un appel non prévu est un échec bruyant du test (`Issue.record`) et rend « lancement impossible ».
final class FakeCommandRunner: CommandRunner {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let timeLimit: TimeInterval
        let outputLimit: Int
    }

    private struct Key: Hashable {
        let executable: String
        let arguments: [String]
    }

    private var scripts: [Key: CommandOutcome] = [:]
    private(set) var calls: [Call] = []
    private(set) var unscriptedCalls: [Call] = []

    /// Réaction à un appel non prévu. Par défaut : le test échoue. Un test peut la remplacer pour vérifier le signalement.
    var reportUnscripted: (String) -> Void = { description in
        Issue.record("Appel non prévu au faux lanceur : \(description)")
    }

    func script(_ outcome: CommandOutcome, executable: String, arguments: [String]) {
        scripts[Key(executable: executable, arguments: arguments)] = outcome
    }

    func run(executable: String, arguments: [String], timeLimit: TimeInterval, outputLimit: Int) -> CommandOutcome {
        let call = Call(executable: executable, arguments: arguments, timeLimit: timeLimit, outputLimit: outputLimit)
        calls.append(call)
        guard let outcome = scripts[Key(executable: executable, arguments: arguments)] else {
            unscriptedCalls.append(call)
            reportUnscripted("\(executable) \(arguments.joined(separator: " "))")
            return .failedToLaunch
        }
        return outcome
    }
}

extension CommandOutcome {
    /// Raccourci de test : commande terminée avec un code et un texte de sortie.
    static func finished(exit code: Int32 = 0, stdout: String = "", stderr: String = "", truncated: Bool = false) -> CommandOutcome {
        .completed(CommandOutput(exitCode: code, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8), truncated: truncated))
    }
}
