import SwiftUI

/// Géométrie pure de l'icône de batterie (SL21) : aucune vue, aucun état, tout se teste en nombres.
///
/// L'icône ressemble à celle de macOS : un contour à angles arrondis, un petit bout à droite, un remplissage qui part de la
/// gauche et qui suit le niveau en continu (pas cinq paliers comme les symboles SF), un éclair quand le Mac charge.
///
/// Repère : l'origine est en haut à gauche du corps ; le bout est à droite du corps, dans le cadre total.
struct BatteryGlyphGeometry: Equatable {
    // MARK: Tailles écrites (corps sans le bout, en points)

    /// Libellé de la barre de menus (22 pt de haut) : 20 x 9,5 pt.
    static let menuBarBody = CGSize(width: 20, height: 9.5)
    /// Carte « Battery » de l'aperçu et de la fenêtre : 28 x 13 pt.
    static let cardBody = CGSize(width: 28, height: 13)
    /// En-tête de l'onglet Batterie (anneau de 112 pt) : 32 x 15 pt.
    static let tabBody = CGSize(width: 32, height: 15)

    // MARK: Règles

    /// Épaisseur du contour : 1,2 pt, et 1,5 pt avec « Augmenter le contraste ».
    static func lineWidth(increasedContrast: Bool) -> CGFloat { increasedContrast ? 1.5 : 1.2 }
    /// Jeu entre le contour et le remplissage.
    static let gap: CGFloat = 0.8
    /// Un niveau au-dessus de 0 % montre toujours au moins 1 pt de remplissage (1 à 4 % restent visibles).
    static let minSliver: CGFloat = 1
    /// Pas d'arrondi de la largeur du remplissage : un demi-point, soit un pixel en @2x.
    static let step: CGFloat = 0.5
    /// **Taille du repère** (éclair ou prise) : sa hauteur, en fraction de la hauteur du corps. Le réglage à retoucher pour le grossir ou le réduire.
    /// 1 = aussi haut que le corps ; au-delà, il dépasse du contour en haut et en bas, de moitié de l'excédent de chaque côté.
    /// 1,2 : 11,4 pt sur le corps de 9,5 pt de la barre de menus, soit environ 1 pt de chaque côté (les dents de la prise et son cordon
    /// sortent du contour, comme sur macOS). À 1 le repère est aussi haut que le corps : lisible, mais les dents se confondent avec le contour.
    static let markScale: CGFloat = 1.2
    /// **Largeur du halo** : le jeu transparent, en points, creusé dans le contour et le remplissage tout autour du repère.
    static let haloWidth: CGFloat = 0.9
    /// Largeur du repère en fraction de sa hauteur.
    static let boltAspect: CGFloat = 0.55
    static let plugAspect: CGFloat = 0.72
    /// L'éclair : contour en 6 points dans le carré unité (x vers la droite, y vers le bas).
    static let boltPoints: [CGPoint] = [
        CGPoint(x: 0.72, y: 0), CGPoint(x: 0.06, y: 0.58), CGPoint(x: 0.42, y: 0.58),
        CGPoint(x: 0.28, y: 1), CGPoint(x: 0.94, y: 0.40), CGPoint(x: 0.58, y: 0.40),
    ]

    /// La prise (« branché, ne charge pas ») : deux dents, un corps, un cordon, en rectangles dans le carré unité (x vers la droite, y vers le bas).
    static let plugRects: [CGRect] = [
        CGRect(x: 0.18, y: 0, width: 0.20, height: 0.34),         // dent gauche
        CGRect(x: 0.62, y: 0, width: 0.20, height: 0.34),         // dent droite
        CGRect(x: 0.06, y: 0.30, width: 0.88, height: 0.40),      // corps
        CGRect(x: 0.41, y: 0.70, width: 0.18, height: 0.30),      // cordon
    ]

    var body: CGSize
    var lineWidth: CGFloat

    init(body: CGSize, increasedContrast: Bool = false) {
        self.body = body
        self.lineWidth = Self.lineWidth(increasedContrast: increasedContrast)
    }

    var bodyRect: CGRect { CGRect(origin: .zero, size: body) }
    var cornerRadius: CGFloat { body.height * 0.3 }

    /// Le bout : 17 % de la hauteur de large, 42 % de haut, collé au corps et centré.
    var nubRect: CGRect {
        let w = max(1.5, body.height * 0.17), h = body.height * 0.42
        return CGRect(x: body.width, y: (body.height - h) / 2, width: w, height: h)
    }

    var totalSize: CGSize { CGSize(width: body.width + nubRect.width, height: body.height) }

    /// La place du remplissage : le corps reculé de l'épaisseur du trait et du jeu.
    var innerRect: CGRect { bodyRect.insetBy(dx: lineWidth + Self.gap, dy: lineWidth + Self.gap) }

    /// Largeur du remplissage pour un pourcentage (en points).
    /// - 0 % (ou pas un nombre, ou moins) : 0. 100 % (ou plus) : exactement la largeur intérieure.
    /// - entre les deux : proportionnelle, arrondie au demi-point le plus proche, puis ramenée à au moins 1 pt
    ///   (un niveau de 1 à 4 % se voit) et à au plus la largeur intérieure moins un demi-point (seul 100 % est plein).
    func fillWidth(percent: Double) -> CGFloat {
        guard !percent.isNaN, percent > 0 else { return 0 }
        let full = innerRect.width
        guard percent < 100 else { return full }
        let raw = full * CGFloat(percent) / 100
        let rounded = (raw / Self.step).rounded() * Self.step
        return min(max(rounded, Self.minSliver), full - Self.step)
    }

    func fillRect(percent: Double) -> CGRect {
        CGRect(x: innerRect.minX, y: innerRect.minY, width: fillWidth(percent: percent), height: innerRect.height)
    }

    /// Hauteur du repère : celle du corps fois `markScale` (le repère n'est plus limité à la zone de remplissage).
    var markHeight: CGFloat { body.height * Self.markScale }

    /// De combien le repère dépasse du corps, en haut et en bas (0 si `markScale` ≤ 1). Le glyphe réserve cette marge pour dessiner sans
    /// rien couper, sans changer sa taille de mise en page.
    var verticalOverflow: CGFloat { max(0, (markHeight - body.height) / 2) }

    /// L'éclair : `markHeight` de haut, centré sur le corps.
    var boltRect: CGRect {
        let h = markHeight, w = h * Self.boltAspect
        return CGRect(x: (body.width - w) / 2, y: (body.height - h) / 2, width: w, height: h)
    }

    /// La prise : `markHeight` de haut, centrée sur le corps.
    var plugRect: CGRect {
        let h = markHeight, w = h * Self.plugAspect
        return CGRect(x: (body.width - w) / 2, y: (body.height - h) / 2, width: w, height: h)
    }

    func markRect(_ mark: BatteryGlyphMark) -> CGRect { mark == .bolt ? boltRect : plugRect }

    /// Plage de niveaux (en %) où le bord du remplissage est caché derrière le repère et son halo : on lit alors le niveau d'un côté seulement
    /// (le texte à côté dit le chiffre). Hors de cette plage, le bord se voit.
    func hiddenEdgeRange(_ mark: BatteryGlyphMark) -> ClosedRange<Double> {
        let r = markRect(mark)
        func percent(at x: CGFloat) -> Double { Double(min(100, max(0, (x - innerRect.minX) / innerRect.width * 100))) }
        return percent(at: r.minX - Self.haloWidth + 0.5)...percent(at: r.maxX + Self.haloWidth - 0.5)
    }
}

/// Le repère dessiné dans l'icône : l'éclair quand la batterie charge, la prise quand le Mac est branché sans charger.
enum BatteryGlyphMark: Equatable { case bolt, plug }

/// Les couleurs de la barre de progression de la batterie. (La règle des couleurs de l'icône elle-même, SL21 : le contour et le bout gardent la
/// couleur de base, le remplissage suit le niveau, est dans `LabelPalette.color(for:)` : une seule règle pour le libellé et les cartes.)
enum BatteryGlyphColors {
    /// Couleur de la barre de progression de la batterie (carte de l'aperçu, anneau de l'onglet) : celle du niveau, donc des seuils réglés,
    /// comme le glyphe et la valeur. Au niveau normal, vert comme avant (le glyphe garde alors la couleur de base).
    static func barTint(for level: PressureLevel) -> Color { level.color ?? .green }
    static func barTint(for b: BatteryStats, thresholds: LevelThresholds) -> Color { barTint(for: .battery(b, thresholds: thresholds)) }
}

/// L'icône de batterie de la carte de l'aperçu (28 x 13 pt) et de l'en-tête de l'onglet Batterie (32 x 15 pt) (SL24).
///
/// **Le même dessin que le libellé de la barre de menus** (SL23) : une image dynamique, `NSImage(size:flipped:drawingHandler:)`, dont le dessin
/// lit l'échelle dans le contexte où AppKit l'affiche (1x, 2x, 3x ; il est refait quand la fenêtre change d'écran) et pose chaque forme sur des
/// pixels entiers (`BatteryPixelGeometry`, `LabelShapes.drawBattery`). Plus de dessin SwiftUI aux coordonnées fractionnaires, qui donnait des bords
/// gris à demi-intensité sur un écran 1x.
///
/// **Clair et sombre.** Les couleurs (le jeton « texte de soutien » pour le contour, le bout et le remplissage normal ; orange, rouge, écarlate
/// pour les niveaux) sont résolues ICI, depuis l'environnement SwiftUI (thème, « Augmenter le contraste »), puis copiées dans le dessin : l'image est
/// refaite quand le thème change, sans dépendre de l'apparence courante au moment où AppKit appelle le dessin.
///
/// La taille de mise en page ne change pas : le corps plus le bout. Le repère (éclair, prise) déborde en haut et en bas dans la marge de l'image,
/// compensée par un remplissage négatif.
struct BatteryGlyphImage: View {
    let percent: Double
    let power: BatteryPowerState
    let level: PressureLevel
    /// Le corps sans le bout, en points : `BatteryGlyphGeometry.cardBody` ou `.tabBody`.
    let bodySize: CGSize
    /// `nil` : suit le réglage du système (les cartes).
    let increasedContrast: Bool?
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.self) private var environment

    init(percent: Double, power: BatteryPowerState, level: PressureLevel = .normal, body: CGSize, increasedContrast: Bool? = nil) {
        self.percent = percent
        self.power = power
        self.level = level
        self.bodySize = body
        self.increasedContrast = increasedContrast
    }

    var body: some View {
        let nub = BatteryPixelGeometry.nubPoints(forBody: bodySize)
        let size = BatteryPixelGeometry.imageSizePoints(bodyPoints: bodySize, nubPoints: nub)
        let margin = BatteryPixelGeometry.overflowPoints(bodyPoints: bodySize)
        let image = BatteryGlyphDrawing.image(percent: percent, power: power, level: level, bodyPoints: bodySize, nubPoints: nub,
                                              palette: BatteryGlyphDrawing.palette(in: environment), increasedContrast: increasedContrast ?? (contrast == .increased))
        Image(nsImage: image)
            .frame(width: size.width, height: size.height)
            .padding(.vertical, -margin)      // la marge où le repère déborde ne change pas la taille de mise en page
            .accessibilityHidden(true)      // le texte à côté dit le niveau (et la carte l'état de charge)
    }
}

/// Le dessin de l'icône dans une image dynamique, et la résolution des couleurs.
enum BatteryGlyphDrawing {
    /// Les couleurs de l'icône pour un environnement SwiftUI (thème clair ou sombre, contraste).
    static func palette(in environment: EnvironmentValues) -> LabelPalette {
        func cg(_ color: Color) -> CGColor { color.resolve(in: environment).cgColor }
        return LabelPalette(base: cg(SupportingTextShapeStyle.color(in: environment)), orange: cg(.orange), red: cg(.red), scarlet: cg(PressureLevel.scarlet),
                            white: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    }

    /// L'image dynamique : sa taille en points ne dépend pas de l'échelle, son dessin se refait à chaque échelle demandée. Le dessin ne touche
    /// qu'à des valeurs copiées ici.
    static func image(percent: Double, power: BatteryPowerState, level: PressureLevel, bodyPoints: CGSize, nubPoints: CGFloat,
                      palette: LabelPalette, increasedContrast: Bool) -> NSImage {
        let size = BatteryPixelGeometry.imageSizePoints(bodyPoints: bodyPoints, nubPoints: nubPoints)
        return NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(percent: percent, power: power, level: level, bodyPoints: bodyPoints, nubPoints: nubPoints, palette: palette,
                 increasedContrast: increasedContrast, scale: MenuBarRenderer.pixelScale(of: context), in: context)
            return true
        }
    }

    /// Dessine l'icône dans un contexte dont l'unité est le point, l'axe y descend et l'origine est le coin haut gauche de l'image.
    /// Le dessin passe en pixels (une unité = un pixel) : chaque coordonnée est un entier.
    static func draw(percent: Double, power: BatteryPowerState, level: PressureLevel, bodyPoints: CGSize, nubPoints: CGFloat,
                     palette: LabelPalette, increasedContrast: Bool, scale rawScale: Int, in context: CGContext) {
        let scale = max(1, rawScale)
        let geometry = BatteryPixelGeometry(bodyPoints: bodyPoints, nubPoints: nubPoints, scale: scale, increasedContrast: increasedContrast)
        let origin = BatteryPixelGeometry.bodyOriginPoints(bodyPoints: bodyPoints)
        context.saveGState()
        context.scaleBy(x: 1 / CGFloat(scale), y: 1 / CGFloat(scale))
        context.setShouldAntialias(true)
        LabelShapes.drawBattery(geometry, percent: percent, power: power, level: level, palette: palette,
                                origin: CGPoint(x: origin.x * CGFloat(scale), y: origin.y * CGFloat(scale)), in: context)
        context.restoreGState()
    }
}
