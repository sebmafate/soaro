import AppKit
import CoreText

/// La mise en page du libellé, en POINTS ENTIERS et indépendante de l'échelle (SL23) : chaque bloc occupe un nombre entier de points, donc
/// commence et finit sur un pixel entier en 1x, 2x et 3x, et l'image a la même taille en points à toutes les échelles.
/// Dans son bloc, chaque forme et chaque texte est ensuite calé sur les pixels de l'échelle (`MenuBarLabelDrawer`).
struct MenuBarLabelLayout: Equatable {
    /// Hauteur du libellé, en points (en pixels : 22 en 1x, 44 en 2x).
    static let height = 22
    /// Espace entre deux blocs.
    static func spacing(compact: Bool) -> Int { compact ? 9 : 6 }
    /// Largeur mini d'un bloc « libellé au-dessus de la valeur » : « 9% » et « 100% » ne décalent pas les voisins.
    static let stackedMinWidth = 31
    /// Largeur mini du bloc réseau, celle de « ↓ 999 KB/s » : le bloc ne bouge plus.
    static let pairMinWidth = 54
    /// Place de l'icône de batterie (corps de 20 pt plus le bout), en points entiers.
    static let batteryIconWidth = 22
    static let batterySpacing = LabelTextLayout.batterySpacing
    /// Largeur mini du pourcentage : 40 pt, ce qu'il faut à « 100 % » (avec l'espace insécable des langues qui en mettent une) en 12 pt demi-gras.
    static let batteryValueMinWidth = 40
    /// Largeur mini de tout l'élément batterie (icône + espace + pourcentage), en style compact.
    static let batteryMinWidth = batteryIconWidth + batterySpacing + batteryValueMinWidth

    struct Block: Equatable {
        var x: Int
        var width: Int
    }

    let compact: Bool
    let severity: Severity?
    let brandWidth: Int
    let blocks: [Block]
    let widthPoints: Int

    init(items: [MenuBarItem], compact: Bool, severity: Severity?) {
        self.compact = compact
        self.severity = severity
        brandWidth = BrandPixelGeometry.widthPoints(for: severity)
        var x = brandWidth
        var blocks: [Block] = []
        for item in items {
            x += Self.spacing(compact: compact)
            let width = Self.blockWidth(item, compact: compact)
            blocks.append(Block(x: x, width: width))
            x += width
        }
        self.blocks = blocks
        widthPoints = x
    }

    /// Largeur d'une valeur avec sa pastille éventuelle (3 pt de remplissage de chaque côté au niveau critique).
    static func valueWidth(_ text: String, style: LabelTextStyle, level: PressureLevel) -> Int {
        style.widestWidth(of: text) + (level == .critical ? 2 * Int(LabelTextLayout.pillPadding) : 0)
    }

    static func flagWidth(_ code: String) -> Int {
        guard let flag = MenuBarFlag.emoji(forCountryCode: code) else { return 0 }
        return Int((1...3).map { LabelFlag.width(flag, scale: $0) }.max()!.rounded(.up))
    }

    static func blockWidth(_ item: MenuBarItem, compact: Bool) -> Int {
        switch item {
        case .stacked(let label, let value, let level):
            if compact {
                return max(stackedMinWidth, LabelTextStyle.caption.widestWidth(of: label), valueWidth(value, style: .value, level: level))
            }
            return LabelTextStyle.line.widestWidth(of: label) + LabelTextLayout.labelValueSpacing + valueWidth(value, style: .lineDigits, level: level)
        case .pair(let top, let bottom):
            if compact {
                return max(pairMinWidth, LabelTextStyle.rate.widestWidth(of: top), LabelTextStyle.rate.widestWidth(of: bottom))
            }
            return LabelTextStyle.lineDigits.widestWidth(of: "\(bottom) \(top)")
        case .flag(let code):
            return flagWidth(code)
        case .battery(let percent, _, let level):
            let text = MenuBarItem.batteryValue(percent)
            if compact {
                return batteryIconWidth + batterySpacing + max(batteryValueMinWidth, valueWidth(text, style: .value, level: level))
            }
            return batteryIconWidth + batterySpacing + valueWidth(text, style: .lineDigits, level: level)
        }
    }
}

/// Le drapeau (un émoji en couleur, SL19), dessiné par Core Text comme le reste.
enum LabelFlag {
    static func font(scale: Int) -> CTFont {
        let px = max(1, PixelGrid.px(MenuBarFlag.fontSize, scale: scale))
        return CTFontCreateWithName("Apple Color Emoji" as CFString, CGFloat(px) / CGFloat(max(1, scale)), nil)
    }

    static func line(_ flag: String, scale: Int) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: flag, attributes: [.font: font(scale: scale)]))
    }

    static func width(_ flag: String, scale: Int) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(flag, scale: scale), nil, nil, nil))
    }

    /// Centre vertical du drapeau dans le libellé : 10,5 pt du haut (mesuré sur le dessin de SwiftUI qu'il remplace).
    static let centrePoints: CGFloat = 10.5
}

/// Dessine tout le libellé dans un `CGContext` : les formes (`LabelShapes`) et le texte (`LabelText`), calés sur les pixels de l'échelle.
///
/// Le contexte reçu est celui de `NSImage(size:flipped:drawingHandler:)` : l'unité est le point, l'axe y descend, l'origine est le coin
/// haut gauche. Le dessin passe en PIXELS (une unité = un pixel) pour que chaque coordonnée soit un entier.
enum MenuBarLabelDrawer {
    static func draw(items: [MenuBarItem], layout: MenuBarLabelLayout, palette: LabelPalette, increasedContrast: Bool, scale rawScale: Int, in context: CGContext) {
        let scale = max(1, rawScale)
        let s = CGFloat(scale)
        context.saveGState()
        context.scaleBy(x: 1 / s, y: 1 / s)
        context.setShouldAntialias(true)
        context.setAllowsFontSmoothing(true)
        context.setShouldSmoothFonts(true)
        context.setShouldSubpixelPositionFonts(false)      // chaque lettre sur un pixel entier
        context.setShouldSubpixelQuantizeFonts(false)

        LabelShapes.drawBrand(BrandPixelGeometry(scale: scale), severity: layout.severity, color: palette.base, in: context)
        for (item, block) in zip(items, layout.blocks) {
            drawItem(item, block: block, layout: layout, palette: palette, increasedContrast: increasedContrast, scale: scale, in: context)
        }
        context.restoreGState()
    }

    // MARK: Un bloc

    private static func drawItem(_ item: MenuBarItem, block: MenuBarLabelLayout.Block, layout: MenuBarLabelLayout, palette: LabelPalette,
                                 increasedContrast: Bool, scale: Int, in context: CGContext) {
        let compact = layout.compact
        let x0 = block.x * scale, boxWidth = block.width * scale
        let lineBaseline = LabelTextLayout.baseline(LabelTextLayout.lineBaseline, scale: scale)
        switch item {
        case .stacked(let label, let value, let level):
            if compact {
                let captionX = x0 + (boxWidth - LabelTextStyle.caption.widthPixels(of: label, scale: scale)) / 2
                LabelText.draw(label, style: .caption, scale: scale, x: captionX, baseline: LabelTextLayout.baseline(LabelTextLayout.captionBaseline, scale: scale), color: palette.base, in: context)
                let valueWidth = LabelTextStyle.value.widthPixels(of: value, scale: scale)
                let padding = level == .critical ? PixelGrid.px(LabelTextLayout.pillPadding, scale: scale) : 0
                let valueX = x0 + (boxWidth - valueWidth - 2 * padding) / 2
                drawValue(value, style: .value, level: level, left: valueX, baseline: LabelTextLayout.baseline(LabelTextLayout.valueBaseline, scale: scale),
                          pill: LabelTextLayout.pillBounds(compact: true, scale: scale), palette: palette, scale: scale, in: context)
            } else {
                LabelText.draw(label, style: .line, scale: scale, x: x0, baseline: lineBaseline, color: palette.base, in: context)
                let valueX = x0 + LabelTextStyle.line.widthPixels(of: label, scale: scale) + LabelTextLayout.labelValueSpacing * scale
                drawValue(value, style: .lineDigits, level: level, left: valueX, baseline: lineBaseline,
                          pill: LabelTextLayout.pillBounds(compact: false, scale: scale), palette: palette, scale: scale, in: context)
            }
        case .pair(let top, let bottom):
            if compact {
                for (text, point) in zip([top, bottom], LabelTextLayout.rateBaselines) {
                    let width = LabelTextStyle.rate.widthPixels(of: text, scale: scale)
                    LabelText.draw(text, style: .rate, scale: scale, x: x0 + boxWidth - width, baseline: LabelTextLayout.baseline(point, scale: scale), color: palette.base, in: context)
                }
            } else {
                LabelText.draw("\(bottom) \(top)", style: .lineDigits, scale: scale, x: x0, baseline: lineBaseline, color: palette.base, in: context)
            }
        case .flag(let code):
            guard let flag = MenuBarFlag.emoji(forCountryCode: code) else { return }
            drawFlag(flag, left: x0, boxWidth: boxWidth, scale: scale, in: context)
        case .battery(let percent, let power, let level):
            let geometry = BatteryPixelGeometry(scale: scale, increasedContrast: increasedContrast)
            let top = (MenuBarLabelLayout.height * scale - geometry.body.height) / 2
            LabelShapes.drawBattery(geometry, percent: Double(percent), power: power, level: level, palette: palette, origin: CGPoint(x: x0, y: top), in: context)
            let valueX = x0 + MenuBarLabelLayout.batteryIconWidth * scale + MenuBarLabelLayout.batterySpacing * scale
            let text = MenuBarItem.batteryValue(percent)
            if compact {
                drawValue(text, style: .value, level: level, left: valueX, baseline: LabelTextLayout.baseline(LabelTextLayout.batteryValueBaseline, scale: scale),
                          pill: (PixelGrid.px(4, scale: scale), PixelGrid.px(18, scale: scale)), palette: palette, scale: scale, in: context)
            } else {
                drawValue(text, style: .lineDigits, level: level, left: valueX, baseline: lineBaseline,
                          pill: LabelTextLayout.pillBounds(compact: false, scale: scale), palette: palette, scale: scale, in: context)
            }
        }
    }

    /// Une valeur : orange ou rouge colorent le texte ; le niveau critique passe en pastille écarlate à texte blanc (la couleur seule ne
    /// suffit pas aux daltoniens). `left` est le bord gauche du texte, ou de la pastille au niveau critique.
    private static func drawValue(_ text: String, style: LabelTextStyle, level: PressureLevel, left: Int, baseline: Int, pill: (top: Int, bottom: Int),
                                  palette: LabelPalette, scale: Int, in context: CGContext) {
        if level == .critical {
            let padding = PixelGrid.px(LabelTextLayout.pillPadding, scale: scale)
            let width = style.widthPixels(of: text, scale: scale) + 2 * padding
            let rect = PixelRect(x: left, y: pill.top, width: width, height: pill.bottom - pill.top)
            LabelShapes.drawPill(rect, radius: CGFloat(PixelGrid.px(LabelTextLayout.pillRadius, scale: scale)), color: palette.scarlet, in: context)
            LabelText.draw(text, style: style, scale: scale, x: left + padding, baseline: baseline, color: palette.white, in: context)
        } else {
            LabelText.draw(text, style: style, scale: scale, x: left, baseline: baseline, color: palette.color(for: level) ?? palette.base, in: context)
        }
    }

    /// Le drapeau : l'image de l'émoji est centrée à 10,5 pt du haut, à pixels entiers.
    private static func drawFlag(_ flag: String, left: Int, boxWidth: Int, scale: Int, in context: CGContext) {
        let s = CGFloat(scale)
        let line = LabelFlag.line(flag, scale: scale)
        let widthPx = Int((CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) * s).rounded())
        context.textMatrix = .identity       // la matrice du texte n'est pas dans l'état graphique : le texte dessiné avant l'a retournée
        let bounds = CTLineGetImageBounds(line, context)          // en points, au-dessus de la ligne de base (axe y vers le haut)
        let centre = CGFloat(PixelGrid.px(LabelFlag.centrePoints, scale: scale))
        let baseline = Int((centre + (bounds.maxY + bounds.minY) / 2 * s).rounded())
        context.saveGState()
        context.scaleBy(x: s, y: s)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: CGFloat(left + (boxWidth - widthPx) / 2) / s, y: CGFloat(baseline) / s)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
