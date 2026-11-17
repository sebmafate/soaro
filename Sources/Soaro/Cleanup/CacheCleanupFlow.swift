import Foundation

/// Confirmer puis nettoyer des caches : le déroulé partagé par toutes les rangées de « Nettoyage » et par le nettoyage rapide.
///
/// Tout ce qui touche au monde (alerte, suppression, état occupé) est injecté, sans valeur par défaut,
/// pour que les tests répondent « Annuler » ou « Nettoyer » sans alerte ni disque.
@MainActor
enum CacheCleanupFlow {
    /// Demande la confirmation, tout de suite et sur l'acteur principal.
    /// - Annulé : renvoie `nil`. `clean` n'est jamais appelé, rien n'est affiché, `willStart` n'est pas appelé.
    /// - Confirmé, mode démo : `clean` n'est jamais appelé, rien n'est lu ni écrit. L'info annonce la somme des tailles
    ///   de démonstration des types, qui ne changent pas.
    /// - Confirmé : `willStart` est appelé une fois (l'appelant marque les rangées occupées), puis `clean` est appelé
    ///   une fois par type, dans l'ordre, hors de l'acteur principal. La tâche renvoie le texte à afficher.
    static func run(
        kinds: [CleanupKind],
        sizes: [CleanupKind: UInt64?],
        demo: Bool,
        confirm: ConfirmHandler,
        clean: @escaping @Sendable (CleanupKind) -> CleanupResult,
        willStart: @MainActor () -> Void
    ) -> Task<String, Never>? {
        let total = kinds.reduce(UInt64(0)) { $0 + ((sizes[$1] ?? nil) ?? 0) }
        var info = kinds.map { "• \($0.title)" }.joined(separator: "\n")
        if total > 0 { info += String(localized: "\n\nAbout \(Format.fileBytes(total)) will be freed.") }
        if kinds.contains(.trash) { info += String(localized: "\nEmptying the Trash is permanent.") }
        guard confirm(
            kinds.count == 1 ? String(localized: "Clean “\(kinds[0].title)”?") : String(localized: "Run the quick clean?"),
            info, String(localized: "Clean"), kinds.contains(.trash)
        ) else { return nil }

        if demo {
            // Mode démonstration : les chiffres sont inventés, aucune suppression n'a lieu.
            let message = String(localized: "\(Format.fileBytes(total)) freed")
            return Task { message }
        }

        willStart()
        return Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (freed: UInt64, failures: Int, errors: [String]) in
                var freed: UInt64 = 0
                var failures = 0
                var errors: [String] = []
                for kind in kinds {
                    let result = clean(kind)
                    freed += result.freed
                    failures += result.failures
                    if let error = result.error { errors.append("\(kind.title) : \(error)") }
                }
                return (freed, failures, errors)
            }.value

            if let first = outcome.errors.first { return first }
            var message = String(localized: "\(Format.fileBytes(outcome.freed)) freed")
            if outcome.failures > 0 { message += String(localized: " (\(outcome.failures) items in use were skipped)") }
            return message
        }
    }
}
