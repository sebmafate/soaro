import AppKit
import CoreText

/// Le texte du libellé (SL23) : dessiné avec Core Text dans le `CGContext`, pas avec le texte de SwiftUI. Core Text laisse choisir la
/// ligne de base (un pixel entier : les bas des lettres tombent sur une rangée de pixels, pas à cheval sur deux), l'origine horizontale
/// (un pixel entier) et le corps (un nombre entier de pixels), et mesure la largeur réelle.
struct LabelTextStyle: Equatable {
    var points: CGFloat
    var weight: NSFont.Weight
    /// Chiffres de même chasse : « 11% » et « 88% » ont la même largeur, rien ne bouge d'une mesure à l'autre.
    var monospacedDigits: Bool

    /// « CPU », « RAM »… au-dessus de la valeur (compact) : 7,5 pt demi-gras.
    static let caption = LabelTextStyle(points: 7.5, weight: .medium, monospacedDigits: false)
    /// La valeur sous le libellé, et le pourcentage de la batterie (compact) : 12 pt à chiffres de même chasse, demi-gras.
    static let value = LabelTextStyle(points: 12, weight: .semibold, monospacedDigits: true)
    /// Les débits réseau sur deux lignes (compact) : 9 pt demi-épais.
    static let rate = LabelTextStyle(points: 9, weight: .medium, monospacedDigits: true)
    /// Le style sur une ligne : libellé, puis valeur et débits à chiffres de même chasse, 13 pt.
    static let line = LabelTextStyle(points: 13, weight: .regular, monospacedDigits: false)
    static let lineDigits = LabelTextStyle(points: 13, weight: .regular, monospacedDigits: true)

    /// Corps en pixels entiers : les points fois l'échelle, arrondis (7,5 pt donne 8 px en 1x, 15 px en 2x).
    func pixelSize(scale: Int) -> Int { max(1, PixelGrid.px(points, scale: scale)) }

    /// Le corps en points qui vaut exactement `pixelSize` pixels : la police choisit son dessin optique (texte ou titre) selon ce corps.
    func fontSize(scale: Int) -> CGFloat { CGFloat(pixelSize(scale: scale)) / CGFloat(max(1, scale)) }

    func font(scale: Int) -> CTFont {
        let size = fontSize(scale: scale)
        let font = monospacedDigits ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        return font as CTFont
    }

    func line(_ text: String, scale: Int) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(scale: scale),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    /// Largeur réelle du texte à cette échelle, en points.
    func width(of text: String, scale: Int) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(text, scale: scale), nil, nil, nil))
    }

    /// Largeur qui convient à toutes les échelles courantes (1x, 2x, 3x), en points entiers : la place d'un bloc ne dépend pas de l'écran.
    func widestWidth(of text: String) -> Int {
        Int((1...3).map { width(of: text, scale: $0) }.max()!.rounded(.up))
    }

    /// Largeur en pixels à cette échelle, arrondie au pixel.
    func widthPixels(of text: String, scale: Int) -> Int {
        Int((width(of: text, scale: scale) * CGFloat(scale)).rounded())
    }
}

/// Où se pose le texte : des rangées de pixels entières. Valeurs en points, mesurées sur le dessin de SwiftUI qu'elles remplacent (à ± 0,5 pt),
/// puis arrondies au pixel pour chaque échelle.
enum LabelTextLayout {
    /// Ligne de base du libellé « CPU » au-dessus de la valeur (compact).
    static let captionBaseline: CGFloat = 6.5
    /// Ligne de base de la valeur, sous le libellé (compact), et bas de la pastille critique.
    static let valueBaseline: CGFloat = 19.5
    /// Lignes de base des deux débits réseau (compact).
    static let rateBaselines: [CGFloat] = [8.5, 19.5]
    /// Ligne de base du pourcentage à côté de l'icône de batterie (compact, 12 pt).
    static let batteryValueBaseline: CGFloat = 15.5
    /// Ligne de base du texte sur une ligne (13 pt) : les capitales sont centrées dans les 22 pt.
    static let lineBaseline: CGFloat = 15.6
    /// Écart horizontal entre le libellé et la valeur, et entre l'icône de batterie et son pourcentage.
    static let labelValueSpacing = 3
    static let batterySpacing = 3
    /// Remplissage horizontal de la pastille (de chaque côté du texte), et rayon de ses angles.
    static let pillPadding: CGFloat = 3
    static let pillRadius: CGFloat = 3.5

    static func baseline(_ points: CGFloat, scale: Int) -> Int { PixelGrid.px(points, scale: scale) }

    /// La pastille de la valeur compacte : de 7,5 pt du haut jusqu'au bas du libellé ; sur une ligne, de 3 à 19 pt.
    static func pillBounds(compact: Bool, scale: Int) -> (top: Int, bottom: Int) {
        compact ? (PixelGrid.px(7.5, scale: scale), 22 * scale) : (PixelGrid.px(3, scale: scale), PixelGrid.px(19, scale: scale))
    }
}

enum LabelText {
    /// Dessine `text` : `x` est le bord gauche et `baseline` la ligne de base, en pixels ENTIERS, dans le repère en pixels (y vers le bas)
    /// de `MenuBarLabelDrawer`. La couleur est celle du contexte.
    static func draw(_ text: String, style: LabelTextStyle, scale: Int, x: Int, baseline: Int, color: CGColor, in context: CGContext) {
        let s = CGFloat(max(1, scale))
        context.saveGState()
        context.scaleBy(x: s, y: s)                       // retour aux points : le corps de la police est donné en points
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)      // l'axe y descend : sans cela le texte serait à l'envers
        context.setFillColor(color)
        context.textPosition = CGPoint(x: CGFloat(x) / s, y: CGFloat(baseline) / s)
        CTLineDraw(style.line(text, scale: scale), context)
        context.restoreGState()
    }
}
