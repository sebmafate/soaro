import AppKit
import CoreGraphics

/// Les couleurs du libellé, résolues une fois pour la barre claire ou sombre (le dessin se fait dans un `CGContext`, hors de SwiftUI).
struct LabelPalette {
    var base: CGColor
    var orange: CGColor
    var red: CGColor
    var scarlet: CGColor
    var white: CGColor

    /// `base` : noir sur barre claire et pour une image modèle (seul l'alpha compte), blanc sur barre sombre quand l'image porte ses couleurs.
    static func make(darkBar: Bool, base: CGColor) -> LabelPalette {
        func resolved(_ color: NSColor) -> CGColor {
            var cg = color.cgColor
            NSAppearance(named: darkBar ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
                cg = color.usingColorSpace(.sRGB)?.cgColor ?? color.cgColor
            }
            return cg
        }
        return LabelPalette(base: base, orange: resolved(.systemOrange), red: resolved(.systemRed),
                            scarlet: CGColor(srgbRed: 1.0, green: 0.14, blue: 0.0, alpha: 1), white: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    }

    /// Couleur d'une valeur : celle du niveau ; `nil` pour le niveau normal (la couleur de base).
    func color(for level: PressureLevel) -> CGColor? {
        switch level {
        case .normal: nil
        case .medium: orange
        case .high: red
        case .critical: scarlet
        }
    }
}

/// Les formes du libellé, dessinées dans un `CGContext` dont l'unité est le PIXEL et dont l'axe y descend (voir `MenuBarLabelDrawer`).
/// Toutes les coordonnées viennent de `BatteryPixelGeometry` et `BrandPixelGeometry` : des entiers, donc des bords nets.
enum LabelShapes {
    /// Rectangle dont les angles gauches et droits ont des rayons différents (rayons ramenés à ce que la place permet).
    static func roundedPath(_ rect: CGRect, left: CGFloat, right: CGFloat) -> CGPath {
        let limit = min(rect.width, rect.height) / 2
        let l = min(left, limit), r = min(right, limit)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + l, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        if r > 0 { path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r) } else { path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)) }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        if r > 0 { path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r) } else { path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)) }
        path.addLine(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        if l > 0 { path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - l), radius: l) } else { path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)) }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + l))
        if l > 0 { path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + l, y: rect.minY), radius: l) } else { path.addLine(to: CGPoint(x: rect.minX, y: rect.minY)) }
        path.closeSubpath()
        return path
    }

    // MARK: Glyphe d'Soaro

    /// Les mêmes courbes que `assets/icon.svg` (x : 200…824, y : 214…694), ramenées au rectangle de pixels du glyphe.
    static func brandPath(_ g: BrandPixelGeometry) -> CGPath {
        let rect = g.pathRect
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (x - 200) / 624 * rect.width, y: rect.minY + (y - 214) / 480 * rect.height)
        }
        let path = CGMutablePath()
        for (base, crest, trough) in [(CGFloat(330), CGFloat(214), CGFloat(446)), (512, 454, 570)] {
            path.move(to: p(200, base))
            path.addCurve(to: p(412, base), control1: p(270, crest), control2: p(342, crest))
            path.addCurve(to: p(624, base), control1: p(482, trough), control2: p(554, trough))
            path.addCurve(to: p(824, base), control1: p(694, crest), control2: p(754, crest))
        }
        path.move(to: p(200, 694))
        path.addLine(to: p(824, 694))
        return path
    }

    static func drawBrand(_ g: BrandPixelGeometry, severity: Severity?, color: CGColor, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(CGFloat(g.strokeWidth))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(brandPath(g))
        context.strokePath()
        context.restoreGState()
        switch severity {
        case .warning:
            context.saveGState()
            context.setFillColor(color)
            context.fillEllipse(in: g.circleRect.cgRect)
            context.restoreGState()
        case .critical:
            drawAlertTriangle(g.triangleRect, color: color, in: context)
        default:
            break
        }
    }

    /// Le triangle d'alerte plein, angles arrondis, avec un point d'exclamation creusé (transparent), comme le symbole qu'il remplace.
    static func drawAlertTriangle(_ rect: PixelRect, color: CGColor, in context: CGContext) {
        let r = max(1, CGFloat(rect.height) / 8)          // rayon des angles : 1 pt
        let x = CGFloat(rect.x), y = CGFloat(rect.y), w = CGFloat(rect.width), h = CGFloat(rect.height)
        let triangle = CGMutablePath()
        triangle.move(to: CGPoint(x: x + w / 2, y: y + r))
        triangle.addLine(to: CGPoint(x: x + w - r, y: y + h - r))
        triangle.addLine(to: CGPoint(x: x + r, y: y + h - r))
        triangle.closeSubpath()
        context.saveGState()
        context.setFillColor(color)
        context.setStrokeColor(color)
        context.setLineWidth(2 * r)
        context.setLineJoin(.round)
        context.addPath(triangle)
        context.drawPath(using: .fillStroke)
        // Le point d'exclamation : une barre et un point, de largeur de même parité que le triangle pour rester centrés sur des pixels entiers.
        var bar = max(1, Int((w / 9).rounded()))
        if (bar % 2) != (rect.width % 2) { bar += 1 }
        let barX = CGFloat(rect.x) + (w - CGFloat(bar)) / 2
        context.setBlendMode(.destinationOut)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: barX, y: y + (h * 0.30).rounded(), width: CGFloat(bar), height: (h * 0.32).rounded()))
        let dotY = min(y + (h * 0.72).rounded(), y + h - r - CGFloat(bar))      // le point ne touche jamais la base du triangle
        context.fill(CGRect(x: barX, y: dotY, width: CGFloat(bar), height: CGFloat(bar)))
        context.restoreGState()
    }

    // MARK: Icône de batterie

    /// Dessine l'icône : `origin` est le coin haut gauche du corps, en pixels entiers.
    static func drawBattery(_ g: BatteryPixelGeometry, percent: Double, power: BatteryPowerState, level: PressureLevel, palette: LabelPalette,
                            origin: CGPoint, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        let outline = palette.base
        let fill = palette.color(for: level) ?? palette.base
        // 1. le remplissage : angles intérieurs arrondis à gauche, côté droit droit tant que la batterie n'est pas pleine.
        let width = g.fillWidth(percent: percent)
        if width > 0 {
            let innerRadius = max(1, g.cornerRadius - CGFloat(g.lineWidth) - CGFloat(g.gap) / 2)
            let isFull = width >= g.inner.width
            context.setFillColor(fill)
            context.addPath(roundedPath(g.fillRect(percent: percent).cgRect, left: innerRadius, right: isFull ? innerRadius : 0))
            context.fillPath()
        }
        // 2. le contour (anneau creusé par la règle pair-impair : des bords sur des pixels entiers) et le bout.
        let ring = CGMutablePath()
        ring.addPath(roundedPath(g.body.cgRect, left: g.cornerRadius, right: g.cornerRadius))
        ring.addPath(roundedPath(g.body.inset(g.lineWidth).cgRect, left: g.cornerRadius - CGFloat(g.lineWidth), right: g.cornerRadius - CGFloat(g.lineWidth)))
        context.setFillColor(outline)
        context.addPath(ring)
        context.fillPath(using: .evenOdd)
        context.addPath(roundedPath(g.nub.cgRect, left: 0, right: CGFloat(g.nub.width) * 0.8))
        context.fillPath()
        // 3. le repère : son halo est un jeu transparent creusé dans tout ce qui est déjà dessiné (que de l'alpha, aucune couleur : l'image
        //    modèle reste monochrome), puis le repère en encre pleine, par-dessus le jeu.
        if let mark = power.mark {
            let path = markPath(g, mark)
            let halo = path.copy(strokingWithWidth: 2 * CGFloat(g.haloWidth), lineCap: .butt, lineJoin: .round, miterLimit: 10)
            context.saveGState()
            context.setBlendMode(.destinationOut)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.addPath(halo)
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
            context.setFillColor(outline)
            context.addPath(path)
            context.fillPath()
        }
        context.restoreGState()
    }

    static func markPath(_ g: BatteryPixelGeometry, _ mark: BatteryGlyphMark) -> CGPath {
        let path = CGMutablePath()
        switch mark {
        case .bolt:
            let points = g.boltPoints
            path.move(to: points[0])
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.closeSubpath()
        case .plug:
            g.plugRects.forEach { path.addRect($0.cgRect) }
        }
        return path
    }

    // MARK: Pastille du niveau critique

    static func drawPill(_ rect: PixelRect, radius: CGFloat, color: CGColor, in context: CGContext) {
        context.saveGState()
        context.setFillColor(color)
        context.addPath(roundedPath(rect.cgRect, left: radius, right: radius))
        context.fillPath()
        context.restoreGState()
    }
}
