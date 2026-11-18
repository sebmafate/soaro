import SwiftUI

/// SL20 : le bouton de la barre d'outils qui replie et rouvre la barre latérale de la fenêtre indépendante.
///
/// La fenêtre est un `NSHostingController` créé à la main : le système n'y ajoute pas de bouton de barre latérale (constaté, voir PLAN.md),
/// d'où ce bouton explicite. Rien n'est mémorisé : la barre latérale est ouverte à chaque ouverture de la fenêtre. Pas de raccourci clavier
/// (garde-fou R8 : aucune vue ne lie de raccourci ; l'app n'a pas de menu où le mettre).
enum SidebarToggle {
    /// Clé du catalogue : étiquette VoiceOver et info-bulle du bouton (le bouton écrit le même littéral, pour l'extraction des textes).
    static let labelKey = "Toggle Sidebar"

    static let initialVisibility = NavigationSplitViewVisibility.all

    /// Replié = seul le détail est visible. Tout autre état (`.all`, `.doubleColumn`, `.automatic`) montre la barre latérale.
    static func isCollapsed(_ visibility: NavigationSplitViewVisibility) -> Bool {
        visibility == .detailOnly
    }

    static func toggled(_ visibility: NavigationSplitViewVisibility) -> NavigationSplitViewVisibility {
        isCollapsed(visibility) ? .all : .detailOnly
    }

    /// L'animation par défaut du système, sauf si « Réduire les animations » est actif.
    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .default
    }
}
