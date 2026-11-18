import CoreGraphics
import Foundation

/// La grille de pixels (SL23). Le libellé de la barre de menus est dessiné pour une échelle entière (1x, 2x, 3x) : toute forme a ses
/// coordonnées en pixels ENTIERS, de sorte qu'un bord tombe entre deux pixels et jamais au milieu d'un pixel (un bord au milieu d'un pixel
/// donne une ligne grise de demi-intensité, le flou qu'on voit sur un écran 1x).
enum PixelGrid {
    /// Des points en pixels entiers, arrondis à l'entier le plus proche (la moitié vers le haut : 7,5 pt en 1x donne 8 px).
    static func px(_ points: CGFloat, scale: Int) -> Int {
        Int((points * CGFloat(scale)).rounded(.toNearestOrAwayFromZero))
    }

    /// Le nombre pair le plus proche (pour qu'une forme se centre sur des pixels entiers dans un corps de hauteur paire).
    static func evenPx(_ points: CGFloat, scale: Int) -> Int {
        let exact = points * CGFloat(scale)
        return max(2, 2 * Int((exact / 2).rounded(.toNearestOrAwayFromZero)))
    }

    /// Le nombre de pixels le plus proche DE LA PARITÉ DEMANDÉE (0 : pair, 1 : impair), jamais moins que 2 (pair) ou 1 (impair) (SL24). Une forme centrée
    /// dans un corps de N pixels tombe sur des pixels entiers seulement si sa taille a la parité de N : les corps de la carte (13 pt) et de l'onglet
    /// (15 pt) font un nombre impair de pixels en 1x. Pour la parité 0, c'est `evenPx`.
    static func px(_ points: CGFloat, scale: Int, parity: Int) -> Int {
        let p = parity & 1
        let n = 2 * Int(((points * CGFloat(scale) - CGFloat(p)) / 2).rounded(.toNearestOrAwayFromZero)) + p
        return max(n, p == 0 ? 2 : 1)
    }

    /// Le même nombre, ramené sur la grille : des points qui valent un nombre entier de pixels.
    static func snap(_ points: CGFloat, scale: Int) -> CGFloat {
        CGFloat(px(points, scale: scale)) / CGFloat(scale)
    }

    /// Cette valeur (en pixels) est-elle entière ?
    static func isWhole(_ pixels: CGFloat, tolerance: CGFloat = 1e-6) -> Bool {
        abs(pixels - pixels.rounded()) < tolerance
    }
}

/// Un rectangle en pixels entiers.
struct PixelRect: Equatable {
    var x: Int, y: Int, width: Int, height: Int
    var maxX: Int { x + width }
    var maxY: Int { y + height }
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    func offsetBy(dx: Int, dy: Int) -> PixelRect { PixelRect(x: x + dx, y: y + dy, width: width, height: height) }
    func inset(_ d: Int) -> PixelRect { PixelRect(x: x + d, y: y + d, width: width - 2 * d, height: height - 2 * d) }
}

/// L'icône de batterie en pixels entiers pour une échelle (SL21, SL23, SL24). UNE géométrie pour le libellé de la barre de menus (corps de
/// 20 x 10 pt), la carte de l'aperçu (28 x 13 pt) et l'en-tête de l'onglet Batterie (32 x 15 pt) : tout est calculé à partir du corps en points
/// et de l'échelle, chaque coordonnée est un entier de pixels. Les règles (trait, jeu, repère, halo) sont celles de `BatteryGlyphGeometry` en points.
/// Repère : l'origine est le coin haut gauche du corps ; le repère (éclair, prise) peut dépasser en haut et en bas de `verticalOverflow`.
struct BatteryPixelGeometry: Equatable {
    /// Le corps de la barre de menus, en points, et son bout (1,6 pt : 2 px en 1x, 3 px en 2x).
    static let bodyPoints = CGSize(width: 20, height: 10)
    static let menuBarNubPoints: CGFloat = 1.6
    /// Épaisseur du contour en points : 1,2 (1 px en 1x, 2 px en 2x), et 1,5 avec « Augmenter le contraste » (2 px en 1x).
    static func linePoints(increasedContrast: Bool) -> CGFloat { increasedContrast ? 1.5 : 1.2 }

    /// Le bout de la carte et de l'onglet : 17 % de la hauteur du corps comme avant SL24, arrondi au point entier (2 pt pour la carte, 3 pt pour l'onglet)
    /// pour que l'image ait la même taille en points à toutes les échelles.
    static func nubPoints(forBody body: CGSize) -> CGFloat { max(2, (body.height * 0.17).rounded()) }

    /// Marge, en points entiers, au-dessus et au-dessous du corps dans l'image : de quoi laisser dépasser le repère à toutes les échelles.
    static func overflowPoints(bodyPoints body: CGSize) -> CGFloat { ((BatteryGlyphGeometry.markScale - 1) * body.height / 2).rounded(.up) }

    /// L'origine du corps dans l'image, en points.
    static func bodyOriginPoints(bodyPoints body: CGSize) -> CGPoint { CGPoint(x: 0, y: overflowPoints(bodyPoints: body)) }

    /// La taille en points de l'image qui porte l'icône : le corps, le bout (arrondi au point au-dessus) et la marge du repère en haut et en bas.
    static func imageSizePoints(bodyPoints body: CGSize, nubPoints nub: CGFloat) -> CGSize {
        CGSize(width: body.width + nub.rounded(.up), height: body.height + 2 * overflowPoints(bodyPoints: body))
    }

    let scale: Int
    let body: PixelRect
    let lineWidth: Int
    let gap: Int
    let cornerRadius: CGFloat
    let nub: PixelRect
    let markHeight: Int
    let haloWidth: Int

    /// La barre de menus : corps de 20 x 10 pt.
    init(scale: Int, increasedContrast: Bool = false) {
        self.init(bodyPoints: Self.bodyPoints, nubPoints: Self.menuBarNubPoints, scale: scale, increasedContrast: increasedContrast)
    }

    /// `bodyPoints` : le corps sans le bout, en points ENTIERS ; `nubPoints` : la largeur du bout.
    init(bodyPoints: CGSize, nubPoints: CGFloat, scale: Int, increasedContrast: Bool = false) {
        let s = max(1, scale)
        self.scale = s
        body = PixelRect(x: 0, y: 0, width: PixelGrid.px(bodyPoints.width, scale: s), height: PixelGrid.px(bodyPoints.height, scale: s))
        lineWidth = max(1, PixelGrid.px(Self.linePoints(increasedContrast: increasedContrast), scale: s))
        gap = max(1, PixelGrid.px(BatteryGlyphGeometry.gap, scale: s))
        cornerRadius = CGFloat(PixelGrid.px(bodyPoints.height * 0.3, scale: s))
        // Le bout : 42 % de la hauteur du corps, de la parité du corps (pour se centrer sur des pixels entiers : un corps de 13 pt fait 13 px en 1x).
        let heightParity = body.height % 2, widthParity = body.width % 2
        let nubHeight = PixelGrid.px(bodyPoints.height * 0.42, scale: s, parity: heightParity)
        let nubWidth = max(1, PixelGrid.px(nubPoints, scale: s))
        nub = PixelRect(x: body.width, y: (body.height - nubHeight) / 2, width: nubWidth, height: nubHeight)
        markHeight = PixelGrid.px(bodyPoints.height * BatteryGlyphGeometry.markScale, scale: s, parity: heightParity)
        haloWidth = max(1, PixelGrid.px(BatteryGlyphGeometry.haloWidth, scale: s))
        markWidthParity = widthParity
    }

    /// Parité de la largeur du corps : les repères la prennent pour rester centrés sur des pixels entiers.
    private let markWidthParity: Int

    var total: CGSize { CGSize(width: body.width + nub.width, height: body.height) }
    /// Le repère dépasse du corps de cette hauteur, en haut comme en bas.
    var verticalOverflow: Int { max(0, (markHeight - body.height) / 2) }
    var inner: PixelRect { body.inset(lineWidth + gap) }

    /// Largeur du remplissage en pixels entiers : 0 à 0 % (ou pas un nombre), la largeur intérieure à 100 % ; entre les deux, proportionnelle et
    /// arrondie au pixel, au moins 1 pt (une trace visible de 1 à 4 %) et au plus la largeur intérieure moins 1 px (seul 100 % est plein).
    func fillWidth(percent: Double) -> Int {
        guard !percent.isNaN, percent > 0 else { return 0 }
        let full = inner.width
        guard percent < 100 else { return full }
        let raw = Double(full) * percent / 100
        return min(max(Int(raw.rounded()), scale), full - 1)
    }

    func fillRect(percent: Double) -> PixelRect {
        PixelRect(x: inner.x, y: inner.y, width: fillWidth(percent: percent), height: inner.height)
    }

    /// L'éclair : sa boîte, 0,55 de sa hauteur de large (largeur de la parité du corps), centrée sur le corps.
    var boltRect: PixelRect {
        let w = PixelGrid.px(CGFloat(markHeight) / CGFloat(scale) * BatteryGlyphGeometry.boltAspect, scale: scale, parity: markWidthParity)
        return PixelRect(x: (body.width - w) / 2, y: (body.height - markHeight) / 2, width: w, height: markHeight)
    }

    /// La prise : 0,72 de sa hauteur de large (largeur de la parité du corps), centrée sur le corps.
    var plugRect: PixelRect {
        let w = PixelGrid.px(CGFloat(markHeight) / CGFloat(scale) * BatteryGlyphGeometry.plugAspect, scale: scale, parity: markWidthParity)
        return PixelRect(x: (body.width - w) / 2, y: (body.height - markHeight) / 2, width: w, height: markHeight)
    }

    func markRect(_ mark: BatteryGlyphMark) -> PixelRect { mark == .bolt ? boltRect : plugRect }

    /// Les sommets de l'éclair, en pixels (les arêtes sont en diagonale : le lissage y est normal).
    var boltPoints: [CGPoint] {
        let r = boltRect
        return BatteryGlyphGeometry.boltPoints.map { CGPoint(x: CGFloat(r.x) + $0.x * CGFloat(r.width), y: CGFloat(r.y) + $0.y * CGFloat(r.height)) }
    }

    /// Les rectangles de la prise : chaque bord arrondi au pixel, 1 px au moins, symétriques.
    var plugRects: [PixelRect] {
        let r = plugRect
        func edge(_ unit: CGFloat, _ length: Int) -> Int { Int((unit * CGFloat(length)).rounded(.toNearestOrAwayFromZero)) }
        return BatteryGlyphGeometry.plugRects.map { u in
            let x0 = edge(u.minX, r.width), x1 = max(edge(u.maxX, r.width), x0 + 1)
            let y0 = edge(u.minY, r.height), y1 = max(edge(u.maxY, r.height), y0 + 1)
            return PixelRect(x: r.x + x0, y: r.y + y0, width: x1 - x0, height: y1 - y0)
        }
    }
}

/// Le glyphe d'Soaro et le badge d'alerte, en pixels pour une échelle (SL23). Le trait de 1,6 pt devient un nombre entier de pixels,
/// et la ligne droite du bas (la mer calmée) tombe sur des rangées de pixels entières, avec les deux bouts DANS la boîte de 16 pt
/// (avant SL23 le bout gauche dépassait de 0,8 pt et était coupé par le bord de l'image).
struct BrandPixelGeometry: Equatable {
    static let boxPoints = CGSize(width: 16, height: 12)
    /// Le bas de la boîte, mesuré depuis le haut du libellé de 22 pt : la boîte de 12 pt est centrée, elle va de 5 à 17.
    static let bottomPoints: CGFloat = 17
    static let strokePoints: CGFloat = 1.6
    static let badgeGapPoints: CGFloat = 1
    static let circleBoxPoints: CGFloat = 5
    static let triangleBoxPoints: CGFloat = 11

    let scale: Int
    let strokeWidth: Int
    /// Rectangle (en pixels, réel) où s'étendent les courbes ; la ligne du bas est sur son bord bas.
    let pathRect: CGRect

    init(scale: Int) {
        let s = max(1, scale)
        self.scale = s
        // 1,6 pt : 1 px en 1x (2 px empâtaient les vagues en un bloc, vu à l'œil), 3 px en 2x, 5 px en 3x.
        strokeWidth = s == 1 ? 1 : max(1, PixelGrid.px(Self.strokePoints, scale: s))
        // Le trait de largeur impaire se centre sur le milieu d'un pixel, celui de largeur paire sur la frontière entre deux pixels.
        let bottom = CGFloat(PixelGrid.px(Self.bottomPoints, scale: s)) + (strokeWidth % 2 == 1 ? 0.5 : 0)
        let height = CGFloat(Int(Self.boxPoints.height) * s)
        let inset = CGFloat(strokeWidth) / 2
        pathRect = CGRect(x: inset, y: bottom - height, width: CGFloat(Int(Self.boxPoints.width) * s) - 2 * inset, height: height)
    }

    /// Les rangées occupées par la ligne droite du bas (la dernière frontière du trait tombe sur un pixel entier).
    var groundRows: Range<Int> {
        let top = Int((pathRect.maxY - CGFloat(strokeWidth) / 2).rounded())
        return top..<(top + strokeWidth)
    }

    /// Haut de la boîte du glyphe, en pixels entiers : le badge s'y aligne.
    var topPixels: Int { PixelGrid.px(Self.bottomPoints - Self.boxPoints.height, scale: scale) }
    var width: Int { Int(Self.boxPoints.width) * scale }

    var circleDiameter: Int { max(1, PixelGrid.px(4.5, scale: scale)) }
    var circleRect: PixelRect {
        PixelRect(x: width + PixelGrid.px(Self.badgeGapPoints, scale: scale), y: topPixels, width: circleDiameter, height: circleDiameter)
    }

    /// Le triangle d'alerte : 10,5 x 8 pt, son sommet au milieu de la boîte du badge.
    var triangleRect: PixelRect {
        PixelRect(x: width + PixelGrid.px(Self.badgeGapPoints, scale: scale), y: PixelGrid.px(5.5, scale: scale),
                  width: PixelGrid.px(10.5, scale: scale), height: PixelGrid.px(8, scale: scale))
    }

    /// Largeur de l'ensemble glyphe + badge, en points entiers.
    static func widthPoints(for severity: Severity?) -> Int {
        let box = Int(boxPoints.width)
        switch severity {
        case .critical: return box + Int(badgeGapPoints) + Int(triangleBoxPoints)
        case .warning: return box + Int(badgeGapPoints) + Int(circleBoxPoints)
        default: return box
        }
    }
}
