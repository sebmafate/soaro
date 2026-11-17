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

    /// Résultats prévus par commande, dans l'ordre ; `next` : rang du prochain à rendre. Le dernier se répète.
    private struct Script {
        var outcomes: [CommandOutcome]
        var next = 0
    }

    private var scripts: [Key: Script] = [:]
    private(set) var calls: [Call] = []
    private(set) var unscriptedCalls: [Call] = []

    /// Réaction à un appel non prévu. Par défaut : le test échoue. Un test peut la remplacer pour vérifier le signalement.
    var reportUnscripted: (String) -> Void = { description in
        Issue.record("Appel non prévu au faux lanceur : \(description)")
    }

    /// Un seul résultat, rendu à chaque appel (comportement d'origine). Remplace tout script précédent de la commande.
    func script(_ outcome: CommandOutcome, executable: String, arguments: [String]) {
        script(sequence: [outcome], executable: executable, arguments: arguments)
    }

    /// Une suite de résultats pour une même commande : chaque appel rend le suivant, et le dernier se répète
    /// (p. ex. `simctl list` appelé pour le scan, avant chaque suppression, puis pour le nouveau scan).
    /// Remplace tout script précédent de la commande.
    func script(sequence outcomes: [CommandOutcome], executable: String, arguments: [String]) {
        precondition(!outcomes.isEmpty, "une suite de résultats ne peut pas être vide")
        scripts[Key(executable: executable, arguments: arguments)] = Script(outcomes: outcomes)
    }

    func run(executable: String, arguments: [String], timeLimit: TimeInterval, outputLimit: Int) -> CommandOutcome {
        let call = Call(executable: executable, arguments: arguments, timeLimit: timeLimit, outputLimit: outputLimit)
        calls.append(call)
        let key = Key(executable: executable, arguments: arguments)
        guard var script = scripts[key] else {
            unscriptedCalls.append(call)
            reportUnscripted("\(executable) \(arguments.joined(separator: " "))")
            return .failedToLaunch
        }
        let outcome = script.outcomes[min(script.next, script.outcomes.count - 1)]
        script.next += 1
        scripts[key] = script
        return outcome
    }
}

extension CommandOutcome {
    /// Raccourci de test : commande terminée avec un code et un texte de sortie.
    static func finished(exit code: Int32 = 0, stdout: String = "", stderr: String = "", truncated: Bool = false,
                         termination: CommandTermination = .exited) -> CommandOutcome {
        .completed(CommandOutput(exitCode: code, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8), truncated: truncated,
                                 termination: termination))
    }
}
