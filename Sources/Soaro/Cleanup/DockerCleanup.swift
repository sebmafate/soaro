import Foundation

/// Un nettoyage demandé, avec le chiffre annoncé avant (la taille de la ligne cochée) : il sert de repli quand Docker n'imprime pas son total.
struct DockerCleanupTarget: Equatable {
    let prune: DockerPrune
    let announcedBytes: UInt64?
}

/// Bilan d'un lot de nettoyages et texte du toast (R11, D3) : tout est PUR (locale explicite).
struct DockerCleanupResult: Equatable {
    /// Nettoyages réussis.
    let succeededCount: Int
    /// Nettoyages en échec (le lot s'arrête au premier échec : 0 ou 1).
    let failedCount: Int
    /// Un délai dépassé a arrêté le lot.
    let timedOut: Bool
    /// Le chiffre de Docker : la somme des totaux annoncés par les nettoyages réussis (à défaut, le chiffre d'avant la commande) ;
    /// `nil` quand l'un d'eux est inconnu.
    let dockerBytes: UInt64?
    /// Ce qui est vraiment revenu sur le Mac : espace libre après moins espace libre avant, PLANCHER À ZÉRO ; `nil` quand rien n'a réussi
    /// ou quand l'espace libre n'a pas pu être lu.
    let returnedBytes: UInt64?

    /// Texte du toast, morceaux joints par « · ». Chaîne VIDE quand il n'y a rien à dire.
    /// - Un nettoyage réussi : le chiffre mesuré sur le Mac, avec celui de Docker ; à moins de la moitié de celui de Docker, le texte dit
    ///   que l'image disque n'a pas rendu l'espace (ce n'est PAS une garantie : c'est une mesure de l'espace libre).
    /// - Puis : un délai dépassé → « Docker did not answer… » ; sinon des échecs → leur nombre.
    func toast(locale: Locale = .current) -> String {
        var parts: [String] = []
        if succeededCount > 0 {
            switch (returnedBytes, dockerBytes) {
            case let (returned?, docker?):
                let (r, d) = (Format.fileBytes(returned, locale: locale), Format.fileBytes(docker, locale: locale))
                if docker > 0, returned * 2 < docker {
                    parts.append(String(localized: "\(r) returned to this Mac, but Docker reported \(d): Docker’s disk image did not give the space back.", locale: locale))
                } else {
                    parts.append(String(localized: "\(r) returned to this Mac (Docker reported \(d)).", locale: locale))
                }
            case let (returned?, nil):
                parts.append(String(localized: "\(Format.fileBytes(returned, locale: locale)) returned to this Mac.", locale: locale))
            case let (nil, docker?):
                parts.append(String(localized: "Docker reported \(Format.fileBytes(docker, locale: locale)). The space returned to this Mac could not be measured.", locale: locale))
            case (nil, nil):
                parts.append(String(localized: "The space returned to this Mac could not be measured.", locale: locale))
            }
        }
        if timedOut {
            parts.append(String(localized: "Docker did not answer. Try again in a moment.", locale: locale))
        } else if failedCount > 0 {
            parts.append(String(localized: "Cleanups that failed: \(failedCount)", locale: locale))
        }
        return parts.joined(separator: " · ")
    }
}

/// Espace libre du volume qui porte un dossier (celui du dossier personnel : le volume de données, comme `df -k ~`).
enum DockerFreeSpace {
    /// Octets disponibles, `nil` si illisible. `statfs` : l'espace réellement libre, sans compter ce que macOS pourrait purger.
    static func available(at folder: URL) -> UInt64? {
        var stats = statfs()
        guard statfs(folder.path, &stats) == 0 else { return nil }
        return UInt64(stats.f_bavail) * UInt64(stats.f_bsize)
    }
}

/// Le lot : relevé de l'espace libre, nettoyages, attente, second relevé (R11). `async` pour que l'attente soit injectable : un test n'attend
/// jamais 60 s. Les nettoyages sont synchrones (le lanceur l'est) : à appeler depuis une tâche détachée, jamais depuis l'acteur principal.
enum DockerCleanupFlow {
    /// Attente avant le second relevé (D3) : SPK-002 a vu 73 % revenir tout de suite et 95 % après une minute.
    static let measureDelay: TimeInterval = 60

    /// - Parameters:
    ///   - targets: les nettoyages, dans l'ordre. Le lot s'arrête au premier échec ou délai dépassé : rien d'autre ne tourne.
    ///   - runner: sans valeur par défaut (ADR 0009).
    ///   - freeSpace: espace libre du volume du dossier personnel, lu avant le premier nettoyage puis après l'attente ; jamais lu sans nettoyage.
    ///   - beforeWait: appelé juste avant l'attente (l'écran passe à « Measuring… »).
    ///   - wait: l'attente (une vraie en production, aucune dans les tests).
    static func run(targets: [DockerCleanupTarget],
                    runner: CommandRunner,
                    dockerPath: String?,
                    freeSpace: @Sendable () -> UInt64?,
                    beforeWait: @Sendable () async -> Void,
                    wait: @Sendable (TimeInterval) async -> Void) async -> DockerCleanupResult {
        let before = freeSpace()
        var succeeded = 0, failed = 0
        var timedOut = false
        var figures: [UInt64?] = []
        for target in targets {
            switch DockerScanner.prune(target.prune, runner: runner, dockerPath: dockerPath) {
            case .pruned(let reported):
                succeeded += 1
                figures.append(reported ?? target.announcedBytes)
            case .timedOut: timedOut = true
            case .failed, .toolNotFound: failed += 1
            }
            if timedOut || failed > 0 { break }
        }

        var returned: UInt64?
        if succeeded > 0 {
            await beforeWait()
            await wait(measureDelay)
            if let before, let after = freeSpace() { returned = after > before ? after - before : 0 }
        }
        let known = figures.compactMap { $0 }
        let docker: UInt64? = !figures.isEmpty && known.count == figures.count ? known.reduce(0, +) : nil
        return DockerCleanupResult(succeededCount: succeeded, failedCount: failed, timedOut: timedOut, dockerBytes: docker, returnedBytes: returned)
    }
}
