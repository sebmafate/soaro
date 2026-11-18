import Foundation

/// La liste blanche des commandes `docker` de Soaro (SL13, SL16, R10, ADR 0010, ADR 0009) : exactement six, de quatre familles.
/// 0. SL16, lectures seules qui disent OÙ le nettoyage tournerait : `docker context inspect` (sans nom : le contexte COURANT, son nom et
///    son point d'accès) et `docker buildx inspect` (sans nom : le constructeur COURANT et son pilote, sans `--bootstrap` : rien n'est démarré).
///    Seul un moteur local est accepté (voir `DockerEngineReport`) ; jamais `context use`, `buildx use`, `buildx create`, `buildx rm`.
///    `buildx inspect` plutôt que `buildx ls` : `ls` interroge TOUS les constructeurs connus, y compris des machines distantes.
/// 1. l'usage : `docker system df --format {{json .}}` (lecture seule) ;
/// 2. la liste des images sans étiquette : `docker images -f dangling=true --format {{json .}}` (lecture seule) ;
/// 3. les deux nettoyages : `docker builder prune -a -f` (décision D1, la seule commande mesurée par SPK-002) et
///    `docker image prune -f` (décision D2 : jamais `-a`).
/// Rien d'autre n'existe dans le code : aucune autre commande n'est construite ni lancée, et tout lancement passe par
/// `DockerScanner` (un seul appel au lanceur, avec les variables d'environnement retirées). Un test de source surveille les mots interdits dans les fichiers Docker.
enum DockerCommand: CaseIterable, Equatable {
    case usage
    case untaggedImages
    case pruneBuildCache
    case pruneUntaggedImages
    /// SL16 : le contexte Docker courant (lecture seule, ne se connecte à rien).
    case currentContext
    /// SL16 : le constructeur buildx courant (lecture seule ; se connecte, au plus, au moteur de ce constructeur).
    case currentBuilder

    /// SL16 : variables d'environnement JAMAIS transmises à `docker` : elles désignent un autre moteur (`DOCKER_HOST`, `DOCKER_CONTEXT`, `DOCKER_CERT_PATH`,
    /// `DOCKER_TLS_VERIFY`) ou un autre constructeur (`BUILDX_BUILDER`). Une application ouverte depuis le Finder n'a pas l'environnement d'un
    /// terminal, mais un lancement depuis un terminal l'a. Tout le reste (HOME…) est hérité.
    static let removedEnvironment = ["DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_CERT_PATH", "DOCKER_TLS_VERIFY", "BUILDX_BUILDER"]

    /// Arguments exacts, un par un (jamais une chaîne assemblée, jamais un shell).
    var arguments: [String] {
        switch self {
        case .usage: ["system", "df", "--format", "{{json .}}"]
        case .untaggedImages: ["images", "-f", "dangling=true", "--format", "{{json .}}"]
        case .pruneBuildCache: ["builder", "prune", "-a", "-f"]
        case .pruneUntaggedImages: ["image", "prune", "-f"]
        case .currentContext: ["context", "inspect"]
        case .currentBuilder: ["buildx", "inspect"]
        }
    }

    /// Seuls les deux nettoyages changent quelque chose.
    var isDestructive: Bool {
        switch self {
        case .usage, .untaggedImages, .currentContext, .currentBuilder: false
        case .pruneBuildCache, .pruneUntaggedImages: true
        }
    }

    /// Délai : 30 s pour une lecture ; 300 s pour un nettoyage (SPK-002 : 43 s pour 22 Go de cache).
    var timeLimit: TimeInterval { isDestructive ? 300 : 30 }

    /// Borne de la sortie, par flux : 1 Mio pour une lecture ; 4 Mio pour un nettoyage (qui liste un identifiant par enregistrement :
    /// une sortie coupée ferait tuer la commande en cours de route).
    var outputLimit: Int { isDestructive ? 4 * 1024 * 1024 : 1024 * 1024 }

    /// Ces arguments sont-ils exactement ceux d'une des six commandes ?
    static func isAllowed(_ arguments: [String]) -> Bool {
        allCases.contains { $0.arguments == arguments }
    }
}
