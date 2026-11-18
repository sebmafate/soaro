import Foundation

/// La liste blanche des commandes `docker` de Soaro (SL13, R10, ADR 0010, ADR 0009) : exactement quatre, de trois familles.
/// 1. l'usage : `docker system df --format {{json .}}` (lecture seule) ;
/// 2. la liste des images sans étiquette : `docker images -f dangling=true --format {{json .}}` (lecture seule) ;
/// 3. les deux nettoyages : `docker builder prune -a -f` (décision D1, la seule commande mesurée par SPK-002) et
///    `docker image prune -f` (décision D2 : jamais `-a`).
/// Rien d'autre n'existe dans le code : aucune autre commande n'est construite ni lancée, et tout lancement passe par
/// `DockerScanner` (un seul appel au lanceur). Un test de source surveille les mots interdits dans les fichiers Docker.
enum DockerCommand: CaseIterable, Equatable {
    case usage
    case untaggedImages
    case pruneBuildCache
    case pruneUntaggedImages

    /// Arguments exacts, un par un (jamais une chaîne assemblée, jamais un shell).
    var arguments: [String] {
        switch self {
        case .usage: ["system", "df", "--format", "{{json .}}"]
        case .untaggedImages: ["images", "-f", "dangling=true", "--format", "{{json .}}"]
        case .pruneBuildCache: ["builder", "prune", "-a", "-f"]
        case .pruneUntaggedImages: ["image", "prune", "-f"]
        }
    }

    /// Seuls les deux nettoyages changent quelque chose.
    var isDestructive: Bool {
        switch self {
        case .usage, .untaggedImages: false
        case .pruneBuildCache, .pruneUntaggedImages: true
        }
    }

    /// Délai : 30 s pour une lecture ; 300 s pour un nettoyage (SPK-002 : 43 s pour 22 Go de cache).
    var timeLimit: TimeInterval { isDestructive ? 300 : 30 }

    /// Borne de la sortie, par flux : 1 Mio pour une lecture ; 4 Mio pour un nettoyage (qui liste un identifiant par enregistrement :
    /// une sortie coupée ferait tuer la commande en cours de route).
    var outputLimit: Int { isDestructive ? 4 * 1024 * 1024 : 1024 * 1024 }

    /// Ces arguments sont-ils exactement ceux d'une des quatre commandes ?
    static func isAllowed(_ arguments: [String]) -> Bool {
        allCases.contains { $0.arguments == arguments }
    }
}
