import Foundation

/// Disposition de l'écran « Docker » (S4) : fonctions PURES, testables sans vue.
enum DockerScreen {
    enum Layout: Equatable {
        /// Attente : « Looking at Docker… », ou « Cleaning… » / « Measuring… » quand un lot tourne (même lancé ailleurs).
        case spinner
        /// Un message sur tout l'écran : `warning` pour un échec (moteur arrêté, muet, illisible), sinon une information (docker introuvable).
        case hint(warning: Bool)
        /// Les lignes : à nettoyer, puis en lecture seule.
        case list
    }

    static func layout(phase: DockerModel.Phase) -> Layout {
        switch phase {
        case .notScanned, .listing: .spinner
        case .hidden: .hint(warning: false)
        case .failed: .hint(warning: true)
        case .listed: .list
        }
    }

    /// La barre d'action (« Clean ») s'affiche quand la liste a quelque chose à nettoyer.
    static func showsActionBar(layout: Layout, hasCleanables: Bool) -> Bool {
        layout == .list && hasCleanables
    }

    /// La rangée « Docker » de la liste des outils : seulement quand `docker` a été trouvé sur le disque (jamais en le lançant), ou en mode démo.
    /// `nil` tant que la détection n'a pas eu lieu : la rangée n'apparaît pas.
    static func showsToolsRow(dockerPath: String?, demo: Bool) -> Bool {
        demo || dockerPath != nil
    }
}
