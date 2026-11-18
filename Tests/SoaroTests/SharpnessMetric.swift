import AppKit
import Foundation
import Testing
@testable import Soaro

/// SL23 : la mesure de netteté d'un bitmap de libellé (canal alpha), pour comparer avant et après et pour fixer des seuils sur des chiffres mesurés.
///
/// Deux mesures, volontairement simples :
/// - **Bords de formes** (`edgeSoftness`) : dans un rectangle qui ne contient que des bords alignés sur les axes (le haut du contour de la batterie,
///   le haut de la pastille…), la part des pixels encrés dont l'alpha est intermédiaire (ni ~0 ni ~1). Un bord posé entre deux pixels en donne
///   un ou deux par colonne ; un bord posé sur la grille n'en donne aucun.
/// - **Texte** (`textEdgeHardness`) : le profil de lignes d'une zone de texte (somme de l'alpha de chaque ligne). La première et la dernière ligne
///   d'encre (haut des chiffres, ligne de base) sont « dures » quand elles pèsent presque autant que leur voisine, « molles » quand elles ne pèsent
///   qu'une fraction : le texte est alors posé à cheval sur deux lignes de pixels.
struct EdgeSoftness: Equatable {
    var soft: Int
    var inked: Int
    /// Part des pixels encrés dont l'alpha est intermédiaire (0 : bords parfaitement nets).
    var share: Double { inked == 0 ? 0 : Double(soft) / Double(inked) }
}

enum SharpnessMetric {
    /// Seuils d'alpha : sous `inkFloor` le pixel est vide, au-dessus de `solidCeiling` il est plein ; entre les deux il est « intermédiaire ».
    static let inkFloor = 0.04
    static let solidCeiling = 0.96

    /// Rectangle en points (origine en haut à gauche) vers un rectangle de pixels qui le contient.
    static func pixels(of rect: CGRect, scale: CGFloat, in ink: GlyphInk) -> (xs: Range<Int>, ys: Range<Int>) {
        let x0 = max(0, Int((rect.minX * scale + 1e-6).rounded(.down))), x1 = min(ink.width, Int((rect.maxX * scale - 1e-6).rounded(.up)))
        let y0 = max(0, Int((rect.minY * scale + 1e-6).rounded(.down))), y1 = min(ink.height, Int((rect.maxY * scale - 1e-6).rounded(.up)))
        return (x0..<max(x0, x1), y0..<max(y0, y1))
    }

    static func edgeSoftness(_ ink: GlyphInk, xs: Range<Int>, ys: Range<Int>) -> EdgeSoftness {
        var soft = 0, inked = 0
        for y in ys { for x in xs {
            let a = ink.alpha(x, y)
            if a > inkFloor { inked += 1; if a < solidCeiling { soft += 1 } }
        } }
        return EdgeSoftness(soft: soft, inked: inked)
    }

    static func edgeSoftness(_ ink: GlyphInk, region: CGRect) -> EdgeSoftness {
        let p = pixels(of: region, scale: ink.scale, in: ink)
        return edgeSoftness(ink, xs: p.xs, ys: p.ys)
    }

    /// Somme de l'alpha de chaque ligne de la zone.
    static func rowProfile(_ ink: GlyphInk, xs: Range<Int>, ys: Range<Int>) -> [Double] {
        ys.map { y in xs.reduce(0.0) { $0 + ink.alpha($1, y) } }
    }

    struct TextEdges: Equatable {
        /// Poids de la première ligne d'encre rapporté à celui de la suivante (haut des chiffres).
        var top: Double
        /// Poids de la dernière ligne d'encre rapporté à celui de la précédente (ligne de base).
        var bottom: Double
        /// Nombre de lignes d'encre.
        var rows: Int
        /// Le plus mou des deux : 1 = bords durs, proche de 0 = texte posé à cheval sur deux lignes de pixels.
        var hardness: Double { min(top, bottom) }
    }

    /// Dureté du haut et du bas d'un texte. `nil` s'il n'y a pas d'encre.
    static func textEdgeHardness(_ ink: GlyphInk, xs: Range<Int>, ys: Range<Int>) -> TextEdges? {
        let profile = rowProfile(ink, xs: xs, ys: ys)
        guard let peak = profile.max(), peak > 0 else { return nil }
        let floor = peak * 0.10      // ignore le voile de lissage de la police (quelques % du pic) : seules les vraies lignes d'encre comptent
        guard let first = profile.firstIndex(where: { $0 > floor }), let last = profile.lastIndex(where: { $0 > floor }), last - first >= 2 else { return nil }
        let top = profile[first] / max(profile[first + 1], 1e-9)
        let bottom = profile[last] / max(profile[last - 1], 1e-9)
        return TextEdges(top: min(top, 1), bottom: min(bottom, 1), rows: last - first + 1)
    }

    static func textEdgeHardness(_ ink: GlyphInk, region: CGRect) -> TextEdges? {
        let p = pixels(of: region, scale: ink.scale, in: ink)
        return textEdgeHardness(ink, xs: p.xs, ys: p.ys)
    }

    /// Rectangle englobant, en points, des pixels qui répondent au critère (couleur de la pastille écarlate, par exemple).
    static func bounds(of ink: GlyphInk, where match: ((r: Double, g: Double, b: Double, a: Double)) -> Bool) -> CGRect? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<ink.height { for x in 0..<ink.width where match(ink.pixel(x, y)) {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= 0 else { return nil }
        let s = ink.scale
        return CGRect(x: CGFloat(minX) / s, y: CGFloat(minY) / s, width: CGFloat(maxX - minX + 1) / s, height: CGFloat(maxY - minY + 1) / s)
    }
}

extension GlyphInk {
    /// Les pixels d'une image AppKit à une échelle EXPLICITE (1, 2, 3), par un dessin dans une représentation bitmap de la bonne taille :
    /// une image dessinée à la volée (`NSImage(size:flipped:drawingHandler:)`) se dessine alors à cette échelle-là, pas à celle de l'écran
    /// où tourne le test.
    init(image: NSImage, scale: CGFloat) throws {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((image.size.width * scale).rounded()), pixelsHigh: Int((image.size.height * scale).rounded()),
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        try self.init(cg: try #require(rep.cgImage), scale: scale)
    }
}
