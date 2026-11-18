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

    func plugPath() -> Path {
        let r = plugRect
        var path = Path()
        for u in Self.plugRects {
            path.addRect(CGRect(x: r.minX + u.minX * r.width, y: r.minY + u.minY * r.height, width: u.width * r.width, height: u.height * r.height))
        }
        return path
    }

    func markPath(_ mark: BatteryGlyphMark) -> Path { mark == .bolt ? boltPath() : plugPath() }
    func markRect(_ mark: BatteryGlyphMark) -> CGRect { mark == .bolt ? boltRect : plugRect }

    /// Le halo : le repère élargi de `haloWidth` de chaque côté (un trait de `2 x haloWidth`, angles arrondis, sur le contour du repère).
    func haloPath(_ mark: BatteryGlyphMark) -> Path {
        markPath(mark).strokedPath(StrokeStyle(lineWidth: 2 * Self.haloWidth, lineJoin: .round))
    }

    /// Plage de niveaux (en %) où le bord du remplissage est caché derrière le repère et son halo : on lit alors le niveau d'un côté seulement
    /// (le texte à côté dit le chiffre). Hors de cette plage, le bord se voit.
    func hiddenEdgeRange(_ mark: BatteryGlyphMark) -> ClosedRange<Double> {
        let r = markRect(mark)
        func percent(at x: CGFloat) -> Double { Double(min(100, max(0, (x - innerRect.minX) / innerRect.width * 100))) }
        return percent(at: r.minX - Self.haloWidth + 0.5)...percent(at: r.maxX + Self.haloWidth - 0.5)
    }

    func boltPath() -> Path {
        let r = boltRect
        var path = Path()
        let points = Self.boltPoints.map { CGPoint(x: r.minX + $0.x * r.width, y: r.minY + $0.y * r.height) }
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    /// Rectangle à angles inégaux, rayons ramenés à ce que la place permet (un remplissage de 1 pt n'a pas de grands angles).
    func roundedRect(_ rect: CGRect, left: CGFloat, right: CGFloat) -> Path {
        let limit = min(rect.width, rect.height) / 2
        let l = min(left, limit), r = min(right, limit)
        return UnevenRoundedRectangle(topLeadingRadius: l, bottomLeadingRadius: l, bottomTrailingRadius: r, topTrailingRadius: r).path(in: rect)
    }
}

/// Le repère dessiné dans l'icône : l'éclair quand la batterie charge, la prise quand le Mac est branché sans charger.
enum BatteryGlyphMark: Equatable { case bolt, plug }

/// La règle des couleurs : le contour et le bout gardent la couleur de base ; le remplissage suit le niveau
/// (normal : la couleur de base ; orange, rouge ; écarlate en critique), comme la valeur à côté de l'icône.
enum BatteryGlyphColors {
    static func fill(level: PressureLevel, base: Color) -> Color { level.color ?? base }
    static func outline(level: PressureLevel, base: Color) -> Color { base }

    /// Couleur de la barre de progression de la batterie (carte de l'aperçu, anneau de l'onglet) : celle du niveau, donc des seuils réglés,
    /// comme le glyphe et la valeur. Au niveau normal, vert comme avant (le glyphe garde alors la couleur de base).
    static func barTint(for level: PressureLevel) -> Color { level.color ?? .green }
    static func barTint(for b: BatteryStats, thresholds: LevelThresholds) -> Color { barTint(for: .battery(b, thresholds: thresholds)) }
}

/// L'icône de batterie « comme celle de macOS », dessinée (pas un symbole SF, qui n'a que quelques niveaux).
///
/// **Image modèle (barre de menus).** Le libellé de la barre est une image modèle tant que rien n'est coloré : seul son canal
/// alpha compte, macOS la teinte. Ici tout se lit donc à l'alpha : le contour, le bout et le remplissage sont de l'encre pleine, et
/// le repère (éclair ou prise) est *creusé dans le remplissage* (mode de fusion `destinationOut` : un trou transparent en forme d'éclair) et, là où il
/// n'y a pas de remplissage, dessiné en encre pleine : il se voit sur une batterie pleine (trou clair dans l'encre) comme sur une
/// batterie vide (encre sur le vide), et à cheval sur le bord du remplissage il s'inverse, comme sur macOS.
/// Une batterie normale ne rend donc pas l'image colorée ; seul un niveau orange, rouge ou écarlate la rend non modèle,
/// et le dessin reste juste sur une barre claire ou sombre (`base` blanc ou noir).
struct BatteryGlyph: View {
    let percent: Double
    let power: BatteryPowerState
    let level: PressureLevel
    /// Couleur du contour, du bout et (niveau normal) du remplissage. `nil` : le jeton « texte de soutien » du thème (les cartes) ;
    /// le libellé de la barre de menus donne noir ou blanc.
    let base: Color?
    let bodySize: CGSize
    /// `nil` : suit le réglage du système (les cartes). Le libellé de la barre le donne explicitement (`ImageRenderer` ne voit pas l'environnement).
    let increasedContrast: Bool?
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.self) private var environment

    init(percent: Double, power: BatteryPowerState, level: PressureLevel = .normal, base: Color? = nil,
         body: CGSize = BatteryGlyphGeometry.menuBarBody, increasedContrast: Bool? = nil) {
        self.percent = percent
        self.power = power
        self.level = level
        self.base = base
        self.bodySize = body
        self.increasedContrast = increasedContrast
    }

    private var geometry: BatteryGlyphGeometry {
        BatteryGlyphGeometry(body: bodySize, increasedContrast: increasedContrast ?? (contrast == .increased))
    }

    var body: some View {
        let g = geometry
        let ink = base ?? SupportingTextShapeStyle.color(in: environment)
        let outline = BatteryGlyphColors.outline(level: level, base: ink)
        let fill = BatteryGlyphColors.fill(level: level, base: ink)
        Canvas { context, _ in
            context.translateBy(x: 0, y: g.verticalOverflow)      // le dessin commence sous la marge réservée au repère
            // 1. le remplissage (angles intérieurs arrondis ; côté droit droit tant que la batterie n'est pas pleine)
            let innerRadius = max(0.5, g.cornerRadius - g.lineWidth - BatteryGlyphGeometry.gap / 2)
            let width = g.fillWidth(percent: percent)
            if width > 0 {
                let isFull = width >= g.innerRect.width
                context.fill(g.roundedRect(g.fillRect(percent: percent), left: innerRadius, right: isFull ? innerRadius : 0.5), with: .color(fill))
            }
            // 2. le contour et le bout
            let strokeRect = g.bodyRect.insetBy(dx: g.lineWidth / 2, dy: g.lineWidth / 2)
            context.stroke(RoundedRectangle(cornerRadius: g.cornerRadius - g.lineWidth / 2).path(in: strokeRect), with: .color(outline), lineWidth: g.lineWidth)
            context.fill(g.roundedRect(g.nubRect, left: 0, right: g.nubRect.width * 0.8), with: .color(outline))
            // 3. le repère (éclair en charge, prise branché sans charge) : d'abord son halo, un jeu transparent creusé dans tout ce qui est déjà
            //    dessiné, contour et remplissage (mode de fusion `destinationOut` : de l'alpha en moins, aucune couleur) ; puis le repère, en encre
            //    pleine dans la couleur du contour, par-dessus le jeu. Que du canal alpha : l'image modèle reste monochrome.
            if let mark = power.mark {
                var cut = context
                cut.blendMode = .destinationOut
                cut.fill(g.haloPath(mark), with: .color(.black))
                cut.fill(g.markPath(mark), with: .color(.black))
                context.fill(g.markPath(mark), with: .color(outline))
            }
        }
        .frame(width: g.totalSize.width, height: g.totalSize.height + 2 * g.verticalOverflow)
        .padding(.vertical, -g.verticalOverflow)       // la marge où le repère déborde ne change pas la taille de mise en page
        .accessibilityHidden(true)      // le texte à côté dit le niveau (et la carte l'état de charge)
    }
}
