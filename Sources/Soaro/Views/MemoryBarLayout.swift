import Foundation

/// Genre d'usage d'un segment de la barre mémoire, dans l'ordre où ils se dessinent de gauche à droite.
enum MemorySegmentKind: Int, CaseIterable, Equatable {
    /// Applications (mémoire des processus, hors purgeable).
    case app
    /// Système (mémoire câblée, « wired »).
    case wired
    /// Mémoire compressée.
    case compressed
    /// Utilisée, mais que les catégories connues n'expliquent pas (écart de mesure au-delà de la tolérance).
    case unattributed
    /// Cache libérable : n'entre PAS dans la mémoire « utilisée ».
    case cached
}

/// Calcul pur de la barre mémoire segmentée (SL26) : des octets en plages de pixels entiers.
///
/// Règles :
/// - La piste représente la RAM totale ; chaque largeur est proportionnelle aux octets sur le TOTAL (pas sur « utilisé »).
/// - Ordre : applications, système, compressée, (non attribué), puis le cache. Le reste de la piste est libre.
/// - Les trois catégories « utilisées » doivent sommer à « utilisé » : si l'écart est d'au plus 2 % du total
///   (arrondis, mesures prises à des instants proches), elles sont mises à l'échelle pour que la somme soit exactement
///   « utilisé » (ni trou ni dépassement) ; au-delà, on dessine ce qu'on a, sans déformer : un manque devient un segment
///   « non attribué » neutre, un excès est dessiné tel quel. Dans tous les cas la somme ne dépasse jamais le total.
/// - Le cache est borné à la place libre.
/// - Les frontières sont des pixels entiers (arrondi des cumuls, donc pas de dérive) ; la piste mesure `floor(largeur x échelle)`
///   pixels ; un segment non vide fait au moins 1 pixel, ce qui est repris sur le plus large si besoin pour que la somme
///   ne dépasse jamais la piste ; un séparateur de `gapPixels` pixels est ôté à droite de chaque segment suivi d'un autre
///   (sauf si le segment n'aurait alors plus de pixel).
/// - Sans total (0 ou absent), ou sans largeur valide : aucun segment.
struct MemoryBarLayout: Equatable {
    struct Segment: Equatable {
        var kind: MemorySegmentKind
        /// Octets représentés (après mise à l'échelle éventuelle).
        var bytes: Double
        /// Premier pixel dessiné.
        var startPixel: Int
        /// Pixel après le dernier pixel dessiné.
        var endPixel: Int
        var width: Int { endPixel - startPixel }
    }

    /// Largeur de la piste en pixels de l'appareil.
    var trackPixels: Int
    var segments: [Segment]

    static let attributionTolerance = 0.02
    static let defaultGapPixels = 1
    private static let maxPixels = 100_000

    static func trackPixels(width: Double, scale: Double) -> Int {
        guard width.isFinite, scale.isFinite, width > 0, scale > 0 else { return 0 }
        return Int(min(Double(maxPixels), (width * scale + 1e-6).rounded(.down)))
    }

    static func make(memory: MemoryStats?, trackWidth: Double, scale: Double, gapPixels: Int = defaultGapPixels) -> MemoryBarLayout {
        make(app: memory?.app, wired: memory?.wired, compressed: memory?.compressed, cached: memory?.cached,
             used: memory?.used, total: memory?.total, trackWidth: trackWidth, scale: scale, gapPixels: gapPixels)
    }

    static func make(app: UInt64?, wired: UInt64?, compressed: UInt64?, cached: UInt64?, used: UInt64?, total: UInt64?,
                     trackWidth: Double, scale: Double, gapPixels: Int = defaultGapPixels) -> MemoryBarLayout {
        let pixels = trackPixels(width: trackWidth, scale: scale)
        guard pixels > 0, let total, total > 0 else { return MemoryBarLayout(trackPixels: pixels, segments: []) }
        let totalBytes = Double(total)

        // 1. Les catégories « utilisées », mises d'accord avec le chiffre « utilisé ».
        var appBytes = Double(app ?? 0), wiredBytes = Double(wired ?? 0), compressedBytes = Double(compressed ?? 0)
        var unattributed = 0.0
        let known = appBytes + wiredBytes + compressedBytes
        if let used {
            let target = min(Double(used), totalBytes)
            if known > 0, target > 0, abs(known - target) <= attributionTolerance * totalBytes {
                let factor = target / known
                appBytes *= factor; wiredBytes *= factor; compressedBytes *= factor
            } else if known < target {
                unattributed = target - known
            }
        }

        // 2. Jamais plus que le total.
        let drawnUsed = appBytes + wiredBytes + compressedBytes + unattributed
        if drawnUsed > totalBytes {
            let factor = totalBytes / drawnUsed
            appBytes *= factor; wiredBytes *= factor; compressedBytes *= factor; unattributed *= factor
        }

        // 3. Le cache n'est pas de la mémoire utilisée : il prend la place libre, pas plus.
        let free = max(0, totalBytes - min(drawnUsed, totalBytes))
        let cacheBytes = min(Double(cached ?? 0), free)

        let ordered: [(MemorySegmentKind, Double)] = [
            (.app, appBytes), (.wired, wiredBytes), (.compressed, compressedBytes), (.unattributed, unattributed), (.cached, cacheBytes),
        ].filter { $0.1 > 0 }

        // 4. Frontières en pixels entiers : arrondi du cumul (pas de dérive), jamais au-delà de la piste.
        var widths: [Int] = []
        var cumulative = 0.0, previousEnd = 0
        for (_, bytes) in ordered {
            cumulative += bytes
            let end = min(pixels, max(previousEnd, Int((cumulative / totalBytes * Double(pixels)).rounded())))
            widths.append(end - previousEnd)
            previousEnd = end
        }

        // 5. Un segment non vide fait au moins 1 pixel ; l'excédent est repris sur les plus larges.
        for index in widths.indices where widths[index] == 0 { widths[index] = 1 }
        var excess = widths.reduce(0, +) - pixels
        while excess > 0, let widest = widths.indices.max(by: { widths[$0] < widths[$1] }), widths[widest] > 1 {
            widths[widest] -= 1
            excess -= 1
        }
        var kept = ordered.count
        while widths.prefix(kept).reduce(0, +) > pixels, kept > 0 { kept -= 1 }      // plus de segments que de pixels

        // 6. Plages dessinées, avec le séparateur à droite de chaque segment suivi d'un autre.
        var segments: [Segment] = []
        var start = 0
        for index in 0..<kept {
            let slotEnd = start + widths[index]
            let isLast = index == kept - 1
            let gap = max(0, gapPixels)
            let drawnEnd = (!isLast && widths[index] - gap >= 1) ? slotEnd - gap : slotEnd
            segments.append(Segment(kind: ordered[index].0, bytes: ordered[index].1, startPixel: start, endPixel: drawnEnd))
            start = slotEnd
        }
        return MemoryBarLayout(trackPixels: pixels, segments: segments)
    }
}
