import AppKit
import Foundation
import Testing
@testable import Soaro

/// SL17 : la logique PURE de la piste à trois poignées des seuils de couleur (Réglages).
/// Décision de l'auteur (2026-11-18, après avoir vu la piste) : pas de 1 et écart minimal de 1 (d'abord 5, comme les Steppers).
/// Les deux constantes sont `ThresholdTrackLogic.step` et `.minimumGap` : les remettre à 5 rétablit les anciennes plages, et les
/// tests (propriétés sur tous les états, exemples exprimés avec elles) suivent ; seul `theCurrentDecisionIsStepOneAndGapOne` pose
/// les valeurs 1 et 1 en clair, et les nombres d'états (161 700 triplets) ne sont comptés que dans cette décision. Le modèle `LevelThresholds` et sa persistance ne changent pas : tout ce que les Steppers pouvaient
/// produire reste valide et relu à l'identique (test de sur-ensemble).
@Suite struct ThresholdTrackLogicTests {
    typealias Logic = ThresholdTrackLogic

    // MARK: Aide : les anciennes plages des Steppers, recopiées telles quelles de `SettingsView` (avant SL17)

    /// (bas, haut) de chaque Stepper : orange, rouge, écarlate. `nil` si une plage serait invalide (l'ancien code plantait alors).
    static func legacyRanges(_ t: LevelThresholds, ascending: Bool) -> [(Int, Int)]? {
        let ranges: [(Int, Int)]
        if ascending {
            ranges = [(5, t.high - 5), (t.medium + 5, t.critical - 5), (t.high + 5, 100)]
        } else {
            ranges = [(t.high + 5, 95), (t.critical + 5, t.medium - 5), (5, t.high - 5)]
        }
        return ranges.allSatisfy({ $0.0 <= $0.1 }) ? ranges : nil
    }

    /// Tous les états que les anciens Steppers pouvaient produire (pas de 5, écart ≥ 5, orange de la batterie jusqu'à 95).
    static func oldStepperStates(ascending: Bool) -> [LevelThresholds] {
        var states: [LevelThresholds] = []
        let grid = Array(stride(from: 5, through: ascending ? 100 : 95, by: 5))
        for a in grid { for b in grid where b >= a + 5 { for c in grid where c >= b + 5 {
            states.append(ascending ? LevelThresholds(medium: a, high: b, critical: c)
                                    : LevelThresholds(medium: c, high: b, critical: a))
        } } }
        return states
    }

    /// Tous les états que la piste peut produire avec les constantes courantes (pas et écart compris).
    static func allStates(ascending: Bool) -> [LevelThresholds] {
        var states: [LevelThresholds] = []
        let grid = Array(stride(from: Logic.lowestValue, through: Logic.highestValue(ascending: ascending), by: Logic.step))
        for a in grid { for b in grid where b >= a + Logic.minimumGap { for c in grid where c >= b + Logic.minimumGap {
            states.append(ascending ? LevelThresholds(medium: a, high: b, critical: c)
                                    : LevelThresholds(medium: c, high: b, critical: a))
        } } }
        return states
    }

    /// Combinaisons quelconques (valeurs de 1 à 100, écarts quelconques), générateur déterministe.
    static func looseStates(ascending: Bool, count: Int) -> [LevelThresholds] {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Int {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Int(seed % 100) + 1
        }
        return (0..<count).map { _ in
            LevelThresholds(medium: next(), high: next(), critical: next()).sanitized(ascending: ascending)
        }
    }

    // MARK: Pas, écart et bornes

    @Test func theCurrentDecisionIsStepOneAndGapOne() {
        // Décision de l'auteur du 2026-11-18. Pour revenir à 5, changer les deux constantes et ce test.
        #expect(Logic.step == 1)
        #expect(Logic.minimumGap == 1)
        #expect(Logic.lowestValue == 1)
        #expect(Logic.highestValue(ascending: true) == 100)
        #expect(Logic.highestValue(ascending: false) == 99)
        #expect(Logic.coarseStep == 5)
    }

    @Test func theBoundsOfTheDefaultsFollowTheNeighboursByOneGap() {
        let g = Logic.minimumGap
        let load = PressureThresholds.default.load        // 60 / 80 / 95
        #expect(Logic.bounds(for: .orange, in: load, ascending: true) == Logic.lowestValue...(80 - g))
        #expect(Logic.bounds(for: .red, in: load, ascending: true) == (60 + g)...(95 - g))
        #expect(Logic.bounds(for: .scarlet, in: load, ascending: true) == (80 + g)...100)
        let battery = PressureThresholds.default.battery  // 20 / 10 / 5
        #expect(Logic.bounds(for: .orange, in: battery, ascending: false) == (10 + g)...Logic.highestValue(ascending: false))
        #expect(Logic.bounds(for: .red, in: battery, ascending: false) == (5 + g)...(20 - g))
        #expect(Logic.bounds(for: .scarlet, in: battery, ascending: false) == Logic.lowestValue...(10 - g))
    }

    @Test func theDefaultThresholdsAreUnchangedAndValid() {
        #expect(PressureThresholds.default.load == LevelThresholds(medium: 60, high: 80, critical: 95))
        #expect(PressureThresholds.default.disk == LevelThresholds(medium: 80, high: 90, critical: 95))
        #expect(PressureThresholds.default.battery == LevelThresholds(medium: 20, high: 10, critical: 5))
        #expect(Logic.isValid(PressureThresholds.default.load, ascending: true))
        #expect(Logic.isValid(PressureThresholds.default.disk, ascending: true))
        #expect(Logic.isValid(PressureThresholds.default.battery, ascending: false))
    }

    // MARK: Sur-ensemble : tout ce que les anciens Steppers pouvaient produire reste possible, et relu à l'identique

    @Test func everyStateTheOldSteppersCouldProduceIsStillValidAndKeepsItsValues() throws {
        for ascending in [true, false] {
            let states = Self.oldStepperStates(ascending: ascending)
            #expect(states.count == (ascending ? 1_140 : 969))
            for t in states {
                let legacy = try #require(Self.legacyRanges(t, ascending: ascending), "\(t) devrait être valide")
                #expect(Logic.isValid(t, ascending: ascending), "\(t)")
                for handle in ThresholdHandle.allCases {
                    let range = Logic.bounds(for: handle, in: t, ascending: ascending)
                    let old = legacy[handle.rawValue]
                    let value = Logic.value(of: handle, in: t)
                    // La plage permise contient l'ancienne, et la valeur y est : la poignée est affichée où elle était.
                    #expect(range.lowerBound <= old.0 && range.upperBound >= old.1, "\(ascending) \(handle) \(t) : \(range) ne contient pas \(old)")
                    #expect(range.contains(value), "\(ascending) \(handle) \(t)")
                    #expect(Logic.snapped(Double(value), for: handle, in: t, ascending: ascending) == value)
                }
            }
        }
    }

    @Test func theNewRangesContainTheOldOnesOnManyLooseCombinations() {
        var compared = 0
        for ascending in [true, false] {
            for t in Self.looseStates(ascending: ascending, count: 30_000) {
                guard let legacy = Self.legacyRanges(t, ascending: ascending) else { continue }
                for handle in ThresholdHandle.allCases {
                    let range = Logic.bounds(for: handle, in: t, ascending: ascending)
                    #expect(range.lowerBound <= legacy[handle.rawValue].0 && range.upperBound >= legacy[handle.rawValue].1, "\(t)")
                    compared += 1
                }
            }
        }
        #expect(compared > 3_000, "trop peu de combinaisons comparées : \(compared)")
    }

    @Test func savedValuesLoadAndDisplayUnchanged() throws {
        // Aucune migration : toute valeur enregistrée qu'`PressureThresholds.load` accepte s'affiche telle quelle sur la piste.
        let suite = "soaro.sl17.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for t in Self.looseStates(ascending: true, count: 300) + Self.oldStepperStates(ascending: true).enumerated().filter({ $0.offset % 13 == 0 }).map(\.element) {
            var all = PressureThresholds.default
            all.load = t
            all.save(to: defaults)
            let loaded = PressureThresholds.load(from: defaults).load
            #expect(loaded == t.sanitized(ascending: true))
            for handle in ThresholdHandle.allCases {
                #expect(Logic.value(of: handle, in: loaded) == Logic.value(of: handle, in: t.sanitized(ascending: true)))
            }
        }
        for t in Self.looseStates(ascending: false, count: 300) {
            var all = PressureThresholds.default
            all.battery = t
            all.save(to: defaults)
            #expect(PressureThresholds.load(from: defaults).battery == t.sanitized(ascending: false))
        }
    }

    @Test func aStateTheHandlesCanReachSurvivesTheSanitizingOfTheSavedPreferences() {
        for ascending in [true, false] {
            for t in Self.allStates(ascending: ascending) {
                #expect(t.sanitized(ascending: ascending) == t)
            }
        }
    }

    @Test func aValueSavedThroughTheTrackRoundTripsThroughThePreferences() throws {
        let suite = "soaro.sl17.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var all = PressureThresholds.default
        let loadValue = Logic.snapped(71, for: .orange, in: all.load, ascending: true)
        let batteryValue = Logic.snapped(33, for: .orange, in: all.battery, ascending: false)
        all.load = Logic.with(loadValue, for: .orange, in: all.load)
        all.battery = Logic.with(batteryValue, for: .orange, in: all.battery)
        all.save(to: defaults)
        #expect(PressureThresholds.load(from: defaults) == all)
        #expect(all.load.medium == loadValue && all.load.high == 80 && all.load.critical == 95)
        #expect(all.battery.medium == batteryValue && all.battery.high == 10 && all.battery.critical == 5)
    }

    @Test func anInvalidStateNeverCrashesAndGivesANonEmptyRange() {
        // Préférences abîmées (valeurs égales, voisines collées) : l'ancien `ClosedRange` aurait planté, la piste ne doit pas.
        let odd = [LevelThresholds(medium: 100, high: 100, critical: 100), LevelThresholds(medium: 1, high: 1, critical: 1),
                   LevelThresholds(medium: 60, high: 60, critical: 61), LevelThresholds(medium: 50, high: 50, critical: 100)]
        for t in odd {
            for ascending in [true, false] {
                for handle in ThresholdHandle.allCases {
                    let range = Logic.bounds(for: handle, in: t, ascending: ascending)
                    #expect(range.lowerBound <= range.upperBound)
                    _ = Logic.snapped(42, for: handle, in: t, ascending: ascending)
                    _ = Logic.apply(.step(1), to: handle, in: t, ascending: ascending)
                    _ = Logic.apply(.highest, to: handle, in: t, ascending: ascending)
                }
            }
        }
    }

    // MARK: Valeurs et ordre des poignées

    @Test func handlesMapToTheThreeLevelsInOrder() {
        let t = LevelThresholds(medium: 60, high: 80, critical: 95)
        #expect(ThresholdHandle.allCases == [.orange, .red, .scarlet])
        #expect(Logic.value(of: .orange, in: t) == 60)
        #expect(Logic.value(of: .red, in: t) == 80)
        #expect(Logic.value(of: .scarlet, in: t) == 95)
        #expect(Logic.with(70, for: .orange, in: t) == LevelThresholds(medium: 70, high: 80, critical: 95))
        #expect(Logic.with(85, for: .red, in: t) == LevelThresholds(medium: 60, high: 85, critical: 95))
        #expect(Logic.with(100, for: .scarlet, in: t) == LevelThresholds(medium: 60, high: 80, critical: 100))
    }

    @Test func isValidRequiresTheOrderTheGapAndTheLimits() {
        let g = Logic.minimumGap
        #expect(Logic.isValid(LevelThresholds(medium: 60, high: 80, critical: 95), ascending: true))
        #expect(Logic.isValid(LevelThresholds(medium: 60, high: 60 + g, critical: 60 + 2 * g), ascending: true))
        #expect(!Logic.isValid(LevelThresholds(medium: 60, high: 60 + g - 1, critical: 95), ascending: true))     // écart trop petit
        #expect(!Logic.isValid(LevelThresholds(medium: 80, high: 60, critical: 95), ascending: true))             // dans le désordre
        #expect(!Logic.isValid(LevelThresholds(medium: 0, high: 60, critical: 95), ascending: true))              // sous le plus bas
        #expect(!Logic.isValid(LevelThresholds(medium: 60, high: 80, critical: 101), ascending: true))
        #expect(Logic.isValid(LevelThresholds(medium: 20, high: 10, critical: 5), ascending: false))
        #expect(!Logic.isValid(LevelThresholds(medium: 20, high: 10, critical: 10), ascending: false))
        #expect(!Logic.isValid(LevelThresholds(medium: Logic.highestValue(ascending: false) + 1, high: 10, critical: 5), ascending: false))
    }

    // MARK: Aimantation, les poignées ne se croisent jamais

    @Test func snappingRoundsToTheNearestStep() {
        let t = PressureThresholds.default.load
        let s = Double(Logic.step)
        #expect(Logic.snapped(60 + 0.4 * s, for: .orange, in: t, ascending: true) == 60)
        #expect(Logic.snapped(60 + 0.6 * s, for: .orange, in: t, ascending: true) == 60 + Logic.step)
        #expect(Logic.snapped(40, for: .orange, in: t, ascending: true) == 40)
        #expect(Logic.snapped(.nan, for: .orange, in: t, ascending: true) == 60)         // la valeur actuelle
    }

    @Test func snappingStopsAtTheNeighbours() {
        let g = Logic.minimumGap
        let load = PressureThresholds.default.load           // 60 / 80 / 95
        #expect(Logic.snapped(100, for: .orange, in: load, ascending: true) == 80 - g)
        #expect(Logic.snapped(-30, for: .orange, in: load, ascending: true) == Logic.lowestValue)
        #expect(Logic.snapped(0, for: .red, in: load, ascending: true) == 60 + g)
        #expect(Logic.snapped(100, for: .red, in: load, ascending: true) == 95 - g)
        #expect(Logic.snapped(10, for: .scarlet, in: load, ascending: true) == 80 + g)
        #expect(Logic.snapped(500, for: .scarlet, in: load, ascending: true) == 100)
        let battery = PressureThresholds.default.battery     // 20 / 10 / 5
        #expect(Logic.snapped(100, for: .orange, in: battery, ascending: false) == Logic.highestValue(ascending: false))
        #expect(Logic.snapped(0, for: .orange, in: battery, ascending: false) == 10 + g)
        #expect(Logic.snapped(100, for: .red, in: battery, ascending: false) == 20 - g)
        #expect(Logic.snapped(0, for: .red, in: battery, ascending: false) == 5 + g)
        #expect(Logic.snapped(60, for: .scarlet, in: battery, ascending: false) == 10 - g)
    }

    @Test func whateverTheDragTheStateStaysValidAndInOrder() {
        for ascending in [true, false] {
            for t in Self.allStates(ascending: ascending).enumerated().filter({ $0.offset % 997 == 0 }).map(\.element) {
                for handle in ThresholdHandle.allCases {
                    for raw in stride(from: -40.0, through: 140.0, by: 3.7) {
                        let value = Logic.snapped(raw, for: handle, in: t, ascending: ascending)
                        let moved = Logic.with(value, for: handle, in: t)
                        #expect(Logic.isValid(moved, ascending: ascending), "\(t) -> \(moved)")
                        #expect(value % Logic.step == 0)
                    }
                }
            }
        }
    }

    @Test func isValidIsExactlyWhatEveryHandleMoveKeepsValid() {
        // Chaque valeur d'une plage permise donne un état valide, et la valeur juste en dehors n'en donne pas.
        for ascending in [true, false] {
            for t in Self.allStates(ascending: ascending).enumerated().filter({ $0.offset % 1_499 == 0 }).map(\.element) {
                for handle in ThresholdHandle.allCases {
                    let range = Logic.bounds(for: handle, in: t, ascending: ascending)
                    for v in stride(from: range.lowerBound, through: range.upperBound, by: Logic.step) {
                        #expect(Logic.isValid(Logic.with(v, for: handle, in: t), ascending: ascending), "\(t) \(handle) \(v)")
                    }
                    #expect(!Logic.isValid(Logic.with(range.upperBound + Logic.step, for: handle, in: t), ascending: ascending), "\(t) \(handle) au-dessus")
                    #expect(!Logic.isValid(Logic.with(range.lowerBound - Logic.step, for: handle, in: t), ascending: ascending), "\(t) \(handle) au-dessous")
                }
            }
        }
    }

    // MARK: Glisser

    @Test func draggingMovesByTheTranslationAndSnaps() {
        let t = PressureThresholds.default.load           // 60 / 80 / 95
        let ppu = 3.2
        let s = Double(Logic.step)
        #expect(Logic.draggedValue(from: 60, translation: 3.2 * 2 * s, pointsPerUnit: ppu, handle: .orange, in: t, ascending: true) == 60 + 2 * Logic.step)
        #expect(Logic.draggedValue(from: 60, translation: -3.2 * 2 * s, pointsPerUnit: ppu, handle: .orange, in: t, ascending: true) == 60 - 2 * Logic.step)
        #expect(Logic.draggedValue(from: 60, translation: 3.2 * 0.4 * s, pointsPerUnit: ppu, handle: .orange, in: t, ascending: true) == 60)   // moins d'un demi-pas
        #expect(Logic.draggedValue(from: 60, translation: 3.2 * 0.6 * s, pointsPerUnit: ppu, handle: .orange, in: t, ascending: true) == 60 + Logic.step)
        #expect(Logic.draggedValue(from: 60, translation: 5_000, pointsPerUnit: ppu, handle: .orange, in: t, ascending: true) == 80 - Logic.minimumGap)
        #expect(Logic.draggedValue(from: 60, translation: -5_000, pointsPerUnit: ppu, handle: .orange, in: t, ascending: true) == Logic.lowestValue)
        // Largeur nulle ou négative : pas de division par zéro, la valeur ne bouge pas.
        #expect(Logic.draggedValue(from: 60, translation: 40, pointsPerUnit: 0, handle: .orange, in: t, ascending: true) == 60)
    }

    @Test func draggingTheBatteryHandlesFollowsThePointerNotTheDirectionOfTheScale() {
        let t = PressureThresholds.default.battery       // 20 / 10 / 5 : l'écarlate est à gauche, l'orange à droite
        #expect(Logic.draggedValue(from: 20, translation: 32, pointsPerUnit: 3.2, handle: .orange, in: t, ascending: false) == 30)
        #expect(Logic.draggedValue(from: 20, translation: -32, pointsPerUnit: 3.2, handle: .orange, in: t, ascending: false) == 10 + Logic.minimumGap)
    }

    // MARK: Quelle poignée saisir

    /// Les poignées de `t` à 3,2 pt par point, sur une piste de 369 pt (le panneau).
    private func xs(_ t: LevelThresholds) -> [ThresholdHandle: Double] {
        Dictionary(uniqueKeysWithValues: ThresholdHandle.allCases.map {
            ($0, Double(ThresholdTrackMetrics.inset) + Double(Logic.value(of: $0, in: t)) * 3.2)
        })
    }
    private let ppu = 3.2
    private var centreY: Double { Double(ThresholdTrackMetrics.centreY) }
    private func pick(_ x: Double, _ t: LevelThresholds, ascending: Bool = true, y: Double? = nil) -> ThresholdTrackLogic.Pick {
        Logic.pickHandle(pointerX: x, pointerY: y ?? centreY, thresholds: t, pointsPerUnit: ppu, ascending: ascending)
    }

    @Test func thePointerPicksTheNearestHandle() {
        let t = LevelThresholds(medium: 60, high: 80, critical: 95)
        let x = xs(t)
        #expect(pick(x[.orange]!, t) == .handle(.orange))
        #expect(pick(x[.orange]! + 4, t) == .handle(.orange))
        #expect(pick(x[.red]! - 3, t) == .handle(.red))
        #expect(pick(x[.scarlet]! + 5, t) == .handle(.scarlet))
    }

    @Test func overlappingHandlesAreToldApartByDistance() {
        // Trois poignées à 1 point d'écart (3,2 pt) : la plus proche du pointeur gagne, de chaque côté.
        let t = LevelThresholds(medium: 50, high: 51, critical: 52)
        let x = xs(t)
        #expect(pick(x[.orange]! - 6, t) == .handle(.orange))
        #expect(pick(x[.orange]! + 0.5, t) == .handle(.orange))
        #expect(pick(x[.red]! + 0.4, t) == .handle(.red))
        #expect(pick(x[.scarlet]! - 0.5, t) == .handle(.scarlet))
        #expect(pick(x[.scarlet]! + 6, t) == .handle(.scarlet))
    }

    @Test func aPointerFarFromEveryHandleOrOffTheTrackPicksNothing() {
        let t = LevelThresholds(medium: 60, high: 80, critical: 95)
        let x = xs(t)
        #expect(pick(x[.orange]! + 40, t) == .none)
        #expect(pick(x[.orange]!, t, y: centreY + Double(ThresholdTrackMetrics.hitSize)) == .none)
        #expect(pick(x[.orange]!, t, y: centreY - Double(ThresholdTrackMetrics.hitSize)) == .none)
        #expect(pick(x[.orange]!, t, y: centreY + Double(ThresholdTrackMetrics.hitSize) / 2 - 1) == .handle(.orange))
    }

    @Test func anExactTieWaitsForTheDirectionOfTheDragAndPicksTheHandleThatCanMove() {
        // Orange 50 et rouge 52 : le milieu est à égale distance des deux ; le rouge est à droite, l'orange à gauche.
        let t = LevelThresholds(medium: 50, high: 52, critical: 90)
        let x = xs(t)
        let middle = (x[.orange]! + x[.red]!) / 2
        #expect(pick(middle, t) == .undecided([.orange, .red]))
        #expect(Logic.resolve([.orange, .red], direction: 1, in: t, ascending: true) == .red)      // vers la droite : le rouge peut avancer
        #expect(Logic.resolve([.orange, .red], direction: -1, in: t, ascending: true) == .orange)  // vers la gauche : l'orange peut reculer
    }

    @Test func aTieSkipsAHandleBlockedByItsNeighbour() {
        // Le plus avancé dans le sens du geste est bloqué (rouge contre l'écarlate, orange au plus bas) : l'autre est choisi.
        let g = Logic.minimumGap
        let leadingRedBlocked = LevelThresholds(medium: 50, high: 90 - g, critical: 90)
        #expect(Logic.resolve([.orange, .red], direction: 1, in: leadingRedBlocked, ascending: true) == .orange)
        let leadingOrangeBlocked = LevelThresholds(medium: Logic.lowestValue, high: 60, critical: 90)
        #expect(Logic.resolve([.orange, .red], direction: -1, in: leadingOrangeBlocked, ascending: true) == .red)
        // Orange 50 et rouge 51 collés, scarlet loin : vers la droite l'orange est bloqué par le rouge, le rouge avance.
        let t = LevelThresholds(medium: 50, high: 51, critical: 90)
        #expect(Logic.resolve([.orange, .red], direction: 1, in: t, ascending: true) == .red)
        // Le rouge collé au scarlet : vers la droite il est bloqué, l'orange (qui a de la place) est choisi.
        let t2 = LevelThresholds(medium: 50, high: 89, critical: 90)
        #expect(Logic.resolve([.red, .scarlet], direction: 1, in: t2, ascending: true) == .scarlet)
        #expect(Logic.resolve([.red, .scarlet], direction: -1, in: t2, ascending: true) == .red)
        // Aucun ne peut bouger dans ce sens (les deux butent) : le premier de la liste, sans planter.
        let blocked = LevelThresholds(medium: 1, high: 2, critical: 3)
        #expect(Logic.resolve([.orange, .red], direction: -1, in: blocked, ascending: true) == .orange)
    }

    @Test func theBatteryIsPickedAndResolvedByPositionNotByLevel() {
        // Batterie 20 / 11 / 10 : l'écarlate (10) est à gauche du rouge (11), qui est à gauche de l'orange (20).
        let t = LevelThresholds(medium: 20, high: 11, critical: 10)
        let x = xs(t)
        #expect(pick(x[.scarlet]! - 6, t, ascending: false) == .handle(.scarlet))
        let tie = LevelThresholds(medium: 40, high: 22, critical: 20)
        let xt = xs(tie)
        #expect(pick((xt[.scarlet]! + xt[.red]!) / 2, tie, ascending: false) == .undecided([.scarlet, .red]))      // dans l'ordre de gauche à droite
        #expect(Logic.resolve([.scarlet, .red], direction: 1, in: tie, ascending: false) == .red)
        #expect(Logic.resolve([.scarlet, .red], direction: -1, in: tie, ascending: false) == .scarlet)
    }

    // MARK: Clavier et VoiceOver

    @Test func stepCommandsMoveByOneStepAndStayInTheBounds() {
        let t = PressureThresholds.default.load
        let s = Logic.step
        #expect(Logic.apply(.step(1), to: .orange, in: t, ascending: true) == LevelThresholds(medium: 60 + s, high: 80, critical: 95))
        #expect(Logic.apply(.step(-1), to: .orange, in: t, ascending: true) == LevelThresholds(medium: 60 - s, high: 80, critical: 95))
        #expect(Logic.apply(.step(2), to: .orange, in: t, ascending: true) == LevelThresholds(medium: 60 + 2 * s, high: 80, critical: 95))
        #expect(Logic.apply(.step(-2), to: .red, in: t, ascending: true) == LevelThresholds(medium: 60, high: 80 - 2 * s, critical: 95))
        // Contre un voisin : ne bouge plus.
        let g = Logic.minimumGap
        let tight = LevelThresholds(medium: 60, high: 60 + g, critical: 60 + 2 * g)
        #expect(Logic.apply(.step(1), to: .orange, in: tight, ascending: true) == tight)
        #expect(Logic.apply(.step(-1), to: .red, in: tight, ascending: true) == tight)
        #expect(Logic.apply(.step(1), to: .red, in: tight, ascending: true) == tight)
        // Plus loin que la borne : s'arrête à la borne.
        #expect(Logic.apply(.step(1_000), to: .red, in: t, ascending: true) == LevelThresholds(medium: 60, high: 95 - g, critical: 95))
    }

    @Test func homeAndEndJumpToTheBounds() {
        let t = PressureThresholds.default.load
        let g = Logic.minimumGap
        #expect(Logic.apply(.lowest, to: .orange, in: t, ascending: true) == LevelThresholds(medium: Logic.lowestValue, high: 80, critical: 95))
        #expect(Logic.apply(.highest, to: .orange, in: t, ascending: true) == LevelThresholds(medium: 80 - g, high: 80, critical: 95))
        #expect(Logic.apply(.lowest, to: .red, in: t, ascending: true) == LevelThresholds(medium: 60, high: 60 + g, critical: 95))
        #expect(Logic.apply(.highest, to: .scarlet, in: t, ascending: true) == LevelThresholds(medium: 60, high: 80, critical: 100))
        let battery = PressureThresholds.default.battery
        #expect(Logic.apply(.highest, to: .orange, in: battery, ascending: false) == LevelThresholds(medium: Logic.highestValue(ascending: false), high: 10, critical: 5))
        #expect(Logic.apply(.lowest, to: .orange, in: battery, ascending: false) == LevelThresholds(medium: 10 + g, high: 10, critical: 5))
    }

    @Test func keysMapToCommands() {
        #expect(Logic.command(for: .right, shift: false) == .step(1))
        #expect(Logic.command(for: .up, shift: false) == .step(1))
        #expect(Logic.command(for: .left, shift: false) == .step(-1))
        #expect(Logic.command(for: .down, shift: false) == .step(-1))
        // Maj : 5 points (`coarseStep`), soit autant de pas.
        #expect(Logic.command(for: .right, shift: true) == .step(Logic.coarseStep / Logic.step))
        #expect(Logic.command(for: .left, shift: true) == .step(-Logic.coarseStep / Logic.step))
        #expect(Logic.command(for: .home, shift: false) == .lowest)
        #expect(Logic.command(for: .end, shift: false) == .highest)
        #expect(Logic.command(for: .home, shift: true) == .lowest)
        #expect(Logic.coarseStep > Logic.step)
    }

    @Test func shiftArrowMovesByFivePoints() {
        let t = PressureThresholds.default.load
        let up = Logic.apply(Logic.command(for: .right, shift: true), to: .orange, in: t, ascending: true)
        #expect(up.medium == 60 + Logic.coarseStep)
    }

    @Test func theArrowsDoNotFlipForTheDescendingGroup() {
        // Pour la batterie aussi, flèche droite = valeur plus grande (la piste va de 0 à 100 de gauche à droite).
        let t = PressureThresholds.default.battery
        let up = Logic.apply(Logic.command(for: .right, shift: false), to: .orange, in: t, ascending: false)
        #expect(up.medium == 20 + Logic.step)
    }

    @Test func voiceOverIncrementsAndDecrementsByOneStepInTheBounds() {
        // VoiceOver passe par `.step(±1)` : un pas, jamais le pas de Maj.
        let t = PressureThresholds.default.load
        #expect(Logic.apply(.step(1), to: .red, in: t, ascending: true).high == 80 + Logic.step)
        #expect(Logic.apply(.step(-1), to: .red, in: t, ascending: true).high == 80 - Logic.step)
        let atTop = LevelThresholds(medium: 60, high: 95 - Logic.minimumGap, critical: 95)
        #expect(Logic.apply(.step(1), to: .red, in: atTop, ascending: true) == atTop)
    }


    // MARK: Étiquettes : une rangée au-dessus de la piste, écartées au minimum, avec un trait vers leur poignée

    typealias Metrics = ThresholdTrackMetrics
    /// Largeurs de la vue : un peu moins que le panneau, le panneau (325 pt de piste + 2 x 22 pt de marges), deux intermédiaires, la fenêtre.
    static let widths: [Double] = [320, 369, 450, 700, 860]

    private func handleXs(_ values: [Int], width: Double) -> [Double] {
        let unit = Metrics.pointsPerUnit(forWidth: width)
        return values.map { Double(Metrics.inset) + Double($0) * unit }
    }

    /// Les deux segments [(x1, y1), (x2, y2)] se coupent-ils (hors extrémités communes) ?
    private func cross(_ a: (Double, Double, Double, Double), _ b: (Double, Double, Double, Double)) -> Bool {
        func side(_ px: Double, _ py: Double, _ qx: Double, _ qy: Double, _ rx: Double, _ ry: Double) -> Double {
            (qx - px) * (ry - py) - (qy - py) * (rx - px)
        }
        let d1 = side(a.0, a.1, a.2, a.3, b.0, b.1), d2 = side(a.0, a.1, a.2, a.3, b.2, b.3)
        let d3 = side(b.0, b.1, b.2, b.3, a.0, a.1), d4 = side(b.0, b.1, b.2, b.3, a.2, a.3)
        return d1 * d2 < 0 && d3 * d4 < 0
    }

    @Test func labelsKeepToTheirHandleWhenThereIsRoom() {
        for width in Self.widths {
            let x = handleXs([20, 50, 90], width: width)
            let centres = Logic.labelCentres(forHandleXs: x, width: width)
            for (c, h) in zip(centres, x) { #expect(abs(c - h) < 1e-9, "largeur \(width)") }
        }
    }

    @Test func threeHandlesOnePointApartSpreadTheirLabelsAroundTheMiddleOne() {
        let width = 369.0
        let x = handleXs([50, 51, 52], width: width)
        let d = Metrics.labelWidth + Metrics.labelSpacing
        let c = Logic.labelCentres(forHandleXs: x, width: width)
        #expect(abs(c[1] - x[1]) < 1e-9)                      // celle du milieu reste au-dessus de sa poignée
        #expect(abs(c[0] - (x[1] - d)) < 1e-9)
        #expect(abs(c[2] - (x[1] + d)) < 1e-9)
    }

    @Test func labelsStayInsideTheTrackAtTheEdges() {
        let width = 369.0
        let half = Metrics.labelWidth / 2
        let d = Metrics.labelWidth + Metrics.labelSpacing
        let left = Logic.labelCentres(forHandleXs: handleXs([1, 2, 3], width: width), width: width)
        #expect(abs(left[0] - half) < 1e-9 && abs(left[1] - (half + d)) < 1e-9 && abs(left[2] - (half + 2 * d)) < 1e-9)
        let right = Logic.labelCentres(forHandleXs: handleXs([98, 99, 100], width: width), width: width)
        #expect(abs(right[2] - (width - half)) < 1e-9 && abs(right[1] - (width - half - d)) < 1e-9 && abs(right[0] - (width - half - 2 * d)) < 1e-9)
    }

    @Test func theInputOrderDoesNotMatterOnlyThePositions() {
        // La batterie : l'écarlate (premier handle de la liste) est à gauche, l'orange à droite.
        let width = 369.0
        let x = [handleXs([5], width: width)[0], handleXs([6], width: width)[0], handleXs([7], width: width)[0]]
        let forward = Logic.labelCentres(forHandleXs: x, width: width)
        let backward = Logic.labelCentres(forHandleXs: x.reversed(), width: width)
        #expect(forward == backward.reversed())
    }

    @Test func labelsNeverOverlapStayInsideAndKeepTheOrderOfTheHandlesOnEveryStateAtEveryWidth() {
        let d = Metrics.labelWidth + Metrics.labelSpacing
        let half = Metrics.labelWidth / 2
        let labelBottom = Double(Metrics.labelTop + Metrics.labelHeight), handleY = Double(Metrics.centreY)
        // Tous les triplets croissants : le résultat ne dépend que des positions, donc vaut pour les deux sens (la batterie en est l'image miroir).
        let states = Self.allStates(ascending: true)
        #expect(states.count > 1_000)
        for width in Self.widths {
            let unit = Metrics.pointsPerUnit(forWidth: width)
            var failures: [String] = []
            for (index, t) in states.enumerated() {
                let x = [Double(Metrics.inset) + Double(t.medium) * unit, Double(Metrics.inset) + Double(t.high) * unit, Double(Metrics.inset) + Double(t.critical) * unit]
                let c = Logic.labelCentres(forHandleXs: x, width: width)
                var problem: String?
                if c[1] - c[0] < d - 1e-9 || c[2] - c[1] < d - 1e-9 { problem = "chevauchement" }
                else if c[0] - half < -1e-9 || c[2] + half > width + 1e-9 { problem = "hors de la piste" }
                else if !(c[0] < c[1] && c[1] < c[2]) || !(x[0] < x[1] && x[1] < x[2]) { problem = "ordre" }
                else if abs(c[0] - x[0]) > 2 * d + 1e-9 || abs(c[2] - x[2]) > 2 * d + 1e-9 { problem = "trop loin de la poignée" }
                else if index % 11 == 0 {
                    // Les traits (étiquette -> poignée) ne se croisent pas.
                    let segments = (0..<3).map { (c[$0], labelBottom, x[$0], handleY) }
                    if cross(segments[0], segments[1]) || cross(segments[1], segments[2]) || cross(segments[0], segments[2]) { problem = "traits croisés" }
                }
                if let problem, failures.count < 5 { failures.append("\(problem) : \(t) à \(width) pt") }
            }
            #expect(failures.isEmpty, "\(failures)")
        }
    }

    @Test func aLabelIsNeverMovedWhenItNeedsNoMoving() {
        // Propriété : si les positions souhaitées respectent déjà l'écart et la piste, rien ne bouge.
        let d = Metrics.labelWidth + Metrics.labelSpacing
        var checked = 0
        for width in Self.widths {
            let unit = Metrics.pointsPerUnit(forWidth: width)
            let all = Self.allStates(ascending: true)
            for t in all.enumerated().filter({ $0.offset % (all.count / 3_000 + 1) == 0 }).map(\.element) {
                let x = [t.medium, t.high, t.critical].map { Double(Metrics.inset) + Double($0) * unit }
                guard x[1] - x[0] >= d, x[2] - x[1] >= d else { continue }
                let c = Logic.labelCentres(forHandleXs: x, width: width)
                #expect(c == x, "\(t) à \(width) pt")
                checked += 1
            }
        }
        #expect(checked > 100)
    }

    @Test func eachLabelBelongsToItsHandleForBothDirections() {
        let width = 369.0
        let unit = Metrics.pointsPerUnit(forWidth: width)
        for ascending in [true, false] {
            for t in Self.allStates(ascending: ascending).enumerated().filter({ $0.offset % 211 == 0 }).map(\.element) {
                let placements = Logic.labelPlacements(for: t, pointsPerUnit: unit, width: width)
                let byHandle = ThresholdHandle.allCases.compactMap { handle in placements[handle].map { (handle, $0) } }
                #expect(byHandle.count == 3)
                for (handle, p) in byHandle {
                    let expectedX = Double(Metrics.inset) + Double(Logic.value(of: handle, in: t)) * unit
                    #expect(abs(p.handleX - expectedX) < 1e-9)
                }
                // Le trait de gauche va à la poignée de gauche : l'ordre des étiquettes est celui des poignées.
                let sortedByHandle = byHandle.sorted { $0.1.handleX < $1.1.handleX }
                #expect(sortedByHandle.map { $0.1.labelCentre } == sortedByHandle.map { $0.1.labelCentre }.sorted())
                #expect(ascending ? sortedByHandle.map { $0.0 } == [.orange, .red, .scarlet] : sortedByHandle.map { $0.0 } == [.scarlet, .red, .orange])
            }
        }
    }

    @Test func aThreeDigitValueFitsItsLabel() {
        // « 100 % » en `.caption2` gras à chiffres de même largeur tient dans l'étiquette, bordure comprise.
        let base = NSFont.preferredFont(forTextStyle: .caption2)
        let font = NSFont.monospacedDigitSystemFont(ofSize: base.pointSize, weight: .semibold)
        let width = (Logic.percentText(100) as NSString).size(withAttributes: [.font: font]).width
        #expect(width + 2 * 1.5 + 2 <= Metrics.labelWidth, "« 100 % » mesure \(width) pt pour une étiquette de \(Metrics.labelWidth) pt")
    }

    @Test func labelsNeedLessThanTheNarrowestWidth() {
        // Trois étiquettes côte à côte : 3 largeurs et 2 espaces tiennent dans la plus petite vue prévue.
        #expect(3 * Metrics.labelWidth + 2 * Metrics.labelSpacing <= Self.widths[0])
        #expect(Metrics.pointsPerUnit(forWidth: Metrics.narrowestContentWidth) > 2.5)
    }


    // MARK: T2 : bandes de couleur

    @Test func bandsFollowTheHandlesForAscendingGroups() {
        let t = LevelThresholds(medium: 60, high: 80, critical: 95)
        #expect(Logic.segments(for: t, ascending: true) == [
            .init(band: .normal, from: 0, to: 60), .init(band: .orange, from: 60, to: 80),
            .init(band: .red, from: 80, to: 95), .init(band: .scarlet, from: 95, to: 100),
        ])
    }

    @Test func bandsFollowTheHandlesForTheBattery() {
        let t = LevelThresholds(medium: 20, high: 10, critical: 5)
        #expect(Logic.segments(for: t, ascending: false) == [
            .init(band: .scarlet, from: 0, to: 5), .init(band: .red, from: 5, to: 10),
            .init(band: .orange, from: 10, to: 20), .init(band: .normal, from: 20, to: 100),
        ])
    }

    @Test func bandsAlwaysCoverTheWholeTrackWithoutHolesOrOverlap() {
        for ascending in [true, false] {
            for t in Self.allStates(ascending: ascending).enumerated().filter({ $0.offset % 97 == 0 }).map(\.element) + Self.looseStates(ascending: ascending, count: 500) {
                let segments = Logic.segments(for: t, ascending: ascending)
                #expect(segments.count == 4)
                #expect(segments.first?.from == 0 && segments.last?.to == 100)
                for (a, b) in zip(segments, segments.dropFirst()) { #expect(a.to == b.from) }
                for s in segments { #expect(s.from <= s.to) }
            }
        }
    }


    // MARK: T3 : textes

    @Test func valueTextsAreComplete() {
        #expect(Logic.valueText(60, ascending: true) == "from 60 %")
        #expect(Logic.valueText(20, ascending: false) == "below 20 %")
        #expect(Logic.percentText(60) == "60 %")
        #expect(Logic.legendText(.orange, value: 60, ascending: true) == "Orange from 60 %")
        #expect(Logic.legendText(.red, value: 80, ascending: true) == "Red from 80 %")
        #expect(Logic.legendText(.scarlet, value: 95, ascending: true) == "Scarlet from 95 %")
        #expect(Logic.legendText(.orange, value: 20, ascending: false) == "Orange below 20 %")
        #expect(Logic.legendText(.scarlet, value: 5, ascending: false) == "Scarlet below 5 %")
        #expect(Logic.name(of: .orange) == "Orange")
        #expect(Logic.name(of: .red) == "Red")
        #expect(Logic.name(of: .scarlet) == "Scarlet")
        #expect(Logic.nowAccessibilityText(36.4) == "Now: 36 %")
    }

    // MARK: T4 : valeur actuelle

    private func snapshot(cpu: Double = 0.2, gpu: Double? = nil, used: UInt64 = 500, total: UInt64 = 1_000, battery: Double? = nil) -> SystemSnapshot {
        SystemSnapshot(
            date: Date(), cpu: CPUStats(user: cpu, system: 0),
            memory: MemoryStats(total: 16, app: 8, wired: 2, compressed: 1, cached: 0, swapUsed: 0, pressure: .normal),
            disk: DiskStats(total: total, available: total > used ? total - used : 0), thermalState: .nominal, uptime: 1,
            gpu: gpu.map { GPUStats(utilization: $0, memoryUsed: 0) },
            battery: battery.map {
                BatteryStats(percent: $0, isCharging: false, isPluggedIn: false, isFullyCharged: false, minutesRemaining: nil,
                             cycleCount: 1, health: nil, designCapacity: nil, maxCapacity: nil, temperature: nil,
                             batteryPower: nil, systemPower: nil, adapterWatts: nil)
            })
    }

    @Test func theLoadGroupShowsTheLargerOfTheCPUAndTheGPULoad() {
        #expect(ThresholdLiveValues(snapshot: snapshot(cpu: 0.36, gpu: 0.22)).load == 36)
        #expect(ThresholdLiveValues(snapshot: snapshot(cpu: 0.10, gpu: 0.82)).load == 82)
        #expect(ThresholdLiveValues(snapshot: snapshot(cpu: 0.40, gpu: nil)).load == 40)    // pas de GPU mesuré : le processeur seul
    }

    @Test func theDiskGroupShowsThePercentUsedAndTheBatteryGroupTheLevel() {
        let live = ThresholdLiveValues(snapshot: snapshot(used: 830, total: 1_000, battery: 67))
        #expect(live.disk == 83)
        #expect(live.battery == 67)
    }

    @Test func unknownValuesAreNil() {
        #expect(ThresholdLiveValues(snapshot: nil) == ThresholdLiveValues(load: nil, disk: nil, battery: nil))
        #expect(ThresholdLiveValues(snapshot: snapshot(battery: nil)).battery == nil)       // Mac sans batterie
        #expect(ThresholdLiveValues(snapshot: snapshot(total: 0)).disk == nil)               // taille du disque inconnue
        #expect(ThresholdLiveValues(snapshot: snapshot(battery: .nan)).battery == nil)
    }

    @Test func liveValuesAreClampedToTheTrack() {
        #expect(ThresholdLiveValues(snapshot: snapshot(battery: 140)).battery == 100)
        #expect(ThresholdLiveValues(snapshot: snapshot(battery: -3)).battery == 0)
    }

    @Test func demoModeUsesTheDemoSnapshot() throws {
        let live = ThresholdLiveValues(snapshot: DemoData.snapshot())
        let load = try #require(live.load), disk = try #require(live.disk), battery = try #require(live.battery)
        #expect(abs(load - 36) < 0.001)        // CPU 27 % + 9 %, plus grand que le GPU (22 %)
        #expect(abs(disk - 83) < 1)
        #expect(battery == 67)
    }

    @Test func theMarkerPositionIsTheValueOverOneHundred() {
        #expect(Logic.fraction(ofPercent: 36) == 0.36)
        #expect(Logic.fraction(ofPercent: -5) == 0)
        #expect(Logic.fraction(ofPercent: 250) == 1)
    }

    // MARK: Accessibilité : style

    @Test func theNormalBandIsOpaqueWithReduceTransparencyOrIncreasedContrast() {
        #expect(ThresholdTrackStyle.normalBandOpacity(reduceTransparency: false, increasedContrast: false) == 0.55)
        #expect(ThresholdTrackStyle.normalBandOpacity(reduceTransparency: true, increasedContrast: false) == 1)
        #expect(ThresholdTrackStyle.normalBandOpacity(reduceTransparency: false, increasedContrast: true) == 1)
    }

    @Test func increasedContrastAddsOutlines() {
        #expect(ThresholdTrackStyle.outlineWidth(increasedContrast: false) == 0)
        #expect(ThresholdTrackStyle.outlineWidth(increasedContrast: true) > 0)
        #expect(ThresholdTrackStyle.ringWidth(increasedContrast: true) >= ThresholdTrackStyle.ringWidth(increasedContrast: false))
    }

    @Test func everyHandleHasAHitAreaOfAtLeast24Points() {
        #expect(ThresholdTrackMetrics.hitSize >= 24)
        #expect(ThresholdTrackMetrics.handleSize <= ThresholdTrackMetrics.hitSize)
    }
}
