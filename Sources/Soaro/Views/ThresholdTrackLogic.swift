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
    /// Largeur fixe de l'étiquette d'une valeur (« 100 % » tient dedans) et espace minimal entre deux étiquettes voisines.
    static let labelWidth: Double = 40
    static let labelSpacing: Double = 4
    static let labelHeight: CGFloat = 16
    /// Marge à gauche et à droite de la piste : la zone de la poignée (12 pt de rayon) dépasse de la piste aux valeurs extrêmes, et
    /// l'étiquette (20 pt de demi-largeur) aussi. Les étiquettes sont de toute façon gardées dans la vue (`labelCentres`).
    static let inset: CGFloat = 22
    /// Largeur la plus étroite où l'écran apparaît : le panneau de la barre de menus (430 pt), moins les marges du formulaire
    /// groupé, mesurée par le rendu hors écran (SL17) : la piste y mesure 325 pt, plus 2 x 22 pt de marges. La fenêtre est plus large.
    static let narrowestContentWidth: Double = 369

    // Hauteurs (points) : une seule rangée d'étiquettes en haut, les traits de rappel, l'axe des poignées, puis le repère « now » et sa légende.
    static let labelTop: CGFloat = 0
    static let centreY: CGFloat = 44
    static let totalHeight: CGFloat = 72

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
    /// LE pas (en points de pourcentage) et LA distance minimale entre deux seuils. 1 et 1 depuis la décision de l'auteur du
    /// 2026-11-18 (à l'origine 5 et 5, comme les Steppers) : changer ces deux lignes suffit pour revenir à 5, toutes les bornes en dérivent.
    static let step = 1
    static let minimumGap = 1
    /// Pas des flèches avec Maj, en points (avec un pas de 1 : 5 ; avec un pas de 5 : 10, soit deux pas).
    static var coarseStep: Int { step == 1 ? 5 : step * 2 }
    /// Valeur la plus basse d'un seuil : un pas (1 ; 5 avec un pas de 5, comme les Steppers).
    static var lowestValue: Int { step }
    /// Valeur la plus haute : 100 pour une valeur qui monte (« jamais » écarlate à 100 existait déjà) ; pour la batterie un pas
    /// de moins (99 ; 95 avec un pas de 5), car « sous 100 % » serait orange en permanence.
    static func highestValue(ascending: Bool) -> Int { ascending ? 100 : 100 - step }

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

    /// Ordre, écart minimal et limites respectés (c'est le cas de tout état que la piste produit).
    static func isValid(_ t: LevelThresholds, ascending: Bool) -> Bool {
        let (low, middle, high) = ascending ? (t.medium, t.high, t.critical) : (t.critical, t.high, t.medium)
        return low >= lowestValue && middle - low >= minimumGap && high - middle >= minimumGap && high <= highestValue(ascending: ascending)
    }

    // MARK: Bornes

    /// Plage permise à une poignée, donnée par ses voisines et séparée d'elles par `minimumGap`. Les limites extérieures sont `lowestValue`
    /// et `highestValue` : elles contiennent celles des anciens Steppers (5 et 100 ; batterie 5 et 95), donc tout état que les Steppers
    /// produisaient reste valide.
    /// Croissant (charge, disque) : orange bas…(rouge−écart), rouge (orange+écart)…(écarlate−écart), écarlate (rouge+écart)…haut.
    /// Décroissant (batterie) : orange (rouge+écart)…haut, rouge (écarlate+écart)…(orange−écart), écarlate bas…(rouge−écart).
    /// Un état abîmé (voisines collées) pourrait donner une plage vide, et l'ancien `ClosedRange` plantait :
    /// ici la plage se réduit à son bas, jamais vide.
    static func bounds(for handle: ThresholdHandle, in t: LevelThresholds, ascending: Bool) -> ClosedRange<Int> {
        let lower: Int, upper: Int
        let top = highestValue(ascending: ascending)
        if ascending {
            switch handle {
            case .orange: lower = lowestValue; upper = t.high - minimumGap
            case .red: lower = t.medium + minimumGap; upper = t.critical - minimumGap
            case .scarlet: lower = t.high + minimumGap; upper = top
            }
        } else {
            switch handle {
            case .orange: lower = t.high + minimumGap; upper = top
            case .red: lower = t.critical + minimumGap; upper = t.medium - minimumGap
            case .scarlet: lower = lowestValue; upper = t.high - minimumGap
            }
        }
        return lower...max(lower, upper)
    }

    // MARK: Aimantation et glisser

    /// Valeur la plus proche (multiple de `step`) d'une position brute en %, ramenée dans les bornes : les poignées ne se croisent jamais.
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
        /// Nombre de pas (`step`), positif ou négatif.
        case step(Int)
        case lowest, highest
    }

    enum Key: Equatable {
        case left, right, up, down, home, end
    }

    /// Flèches : un pas (Maj : `coarseStep` points) ; Début et Fin : les bornes. La droite et le haut augmentent la valeur, y compris pour la batterie.
    static func command(for key: Key, shift: Bool) -> Command {
        let amount = shift ? coarseStep / step : 1
        return switch key {
        case .right, .up: .step(amount)
        case .left, .down: .step(-amount)
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

    // MARK: Quelle poignée saisir

    enum Pick: Equatable {
        /// Le pointeur n'est sur aucune poignée.
        case none
        case handle(ThresholdHandle)
        /// Deux poignées à égale distance du pointeur (de gauche à droite) : la direction du geste décide (`resolve`).
        case undecided([ThresholdHandle])
    }

    /// Les poignées se recouvrent quand les seuils sont proches (3 pt d'écart pour 1 point sur la piste du panneau) : le geste ne
    /// prend donc pas « celle qui est dessus » mais la PLUS PROCHE du pointeur, en distance horizontale, parmi celles dont la zone
    /// (24 x 24 pt) contient le pointeur. À égalité exacte, `.undecided` : on attend la direction du geste.
    static func pickHandle(pointerX: Double, pointerY: Double, thresholds t: LevelThresholds, pointsPerUnit: Double, ascending: Bool) -> Pick {
        let radius = Double(ThresholdTrackMetrics.hitSize) / 2
        guard abs(pointerY - Double(ThresholdTrackMetrics.centreY)) <= radius else { return .none }
        let candidates = ThresholdHandle.allCases.map { handle -> (handle: ThresholdHandle, x: Double, distance: Double) in
            let x = Double(ThresholdTrackMetrics.inset) + Double(value(of: handle, in: t)) * pointsPerUnit
            return (handle, x, abs(pointerX - x))
        }.filter { $0.distance <= radius }
        guard let nearest = candidates.map(\.distance).min() else { return .none }
        let tied = candidates.filter { $0.distance - nearest < 0.01 }.sorted { $0.x < $1.x }
        return tied.count == 1 ? .handle(tied[0].handle) : .undecided(tied.map(\.handle))
    }

    /// Départage des poignées à égalité selon le sens du geste (`direction` : -1 vers la gauche, +1 vers la droite) : parmi celles qui
    /// peuvent encore bouger dans ce sens (borne non atteinte), la plus avancée dans ce sens ; si aucune ne peut, la première de la liste.
    /// `candidates` est donné de gauche à droite.
    static func resolve(_ candidates: [ThresholdHandle], direction: Int, in t: LevelThresholds, ascending: Bool) -> ThresholdHandle {
        func canMove(_ handle: ThresholdHandle) -> Bool {
            let range = bounds(for: handle, in: t, ascending: ascending)
            return range.contains(value(of: handle, in: t) + (direction >= 0 ? step : -step))
        }
        let movable = candidates.filter(canMove)
        if direction >= 0 { return movable.last ?? candidates[0] }
        return movable.first ?? candidates[0]
    }

    // MARK: Étiquettes

    /// Où dessiner l'étiquette d'une poignée : son centre (x, en points) et celui de la poignée, que le trait de rappel relie.
    struct LabelPlacement: Equatable {
        var labelCentre: Double
        var handleX: Double
    }

    /// Une seule rangée d'étiquettes au-dessus de la piste, dans l'ordre des poignées de gauche à droite. Chaque étiquette est centrée
    /// sur sa poignée quand il y a de la place ; sinon elles s'écartent au minimum (largeur + espace entre deux centres), en gardant
    /// leur ordre, sans sortir de [0, `width`]. C'est la régression isotone (pool-adjacent-violators) des positions souhaitées, une
    /// fois retiré le décalage de rang : elle minimise la somme des carrés des déplacements sous ces contraintes, et laisse en place
    /// les étiquettes qui n'ont pas à bouger. Le pire cas (trois seuils à 1 point d'écart) place l'étiquette du milieu sur sa poignée et
    /// les deux autres à `largeur + espace` de part et d'autre ; au bord elles se serrent contre le bord. Les traits de rappel
    /// (étiquette -> poignée) ne se croisent pas, car les deux suites de positions sont dans le même ordre.
    /// - Returns: les centres des étiquettes, dans l'ordre de `handleXs` (qui n'a pas à être trié).
    static func labelCentres(forHandleXs handleXs: [Double], width: Double,
                             labelWidth: Double = ThresholdTrackMetrics.labelWidth,
                             spacing: Double = ThresholdTrackMetrics.labelSpacing) -> [Double] {
        let count = handleXs.count
        guard count > 0 else { return [] }
        let distance = labelWidth + spacing
        let order = handleXs.indices.sorted { handleXs[$0] < handleXs[$1] }
        // Positions souhaitées, rang retiré : le problème devient « suite croissante la plus proche ».
        let shifted = order.enumerated().map { handleXs[$0.element] - Double($0.offset) * distance }
        // Pool-adjacent-violators.
        var blocks: [(sum: Double, size: Int)] = []
        for value in shifted {
            blocks.append((value, 1))
            while blocks.count > 1, blocks[blocks.count - 2].sum / Double(blocks[blocks.count - 2].size) > blocks[blocks.count - 1].sum / Double(blocks[blocks.count - 1].size) {
                let last = blocks.removeLast()
                blocks[blocks.count - 1].sum += last.sum
                blocks[blocks.count - 1].size += last.size
            }
        }
        var fitted: [Double] = []
        for block in blocks { fitted += Array(repeating: block.sum / Double(block.size), count: block.size) }
        // Dans la vue : le premier centre au moins à une demi-largeur du bord gauche, le dernier à une demi-largeur du bord droit.
        let lowest = labelWidth / 2
        let highest = max(lowest, width - labelWidth / 2 - Double(count - 1) * distance)
        var centres = [Double](repeating: 0, count: count)
        for (rank, index) in order.enumerated() {
            centres[index] = min(max(fitted[rank], lowest), highest) + Double(rank) * distance
        }
        return centres
    }

    /// Les étiquettes des trois poignées d'un groupe (une piste de `width` pt, `pointsPerUnit` points par point de pourcentage).
    static func labelPlacements(for t: LevelThresholds, pointsPerUnit: Double, width: Double) -> [ThresholdHandle: LabelPlacement] {
        let xs = ThresholdHandle.allCases.map { Double(ThresholdTrackMetrics.inset) + Double(value(of: $0, in: t)) * pointsPerUnit }
        let centres = labelCentres(forHandleXs: xs, width: width)
        var result: [ThresholdHandle: LabelPlacement] = [:]
        for (index, handle) in ThresholdHandle.allCases.enumerated() {
            result[handle] = LabelPlacement(labelCentre: centres[index], handleX: xs[index])
        }
        return result
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
