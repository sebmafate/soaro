import Foundation

/// Les trois poignées d'un groupe de seuils, dans l'ordre orange, rouge, écarlate
/// (`LevelThresholds.medium`, `.high`, `.critical`).
enum ThresholdHandle: Int, CaseIterable, Equatable {
    case orange, red, scarlet
}

/// Mesures de la piste, en points. Les tests s'en servent (zone de 24 pt, étiquettes qui ne se chevauchent pas).
enum ThresholdTrackMetrics {
    /// Côté de la zone qui réagit au pointeur : au moins 24 pt (WCAG 2.2, critère 2.5.8, DESIGN.md partie 2).
    static let hitSize: CGFloat = 24
    /// Diamètre dessiné de la poignée (fond blanc, anneau coloré).
    static let handleSize: CGFloat = 20
    static let trackHeight: CGFloat = 10
    /// Largeur fixe de l'étiquette d'une valeur (« 100 % » tient dedans) et espace minimal entre deux étiquettes.
    static let labelWidth: Double = 34
    static let labelSpacing: Double = 4
    static let labelHeight: CGFloat = 16
    /// Marge à gauche et à droite de la piste : la poignée (12 pt de rayon de zone) et l'étiquette (17 pt, plus son décalage)
    /// dépassent de la piste aux valeurs extrêmes.
    static let inset: CGFloat = 22
    /// Largeur la plus étroite où l'écran apparaît : le panneau de la barre de menus (430 pt), moins les marges du formulaire
    /// groupé, mesurée par le rendu hors écran (SL17) : la piste y mesure 325 pt, plus 2 x 22 pt de marges. La fenêtre est plus large.
    static let narrowestContentWidth: Double = 369

    // Hauteurs (points) de la piste : rangée haute des étiquettes relevées, rangée basse, axe des poignées, hauteur totale (légende « now » comprise).
    static let raisedLabelTop: CGFloat = 0
    static let labelTop: CGFloat = 24
    static let centreY: CGFloat = 54
    static let totalHeight: CGFloat = 80

    /// Points d'écran par point de pourcentage, pour une piste dessinée dans `width` pt (marges comprises). 0 si la largeur ne laisse rien.
    static func pointsPerUnit(forWidth width: Double) -> Double {
        max(0, width - 2 * Double(inset)) / 100
    }
}

/// Style de la piste selon les réglages d'accessibilité (rien ne bouge : « Réduire les animations » est sans objet).
enum ThresholdTrackStyle {
    /// Bande « normal » : translucide par défaut, pleine avec « Réduire la transparence » ou « Augmenter le contraste ».
    static func normalBandOpacity(reduceTransparency: Bool, increasedContrast: Bool) -> Double {
        reduceTransparency || increasedContrast ? 1 : 0.55
    }

    /// Contour fin autour de la piste et des poignées avec « Augmenter le contraste ».
    static func outlineWidth(increasedContrast: Bool) -> CGFloat { increasedContrast ? 1 : 0 }

    static func ringWidth(increasedContrast: Bool) -> CGFloat { increasedContrast ? 4 : 3 }
}

/// Valeur actuelle de chaque groupe, en % de 0 à 100 (`nil` : inconnue, le repère est caché).
/// Vient de l'instantané d'`AppState` (le même qui colore la barre de menus), donc en mode démo de l'instantané de démonstration.
struct ThresholdLiveValues: Equatable {
    /// Groupe « Processeur et GPU » : la plus grande des deux charges (les mêmes seuils servent aux deux valeurs de la barre de menus).
    var load: Double?
    /// Groupe « Disque » : la part occupée.
    var disk: Double?
    /// Groupe « Batterie » : le niveau restant.
    var battery: Double?

    init(load: Double?, disk: Double?, battery: Double?) {
        self.load = load; self.disk = disk; self.battery = battery
    }

    init(snapshot: SystemSnapshot?) {
        guard let snapshot else { self.init(load: nil, disk: nil, battery: nil); return }
        func clamped(_ percent: Double) -> Double? { percent.isFinite ? min(100, max(0, percent)) : nil }
        let cpu = clamped(snapshot.cpu.total * 100)
        let gpu = snapshot.gpu.flatMap { clamped($0.utilization * 100) }
        let load = [cpu, gpu].compactMap { $0 }.max()
        let disk = snapshot.disk.total == 0 ? nil : clamped(snapshot.disk.usedFraction * 100)
        let battery = snapshot.battery.flatMap { clamped($0.percent) }
        self.init(load: load, disk: disk, battery: battery)
    }
}

/// Règles PURES de la piste à trois poignées : positions, aimantation, bornes, bandes, étiquettes, touches, textes.
/// Le modèle `LevelThresholds` et sa persistance ne changent pas : la piste ne produit que des états que les anciens
/// Steppers pouvaient produire (pas de 5, écart minimal de 5).
enum ThresholdTrackLogic {
    static let step = 5
    static let minimumGap = 5

    // MARK: Valeurs

    static func value(of handle: ThresholdHandle, in t: LevelThresholds) -> Int {
        switch handle {
        case .orange: t.medium
        case .red: t.high
        case .scarlet: t.critical
        }
    }

    static func with(_ value: Int, for handle: ThresholdHandle, in t: LevelThresholds) -> LevelThresholds {
        var copy = t
        switch handle {
        case .orange: copy.medium = value
        case .red: copy.high = value
        case .scarlet: copy.critical = value
        }
        return copy
    }

    /// Ordre et écart minimal respectés (c'est le cas de tout état que la piste produit).
    static func isValid(_ t: LevelThresholds, ascending: Bool) -> Bool {
        let (low, middle, high) = ascending ? (t.medium, t.high, t.critical) : (t.critical, t.high, t.medium)
        return low >= step && middle - low >= minimumGap && high - middle >= minimumGap && high <= (ascending ? 100 : 95)
    }

    // MARK: Bornes

    /// Plage permise à une poignée, donnée par ses voisines : exactement les anciennes plages des Steppers.
    /// Croissant (charge, disque) : orange 5…(rouge−5), rouge (orange+5)…(écarlate−5), écarlate (rouge+5)…100.
    /// Décroissant (batterie) : orange (rouge+5)…95, rouge (écarlate+5)…(orange−5), écarlate 5…(rouge−5).
    /// Un état abîmé (voisines à moins de 10 points) donnerait une plage vide, et l'ancien `ClosedRange` plantait :
    /// ici la plage se réduit à son bas, jamais vide.
    static func bounds(for handle: ThresholdHandle, in t: LevelThresholds, ascending: Bool) -> ClosedRange<Int> {
        let lower: Int, upper: Int
        if ascending {
            switch handle {
            case .orange: lower = step; upper = t.high - minimumGap
            case .red: lower = t.medium + minimumGap; upper = t.critical - minimumGap
            case .scarlet: lower = t.high + minimumGap; upper = 100
            }
        } else {
            switch handle {
            case .orange: lower = t.high + minimumGap; upper = 95
            case .red: lower = t.critical + minimumGap; upper = t.medium - minimumGap
            case .scarlet: lower = step; upper = t.high - minimumGap
            }
        }
        return lower...max(lower, upper)
    }

    // MARK: Aimantation et glisser

    /// Valeur la plus proche (multiple de 5) d'une position brute en %, ramenée dans les bornes : les poignées ne se croisent jamais.
    static func snapped(_ raw: Double, for handle: ThresholdHandle, in t: LevelThresholds, ascending: Bool) -> Int {
        let range = bounds(for: handle, in: t, ascending: ascending)
        guard raw.isFinite else { return min(max(value(of: handle, in: t), range.lowerBound), range.upperBound) }
        let grid = (raw / Double(step)).rounded() * Double(step)
        let clamped = min(max(grid, Double(range.lowerBound)), Double(range.upperBound))
        return Int(clamped)
    }

    /// Valeur après un glisser de `translation` points depuis `origin` (la valeur de la poignée au début du geste).
    /// La poignée suit le pointeur (de gauche à droite la valeur augmente, aussi pour la batterie).
    static func draggedValue(from origin: Int, translation: Double, pointsPerUnit: Double, handle: ThresholdHandle,
                             in t: LevelThresholds, ascending: Bool) -> Int {
        guard pointsPerUnit > 0 else { return origin }
        return snapped(Double(origin) + translation / pointsPerUnit, for: handle, in: t, ascending: ascending)
    }

    // MARK: Clavier et VoiceOver

    enum Command: Equatable {
        /// Nombre de pas de 5, positif ou négatif.
        case step(Int)
        case lowest, highest
    }

    enum Key: Equatable {
        case left, right, up, down, home, end
    }

    /// Flèches : un pas de 5 (Maj : 10) ; Début et Fin : les bornes. La droite et le haut augmentent la valeur, y compris pour la batterie.
    static func command(for key: Key, shift: Bool) -> Command {
        switch key {
        case .right, .up: .step(shift ? 2 : 1)
        case .left, .down: .step(shift ? -2 : -1)
        case .home: .lowest
        case .end: .highest
        }
    }

    static func apply(_ command: Command, to handle: ThresholdHandle, in t: LevelThresholds, ascending: Bool) -> LevelThresholds {
        let range = bounds(for: handle, in: t, ascending: ascending)
        let current = value(of: handle, in: t)
        let target: Int
        switch command {
        case .step(let count): target = current + count * step
        case .lowest: target = range.lowerBound
        case .highest: target = range.upperBound
        }
        return with(min(max(target, range.lowerBound), range.upperBound), for: handle, in: t)
    }

    // MARK: Bandes de couleur

    enum Band: Equatable { case normal, orange, red, scarlet }

    struct Segment: Equatable {
        var band: Band
        var from: Int
        var to: Int
    }

    /// Les quatre bandes de la piste de 0 à 100 %. Croissant : normal, orange, rouge, écarlate ; batterie : écarlate, rouge, orange, normal.
    static func segments(for t: LevelThresholds, ascending: Bool) -> [Segment] {
        if ascending {
            return [Segment(band: .normal, from: 0, to: t.medium), Segment(band: .orange, from: t.medium, to: t.high),
                    Segment(band: .red, from: t.high, to: t.critical), Segment(band: .scarlet, from: t.critical, to: 100)]
        }
        return [Segment(band: .scarlet, from: 0, to: t.critical), Segment(band: .red, from: t.critical, to: t.high),
                Segment(band: .orange, from: t.high, to: t.medium), Segment(band: .normal, from: t.medium, to: 100)]
    }

    static func fraction(ofPercent percent: Double) -> Double {
        min(1, max(0, percent / 100))
    }

    // MARK: Étiquettes

    struct LabelPlacement: Equatable {
        /// Étiquette relevée sur une seconde rangée, reliée à sa poignée par une tige fine.
        var raised: Bool
        /// Décalage horizontal de l'étiquette par rapport à sa poignée, en points (0 sauf près d'une tige).
        var shift: Double
    }

    /// Place les trois étiquettes pour que rien ne se chevauche. L'étiquette du MILIEU (rouge, dans les deux sens) est relevée quand
    /// elle est trop près d'une voisine pour tenir à côté d'elle : écart en points d'écran inférieur à la largeur d'une étiquette
    /// plus son espace. À 4 pt par point (piste d'environ 400 pt) cela fait un écart inférieur à 9 points, soit 5 ; une piste
    /// plus étroite lève aussi l'étiquette pour un écart de 10. Les étiquettes voisines s'écartent alors de la tige (de quelques points).
    static func labelPlacements(for t: LevelThresholds, pointsPerUnit: Double,
                                labelWidth: Double = ThresholdTrackMetrics.labelWidth,
                                spacing: Double = ThresholdTrackMetrics.labelSpacing) -> [ThresholdHandle: LabelPlacement] {
        let needed = labelWidth + spacing
        let orange = Double(t.medium) * pointsPerUnit
        let red = Double(t.high) * pointsPerUnit
        let scarlet = Double(t.critical) * pointsPerUnit
        let nearest = min(abs(red - orange), abs(scarlet - red))
        guard nearest < needed else {
            return [.orange: LabelPlacement(raised: false, shift: 0), .red: LabelPlacement(raised: false, shift: 0),
                    .scarlet: LabelPlacement(raised: false, shift: 0)]
        }
        // La tige est à `red` : chaque étiquette voisine s'arrête à la moitié de sa largeur, plus 3 pt, de la tige.
        let clearance = labelWidth / 2 + 3
        func shift(_ x: Double) -> Double {
            x <= red ? min(0, (red - clearance) - x) : max(0, (red + clearance) - x)
        }
        return [.orange: LabelPlacement(raised: false, shift: shift(orange)), .red: LabelPlacement(raised: true, shift: 0),
                .scarlet: LabelPlacement(raised: false, shift: shift(scarlet))]
    }

    // MARK: Textes

    static func name(of handle: ThresholdHandle) -> String {
        switch handle {
        case .orange: String(localized: "Orange")
        case .red: String(localized: "Red")
        case .scarlet: String(localized: "Scarlet")
        }
    }

    /// « 60 % » (l'étiquette au-dessus de la poignée).
    static func percentText(_ value: Int) -> String {
        String(localized: "\(value) %")
    }

    /// « from 60 % » / « below 20 % » : la valeur lue par VoiceOver.
    static func valueText(_ value: Int, ascending: Bool) -> String {
        ascending ? String(localized: "from \(value) %") : String(localized: "below \(value) %")
    }

    /// « Orange from 60 % » / « Orange below 20 % » : deux phrases entières, pour que chaque langue place les mots comme elle veut.
    static func legendText(_ handle: ThresholdHandle, value: Int, ascending: Bool) -> String {
        let levelName = name(of: handle)
        return ascending ? String(localized: "\(levelName) from \(value) %") : String(localized: "\(levelName) below \(value) %")
    }

    /// Lu par VoiceOver pour le repère « maintenant ».
    static func nowAccessibilityText(_ percent: Double) -> String {
        let rounded = Int(percent.rounded())
        return String(localized: "Now: \(rounded) %")
    }
}
