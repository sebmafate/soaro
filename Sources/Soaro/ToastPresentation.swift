import AppKit
import Foundation

/// Règles pures du toast (SL5) : aucune dépendance à SwiftUI ni à l'état de l'app, donc testables telles quelles.
/// Le texte du toast ne change jamais ; seuls son mouvement et son annonce vocale dépendent des réglages d'accessibilité.
enum ToastPresentation {
    /// Mouvement du toast à l'apparition et à la disparition.
    enum MotionStyle: Equatable {
        /// Glissement depuis le bas avec fondu (comportement par défaut).
        case slideAndFade
        /// Fondu seul, sans déplacement (Réduire les animations activé).
        case fade
    }

    /// Durée d'affichage, la même pour tout le monde (règle « visible 4 s » de DESIGN.md).
    static let visibleDuration: Duration = .seconds(4)

    static func motionStyle(reduceMotion: Bool) -> MotionStyle {
        reduceMotion ? .fade : .slideAndFade
    }

    /// Texte lu par VoiceOver : le message tel quel (déjà traduit), sans préfixe. `nil` si le message est vide ou blanc.
    static func announcement(for message: String) -> String? {
        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : message
    }
}

/// Annonceur réel : demande à VoiceOver de lire le message, avec une priorité haute pour qu'un changement de focus
/// ne la coupe pas. Voie AppKit (`NSAccessibility`), la même dans le panneau et dans la fenêtre.
enum ToastAnnouncer {
    @MainActor static func announce(_ text: String) {
        // Sans application (processus de tests), il n'y a personne à qui parler.
        guard let app = NSApp else { return }
        NSAccessibility.post(
            element: app,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
    }
}
