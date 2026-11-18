import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Soaro

/// Un bitmap RGBA transparent dont l'unité est le pixel et dont l'axe y descend : le repère dans lequel `LabelShapes` dessine.
enum ShapeCanvas {
    static func render(width: Int, height: Int, scale: Int, draw: (CGContext) -> Void) throws -> GlyphInk {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        draw(context)
        return try GlyphInk(cg: try #require(context.makeImage()), scale: CGFloat(scale))
    }

    static let black = LabelPalette.make(darkBar: false, base: CGColor(gray: 0, alpha: 1))

    /// L'icône seule, avec la marge où le repère déborde ; le corps commence à (0, débordement).
    static func battery(scale: Int, percent: Double, power: BatteryPowerState = .onBattery, level: PressureLevel = .normal,
                        contrast: Bool = false, palette: LabelPalette = black) throws -> (ink: GlyphInk, geometry: BatteryPixelGeometry) {
        let g = BatteryPixelGeometry(scale: scale, increasedContrast: contrast)
        let ink = try render(width: Int(g.total.width), height: g.body.height + 2 * g.verticalOverflow, scale: scale) {
            LabelShapes.drawBattery(g, percent: percent, power: power, level: level, palette: palette, origin: CGPoint(x: 0, y: g.verticalOverflow), in: $0)
        }
        return (ink, g)
    }
}

/// SL23, étape 2 : les formes du libellé lues en pixels, à trois échelles. Les bords alignés sur les axes tombent sur des pixels entiers :
/// aucun pixel d'alpha intermédiaire (le seuil vient de la mesure de départ : 0,30 à 0,68 de pixels intermédiaires sur le contour de la batterie
/// avec le dessin SwiftUI, 1,00 sur la ligne droite du glyphe).
@MainActor @Suite struct LabelShapesSharpnessTests {
    private func softness(_ ink: GlyphInk, _ rect: PixelRect) -> EdgeSoftness {
        SharpnessMetric.edgeSoftness(ink, xs: max(0, rect.x)..<min(ink.width, rect.maxX), ys: max(0, rect.y)..<min(ink.height, rect.maxY))
    }

    /// Les bords droits du contour : le haut, le bas, le côté gauche, le bord droit du remplissage. Les angles arrondis sont exclus.
    private func batteryEdges(_ g: BatteryPixelGeometry, percent: Double) -> [(name: String, rect: PixelRect)] {
        let o = g.verticalOverflow
        let r = Int(g.cornerRadius.rounded(.up)) + 1
        let line = g.lineWidth
        let flat = g.body.width - 2 * r
        let fill = g.fillRect(percent: percent)
        return [
            ("haut", PixelRect(x: r, y: o, width: flat, height: line)),
            ("bas", PixelRect(x: r, y: o + g.body.height - line, width: flat, height: line)),
            ("gauche", PixelRect(x: 0, y: o + r, width: line, height: g.body.height - 2 * r)),
            ("bord du remplissage", PixelRect(x: fill.maxX - 1, y: o + fill.y + 2 * 0 + 1, width: 2, height: max(1, fill.height - 2))),
            ("bout, flanc gauche", PixelRect(x: g.nub.x, y: o + g.nub.y, width: 1, height: g.nub.height)),
        ]
    }

    @Test(arguments: [1, 2, 3])
    func theBatteryEdgesAreOnWholePixels(scale: Int) throws {
        for percent in [20.0, 50, 67, 83] {
            for contrast in [false, true] {
                let (ink, g) = try ShapeCanvas.battery(scale: scale, percent: percent, contrast: contrast)
                for edge in batteryEdges(g, percent: percent) {
                    let result = softness(ink, edge.rect)
                    #expect(result.inked > 0, "\(edge.name) \(scale)x \(percent) % : de l'encre dans la zone mesurée")
                    #expect(result.soft == 0, "\(edge.name), \(scale)x, \(percent) %, contraste \(contrast) : \(result.soft) pixels intermédiaires sur \(result.inked)")
                }
            }
        }
    }

    @Test(arguments: [1, 2, 3])
    func theBatteryPlugEdgesAreOnWholePixels(scale: Int) throws {
        // La prise est faite de rectangles : tous ses bords sont droits, sur la grille (halo compris, aux angles arrondis près).
        let (ink, g) = try ShapeCanvas.battery(scale: scale, percent: 0, power: .pluggedNotCharging)
        let box = g.plugRect
        let o = g.verticalOverflow
        // Le haut des dents et la largeur du corps de la prise : des rangées et des colonnes entières d'encre pleine.
        let body = g.plugRects[2]
        let result = softness(ink, PixelRect(x: body.x + 1, y: body.y + o + 1, width: body.width - 2, height: max(1, body.height - 2)))
        #expect(result.soft == 0 && result.inked > 0, "le corps de la prise, \(scale)x : \(result)")
        let teeth = g.plugRects[0]
        let top = softness(ink, PixelRect(x: teeth.x, y: box.y + o, width: teeth.width, height: 1))
        #expect(top.soft == 0 && top.inked > 0, "le haut d'une dent, \(scale)x : \(top)")
    }

    @Test(arguments: [1, 2, 3])
    func theBrandGroundLineHasNoIntermediatePixel(scale: Int) throws {
        let g = BrandPixelGeometry(scale: scale)
        let ink = try ShapeCanvas.render(width: 17 * scale + 12 * scale, height: 22 * scale, scale: scale) {
            LabelShapes.drawBrand(g, severity: nil, color: CGColor(gray: 0, alpha: 1), in: $0)
        }
        let rows = g.groundRows
        let cap = g.strokeWidth
        // Entre les bouts ronds : la ligne droite, rangée par rangée.
        let result = softness(ink, PixelRect(x: cap + 1, y: rows.lowerBound - 1, width: 16 * scale - 2 * cap - 2, height: rows.count + 2))
        #expect(result.soft == 0, "\(scale)x : \(result.soft) pixels intermédiaires sur \(result.inked)")
        #expect(result.inked == (16 * scale - 2 * cap - 2) * rows.count, "exactement les \(rows.count) rangées du trait")
    }

    @Test(arguments: [1, 2, 3])
    func theCriticalPillEdgesAreOnWholePixels(scale: Int) throws {
        let rect = PixelRect(x: 3, y: 4, width: 34 * scale, height: 14 * scale + scale / 2)
        let radius = CGFloat(PixelGrid.px(3.5, scale: scale))
        let ink = try ShapeCanvas.render(width: rect.maxX + 4, height: rect.maxY + 4, scale: scale) {
            LabelShapes.drawPill(rect, radius: radius, color: ShapeCanvas.black.scarlet, in: $0)
        }
        let r = Int(radius.rounded(.up)) + 1
        for area in [PixelRect(x: rect.x + r, y: rect.y - 1, width: rect.width - 2 * r, height: 3), PixelRect(x: rect.x + r, y: rect.maxY - 2, width: rect.width - 2 * r, height: 3),
                     PixelRect(x: rect.x - 1, y: rect.y + r, width: 3, height: rect.height - 2 * r), PixelRect(x: rect.maxX - 2, y: rect.y + r, width: 3, height: rect.height - 2 * r)] {
            let result = softness(ink, area)
            #expect(result.soft == 0 && result.inked > 0, "\(scale)x : \(result)")
        }
    }

    @Test func theDrawnBodyIsTwentyByTenPointsInInkAtEveryScale() throws {
        for scale in 1...3 {
            let (ink, g) = try ShapeCanvas.battery(scale: scale, percent: 0)
            let o = g.verticalOverflow
            #expect(ink.alpha(0, o + g.body.height / 2) > 0.99 && ink.alpha(g.body.width - 1, o + g.body.height / 2) > 0.99, "le contour touche les deux bords du corps")
            #expect(ink.alpha(g.body.width / 2, o) > 0.99 && ink.alpha(g.body.width / 2, o + g.body.height - 1) > 0.99)
            #expect(ink.alpha(g.body.width + g.nub.width - 1, o + g.body.height / 2) > 0.3, "le bout")
            #expect(ink.alpha(g.body.width / 2, o + g.body.height / 2) < 0.01, "vide à 0 %")
        }
    }

    @Test func theMarkIsInkOnAnEmptyBatteryAndAHoleInAFullOne() throws {
        for scale in 1...3 {
            let g = BatteryPixelGeometry(scale: scale)
            let o = g.verticalOverflow
            let centreX = g.plugRect.x + g.plugRect.width / 2, centreY = o + g.body.height / 2
            let empty = try ShapeCanvas.battery(scale: scale, percent: 0, power: .pluggedNotCharging).ink
            #expect(empty.alpha(centreX, centreY) > 0.99, "encre pleine sur le vide, \(scale)x")
            let full = try ShapeCanvas.battery(scale: scale, percent: 100, power: .onBattery).ink
            #expect(full.alpha(centreX, centreY) > 0.99, "plein : encre")
            let fullWithBolt = try ShapeCanvas.battery(scale: scale, percent: 100, power: .charging).ink
            // Le halo est creusé dans le remplissage : juste à gauche du sommet gauche de l'éclair (tout le remplissage est plein à 100 %), l'alpha tombe (le sommet est en diagonale : en 1x le pixel n'est creusé qu'en partie).
            let left = try #require(g.boltPoints.min { $0.x < $1.x })
            let beside = fullWithBolt.alpha(Int(left.x.rounded(.down)) - 1, o + Int(left.y.rounded()))
            let plain = full.alpha(Int(left.x.rounded(.down)) - 1, o + Int(left.y.rounded()))
            #expect(plain > 0.99 && beside < 0.8, "halo creusé, \(scale)x : \(beside)")
        }
    }

    @Test func theTemplateImageStaysAlphaOnlyForABlackPalette() throws {
        let (ink, g) = try ShapeCanvas.battery(scale: 2, percent: 60, power: .charging)
        for y in 0..<ink.height { for x in 0..<ink.width {
            let p = ink.pixel(x, y)
            if p.a > 0 { #expect(p.r < 0.01 && p.g < 0.01 && p.b < 0.01, "noir partout (modèle) : \(p) à \(x),\(y)") }
        } }
        _ = g
    }

    @Test func aColouredLevelColoursOnlyTheFill() throws {
        let palette = LabelPalette.make(darkBar: false, base: CGColor(gray: 0, alpha: 1))
        let (ink, g) = try ShapeCanvas.battery(scale: 2, percent: 60, level: .high, palette: palette)
        let o = g.verticalOverflow
        let fill = ink.pixel(g.inner.x + 3, o + g.inner.y + g.inner.height / 2)
        #expect(fill.a > 0.99 && fill.r > 0.9 && fill.g < 0.35 && fill.b < 0.35, "rouge : \(fill)")
        let outline = ink.pixel(g.body.width / 2, o)
        #expect(outline.a > 0.99 && outline.r < 0.05, "contour de la couleur de base : \(outline)")
    }
}
