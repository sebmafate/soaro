import Foundation

/// Une ligne que l'on peut cocher : le cache de build ou les images sans étiquette (R10, D1, D2). Rien d'autre n'existe.
struct DockerCleanable: Equatable {
    let prune: DockerPrune
    /// Taille annoncée (cache : `Reclaimable` de Docker ; images : somme de leurs tailles) ; `nil` quand elle est inconnue.
    let size: UInt64?
    /// Nombre d'images (ligne des images seulement).
    let count: Int?
}

/// La ligne en lecture seule des autres images inutilisées (D2) : ni case, ni suppression.
struct DockerOtherImages: Equatable {
    let count: Int?
    let size: UInt64?
}

/// Ce que l'écran montre d'un listage (R10, D2) : fonction PURE de `DockerScan`, testable sans modèle ni lanceur.
struct DockerOverview: Equatable {
    /// Lignes cochables, dans l'ordre : cache de build, puis images sans étiquette.
    let cleanables: [DockerCleanable]
    /// La taille du cache de build est illisible ou la ligne manque : une ligne en lecture seule le dit (jamais une case).
    let buildCacheSizeUnknown: Bool
    /// Lignes en lecture seule : conteneurs et volumes (jamais touchés), chiffres de Docker.
    let containers: DockerUsageLine
    let volumes: DockerUsageLine
    /// Les autres images inutilisées, `nil` quand il n'y en a aucune.
    let otherUnusedImages: DockerOtherImages?

    private static let emptyLine = DockerUsageLine(total: nil, active: nil, size: nil, reclaimable: nil)

    /// Somme des tailles connues des lignes cochables.
    var cleanableTotal: UInt64 { cleanables.reduce(0) { $0 + ($1.size ?? 0) } }

    static func make(_ scan: DockerScan) -> DockerOverview {
        guard scan.status == .ok, let usage = scan.usage else {
            return DockerOverview(cleanables: [], buildCacheSizeUnknown: false, containers: emptyLine, volumes: emptyLine, otherUnusedImages: nil)
        }
        var cleanables: [DockerCleanable] = []
        var cacheUnknown = false
        if let reclaimable = usage.buildCache?.reclaimable {
            if reclaimable > 0 { cleanables.append(DockerCleanable(prune: .buildCache, size: reclaimable, count: nil)) }
        } else {
            cacheUnknown = true
        }

        // Une image qu'un conteneur utilise (ou dont l'usage est inconnu) n'est jamais dans la liste à nettoyer.
        let removable = scan.untagged.filter(\.isRemovable)
        let removableSizes = removable.map(\.size)
        let removableSize: UInt64? = removableSizes.allSatisfy({ $0 != nil }) ? removableSizes.compactMap { $0 }.reduce(0, +) : nil
        if !removable.isEmpty {
            cleanables.append(DockerCleanable(prune: .untaggedImages, size: removableSize, count: removable.count))
        }

        var other: DockerOtherImages?
        if let images = usage.images {
            let count: Int? = images.total.flatMap { total in
                images.active.map { active in max(0, max(0, total - active) - removable.count) }
            }
            let size: UInt64? = images.reclaimable.flatMap { reclaimable in
                removableSize.map { reclaimable > $0 ? reclaimable - $0 : 0 }
            }
            if (count ?? 0) > 0 || (size ?? 0) > 0 { other = DockerOtherImages(count: count, size: size) }
        }
        return DockerOverview(cleanables: cleanables, buildCacheSizeUnknown: cacheUnknown,
                              containers: usage.containers ?? emptyLine, volumes: usage.volumes ?? emptyLine, otherUnusedImages: other)
    }
}
