import Foundation
import Testing
@testable import Soaro

/// SL17 : la logique PURE de la piste à trois poignées des seuils de couleur (Réglages).
/// Les bornes, le pas de 5 et l'écart minimal de 5 sont ceux des anciens Steppers (test de parité),
/// le modèle `LevelThresholds` et sa persistance ne changent pas.
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

    /// Toutes les combinaisons valides sur la grille de 5 (écart ≥ 5) : le cas normal.
    static func gridStates(ascending: Bool) -> [LevelThresholds] {
        var states: [LevelThresholds] = []
        // Les anciens Steppers n'allaient pas au-delà de 95 pour l'orange de la batterie : ces états-là n'existaient pas.
        let grid = Array(stride(from: 5, through: ascending ? 100 : 95, by: 5))
        for a in grid { for b in grid where b >= a + 5 { for c in grid where c >= b + 5 {
            states.append(ascending ? LevelThresholds(medium: a, high: b, critical: c)
                                    : LevelThresholds(medium: c, high: b, critical: a))
        } } }
        return states
    }

    /// Combinaisons quelconques (valeurs de 1 à 100, pas sur la grille, écarts quelconques), générateur déterministe.
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

    // MARK: T1 : bornes

    @Test func theBoundsEqualTheOldStepperRangesOnEveryGridCombination() throws {
        for ascending in [true, false] {
            let states = Self.gridStates(ascending: ascending)
            #expect(states.count == (ascending ? 1_140 : 969))
            for t in states {
                let legacy = try #require(Self.legacyRanges(t, ascending: ascending), "\(t) devrait être valide")
                for handle in ThresholdHandle.allCases {
                    let range = Logic.bounds(for: handle, in: t, ascending: ascending)
                    let old = legacy[handle.rawValue]
                    let expected: ClosedRange<Int> = old.0...old.1
                    #expect(range == expected, "\(ascending) \(handle) \(t)")
                }
            }
        }
    }

    @Test func theBoundsEqualTheOldStepperRangesOnManyLooseCombinations() {
        var compared = 0
        for ascending in [true, false] {
            for t in Self.looseStates(ascending: ascending, count: 30_000) {
                guard let legacy = Self.legacyRanges(t, ascending: ascending) else { continue }   // plage invalide : l'ancien code plantait
                for handle in ThresholdHandle.allCases {
                    let range = Logic.bounds(for: handle, in: t, ascending: ascending)
                    let expected: ClosedRange<Int> = legacy[handle.rawValue].0...legacy[handle.rawValue].1
                    #expect(range == expected, "\(t)")
                    compared += 1
                }
            }
        }
        #expect(compared > 3_000, "trop peu de combinaisons valides comparées : \(compared)")
    }

    @Test func theBoundsOfTheDefaultsAreTheOnesTheSteppersHad() {
        let load = PressureThresholds.default.load        // 60 / 80 / 95
        #expect(Logic.bounds(for: .orange, in: load, ascending: true) == 5...75)
        #expect(Logic.bounds(for: .red, in: load, ascending: true) == 65...90)
        #expect(Logic.bounds(for: .scarlet, in: load, ascending: true) == 85...100)
        let battery = PressureThresholds.default.battery  // 20 / 10 / 5
        #expect(Logic.bounds(for: .orange, in: battery, ascending: false) == 15...95)
        #expect(Logic.bounds(for: .red, in: battery, ascending: false) == 10...15)
        #expect(Logic.bounds(for: .scarlet, in: battery, ascending: false) == 5...5)
    }

    @Test func theStepAndTheGapAreFive() {
        #expect(Logic.step == 5)
        #expect(Logic.minimumGap == 5)
    }

    @Test func anInvalidStateNeverCrashesAndGivesANonEmptyRange() {
        // Préférences abîmées (valeurs égales, écarts de 1) : l'ancien `ClosedRange` aurait planté, la piste ne doit pas.
        let odd = [LevelThresholds(medium: 100, high: 100, critical: 100), LevelThresholds(medium: 1, high: 1, critical: 1),
                   LevelThresholds(medium: 60, high: 62, critical: 63), LevelThresholds(medium: 50, high: 51, critical: 100)]
        for t in odd {
            for ascending in [true, false] {
                for handle in ThresholdHandle.allCases {
                    let range = Logic.bounds(for: handle, in: t, ascending: ascending)
                    #expect(range.lowerBound <= range.upperBound)
                    _ = Logic.snapped(42, for: handle, in: t, ascending: ascending)
                    _ = Logic.apply(.step(1), to: handle, in: t, ascending: ascending)
                }
            }
        }
    }

    // MARK: T1 : valeurs et ordre des poignées

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

    // MARK: T1 : aimantation, les poignées ne se croisent jamais

    @Test func snappingRoundsToTheNearestMultipleOfFive() {
        let t = PressureThresholds.default.load
        #expect(Logic.snapped(62.4, for: .orange, in: t, ascending: true) == 60)
        #expect(Logic.snapped(62.5, for: .orange, in: t, ascending: true) == 65)
        #expect(Logic.snapped(67.4, for: .orange, in: t, ascending: true) == 65)
        #expect(Logic.snapped(40, for: .orange, in: t, ascending: true) == 40)
    }

    @Test func snappingStopsAtTheNeighbours() {
        let load = PressureThresholds.default.load           // 60 / 80 / 95
        #expect(Logic.snapped(100, for: .orange, in: load, ascending: true) == 75)    // 80 - 5
        #expect(Logic.snapped(-30, for: .orange, in: load, ascending: true) == 5)
        #expect(Logic.snapped(0, for: .red, in: load, ascending: true) == 65)         // 60 + 5
        #expect(Logic.snapped(100, for: .red, in: load, ascending: true) == 90)       // 95 - 5
        #expect(Logic.snapped(10, for: .scarlet, in: load, ascending: true) == 85)
        #expect(Logic.snapped(500, for: .scarlet, in: load, ascending: true) == 100)
        let battery = PressureThresholds.default.battery     // 20 / 10 / 5
        #expect(Logic.snapped(100, for: .orange, in: battery, ascending: false) == 95)
        #expect(Logic.snapped(0, for: .orange, in: battery, ascending: false) == 15)  // 10 + 5
        #expect(Logic.snapped(100, for: .red, in: battery, ascending: false) == 15)   // 20 - 5
        #expect(Logic.snapped(0, for: .red, in: battery, ascending: false) == 10)     // 5 + 5
        #expect(Logic.snapped(60, for: .scarlet, in: battery, ascending: false) == 5) // 10 - 5, déjà au plus bas
    }

    @Test func whateverTheDragTheStateStaysValidAndInOrder() {
        for ascending in [true, false] {
            for t in Self.gridStates(ascending: ascending).enumerated().filter({ $0.offset % 7 == 0 }).map(\.element) {
                for handle in ThresholdHandle.allCases {
                    for raw in stride(from: -40.0, through: 140.0, by: 7.3) {
                        let value = Logic.snapped(raw, for: handle, in: t, ascending: ascending)
                        let moved = Logic.with(value, for: handle, in: t)
                        #expect(Self.legacyRanges(moved, ascending: ascending) != nil, "\(t) -> \(moved)")
                        #expect(Logic.isValid(moved, ascending: ascending), "\(t) -> \(moved)")
                        #expect(value % 5 == 0)
                    }
                }
            }
        }
    }

    @Test func aStateTheHandlesCanReachSurvivesTheSanitizingOfTheSavedPreferences() {
        // Aucune migration : ce que la piste produit est relu à l'identique par `PressureThresholds.load`.
        for ascending in [true, false] {
            for t in Self.gridStates(ascending: ascending) {
                #expect(t.sanitized(ascending: ascending) == t)
            }
        }
    }

    @Test func aValueSavedThroughTheTrackRoundTripsThroughThePreferences() throws {
        let suite = "soaro.sl17.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var all = PressureThresholds.default
        all.load = Logic.with(Logic.snapped(70, for: .orange, in: all.load, ascending: true), for: .orange, in: all.load)
        all.battery = Logic.with(Logic.snapped(30, for: .orange, in: all.battery, ascending: false), for: .orange, in: all.battery)
        all.save(to: defaults)
        #expect(PressureThresholds.load(from: defaults) == all)
        #expect(all.load == LevelThresholds(medium: 70, high: 80, critical: 95))
        #expect(all.battery == LevelThresholds(medium: 30, high: 10, critical: 5))
    }

    @Test func isValidRequiresTheOrderAndTheGapOfFive() {
        #expect(Logic.isValid(LevelThresholds(medium: 60, high: 80, critical: 95), ascending: true))
        #expect(Logic.isValid(LevelThresholds(medium: 60, high: 65, critical: 70), ascending: true))
        #expect(!Logic.isValid(LevelThresholds(medium: 60, high: 64, critical: 95), ascending: true))
        #expect(!Logic.isValid(LevelThresholds(medium: 80, high: 60, critical: 95), ascending: true))
        #expect(Logic.isValid(LevelThresholds(medium: 20, high: 10, critical: 5), ascending: false))
        #expect(!Logic.isValid(LevelThresholds(medium: 20, high: 10, critical: 8), ascending: false))
    }

    // MARK: T1 : glisser

    @Test func draggingMovesByTheTranslationAndSnaps() {
        let t = PressureThresholds.default.load           // 60 / 80 / 95
        // 3,2 pt par point : 16 pt = 5 points.
        #expect(Logic.draggedValue(from: 60, translation: 16, pointsPerUnit: 3.2, handle: .orange, in: t, ascending: true) == 65)
        #expect(Logic.draggedValue(from: 60, translation: -16, pointsPerUnit: 3.2, handle: .orange, in: t, ascending: true) == 55)
        #expect(Logic.draggedValue(from: 60, translation: 3, pointsPerUnit: 3.2, handle: .orange, in: t, ascending: true) == 60)  // moins d'un demi-pas
        #expect(Logic.draggedValue(from: 60, translation: 5_000, pointsPerUnit: 3.2, handle: .orange, in: t, ascending: true) == 75)
        #expect(Logic.draggedValue(from: 60, translation: -5_000, pointsPerUnit: 3.2, handle: .orange, in: t, ascending: true) == 5)
        // Largeur nulle ou négative : pas de division par zéro, la valeur ne bouge pas.
        #expect(Logic.draggedValue(from: 60, translation: 40, pointsPerUnit: 0, handle: .orange, in: t, ascending: true) == 60)
    }

    @Test func draggingTheBatteryHandlesFollowsThePointerNotTheDirectionOfTheScale() {
        let t = PressureThresholds.default.battery       // 20 / 10 / 5 : l'écarlate est à gauche, l'orange à droite
        #expect(Logic.draggedValue(from: 20, translation: 32, pointsPerUnit: 3.2, handle: .orange, in: t, ascending: false) == 30)
        #expect(Logic.draggedValue(from: 20, translation: -32, pointsPerUnit: 3.2, handle: .orange, in: t, ascending: false) == 15)
    }

    // MARK: T1 : clavier et VoiceOver

    @Test func stepCommandsMoveByFivePerStepAndStayInTheBounds() {
        let t = PressureThresholds.default.load
        #expect(Logic.apply(.step(1), to: .orange, in: t, ascending: true) == LevelThresholds(medium: 65, high: 80, critical: 95))
        #expect(Logic.apply(.step(-1), to: .orange, in: t, ascending: true) == LevelThresholds(medium: 55, high: 80, critical: 95))
        #expect(Logic.apply(.step(2), to: .orange, in: t, ascending: true) == LevelThresholds(medium: 70, high: 80, critical: 95))
        #expect(Logic.apply(.step(-2), to: .red, in: t, ascending: true) == LevelThresholds(medium: 60, high: 70, critical: 95))
        // Contre un voisin : ne bouge plus.
        let tight = LevelThresholds(medium: 60, high: 65, critical: 70)
        #expect(Logic.apply(.step(1), to: .orange, in: tight, ascending: true) == tight)
        #expect(Logic.apply(.step(-1), to: .red, in: tight, ascending: true) == tight)
        #expect(Logic.apply(.step(1), to: .red, in: tight, ascending: true) == tight)
        // Plus 5 de plus que la borne : s'arrête à la borne (Maj + flèche, 10 points).
        let nearEdge = LevelThresholds(medium: 60, high: 80, critical: 95)
        #expect(Logic.apply(.step(2), to: .red, in: nearEdge, ascending: true) == LevelThresholds(medium: 60, high: 90, critical: 95))
    }

    @Test func homeAndEndJumpToTheBounds() {
        let t = PressureThresholds.default.load
        #expect(Logic.apply(.lowest, to: .orange, in: t, ascending: true) == LevelThresholds(medium: 5, high: 80, critical: 95))
        #expect(Logic.apply(.highest, to: .orange, in: t, ascending: true) == LevelThresholds(medium: 75, high: 80, critical: 95))
        #expect(Logic.apply(.lowest, to: .red, in: t, ascending: true) == LevelThresholds(medium: 60, high: 65, critical: 95))
        #expect(Logic.apply(.highest, to: .scarlet, in: t, ascending: true) == LevelThresholds(medium: 60, high: 80, critical: 100))
        let battery = PressureThresholds.default.battery
        #expect(Logic.apply(.highest, to: .orange, in: battery, ascending: false) == LevelThresholds(medium: 95, high: 10, critical: 5))
        #expect(Logic.apply(.lowest, to: .orange, in: battery, ascending: false) == LevelThresholds(medium: 15, high: 10, critical: 5))
    }

    @Test func keysMapToCommands() {
        #expect(Logic.command(for: .right, shift: false) == .step(1))
        #expect(Logic.command(for: .up, shift: false) == .step(1))
        #expect(Logic.command(for: .left, shift: false) == .step(-1))
        #expect(Logic.command(for: .down, shift: false) == .step(-1))
        #expect(Logic.command(for: .right, shift: true) == .step(2))        // Maj : 10 points
        #expect(Logic.command(for: .left, shift: true) == .step(-2))
        #expect(Logic.command(for: .home, shift: false) == .lowest)
        #expect(Logic.command(for: .end, shift: false) == .highest)
        #expect(Logic.command(for: .home, shift: true) == .lowest)
    }

    @Test func theArrowsDoNotFlipForTheDescendingGroup() {
        // Pour la batterie aussi, flèche droite = valeur plus grande (la piste va de 0 à 100 de gauche à droite).
        let t = PressureThresholds.default.battery
        let up = Logic.apply(Logic.command(for: .right, shift: false), to: .orange, in: t, ascending: false)
        #expect(up.medium == 25)
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
            for t in Self.gridStates(ascending: ascending) + Self.looseStates(ascending: ascending, count: 500) {
                let segments = Logic.segments(for: t, ascending: ascending)
                #expect(segments.count == 4)
                #expect(segments.first?.from == 0 && segments.last?.to == 100)
                for (a, b) in zip(segments, segments.dropFirst()) { #expect(a.to == b.from) }
                for s in segments { #expect(s.from <= s.to) }
            }
        }
    }

    // MARK: T3 : étiquettes

    /// Position horizontale (en points) d'une valeur, avec `pointsPerUnit` points par pour cent.
    private func x(_ value: Int, _ ppu: Double) -> Double { Double(value) * ppu }

    @Test func aGapOfFiveRaisesTheMiddleLabelOnATrackOfAboutFourHundredPoints() {
        let ppu = 4.0       // piste d'environ 400 pt : 9 points d'écart = 36 pt, la largeur d'une étiquette et de son espace
        let close = Logic.labelPlacements(for: LevelThresholds(medium: 60, high: 65, critical: 95), pointsPerUnit: ppu)
        #expect(close[.red]?.raised == true)
        #expect(close[.orange]?.raised == false && close[.scarlet]?.raised == false)
        let far = Logic.labelPlacements(for: LevelThresholds(medium: 60, high: 80, critical: 95), pointsPerUnit: ppu)
        #expect(far.values.allSatisfy { !$0.raised })
        let closeAbove = Logic.labelPlacements(for: LevelThresholds(medium: 20, high: 70, critical: 75), pointsPerUnit: ppu)
        #expect(closeAbove[.red]?.raised == true)
    }

    @Test func theRuleIsAboutPointsOnTheScreenSoANarrowTrackRaisesEarlier() {
        let t = LevelThresholds(medium: 60, high: 70, critical: 95)     // écart de 10
        #expect(Logic.labelPlacements(for: t, pointsPerUnit: 4.0)[.red]?.raised == false)
        #expect(Logic.labelPlacements(for: t, pointsPerUnit: 3.0)[.red]?.raised == true)
    }

    @Test func onlyTheMiddleHandleIsEverRaised() {
        for t in Self.gridStates(ascending: true) {
            let placements = Logic.labelPlacements(for: t, pointsPerUnit: 3.0)
            #expect(placements[.orange]?.raised == false)
            #expect(placements[.scarlet]?.raised == false)
        }
    }

    @Test func labelsNeverOverlapAndTheStemStaysClearOnEveryValidStateAtEveryWidth() {
        let width = ThresholdTrackMetrics.labelWidth
        for ppu in [2.6, 3.0, 3.4, 4.0, 5.0] {
            for ascending in [true, false] {
                for t in Self.gridStates(ascending: ascending) {
                    let placements = Logic.labelPlacements(for: t, pointsPerUnit: ppu)
                    let red = Double(t.high) * ppu
                    // Les étiquettes de la première rangée : intervalles [centre ± largeur/2].
                    var row: [(handle: ThresholdHandle, lo: Double, hi: Double)] = []
                    for handle in ThresholdHandle.allCases {
                        guard let p = placements[handle], !p.raised else { continue }
                        let centre = Double(Logic.value(of: handle, in: t)) * ppu + p.shift
                        row.append((handle, centre - width / 2, centre + width / 2))
                    }
                    let sorted = row.sorted { $0.lo < $1.lo }
                    for (a, b) in zip(sorted, sorted.dropFirst()) {
                        #expect(b.lo - a.hi >= 2 - 1e-9, "étiquettes qui se touchent : \(t), \(ppu) pt par point")
                    }
                    if placements[.red]?.raised == true {
                        for item in sorted {
                            #expect(red < item.lo - 1 + 1e-9 || red > item.hi + 1 - 1e-9, "la tige traverse une étiquette : \(t), \(ppu)")
                        }
                    }
                }
            }
        }
    }

    @Test func aLabelStaysAboveItsOwnHandleToWithinAFewPoints() {
        // Le décalage reste petit : l'étiquette est toujours lisiblement au-dessus de sa poignée (poignée de 20 pt).
        for t in Self.gridStates(ascending: true) {
            for (_, placement) in Logic.labelPlacements(for: t, pointsPerUnit: 3.0) {
                #expect(abs(placement.shift) <= 10)
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

    @Test func theTrackFitsTheNarrowestWidthWhereSettingsAppear() {
        // Les réglages du panneau (430 pt) laissent au moins `narrowestContentWidth` à la piste (mesuré par le rendu hors écran).
        let ppu = ThresholdTrackMetrics.pointsPerUnit(forWidth: ThresholdTrackMetrics.narrowestContentWidth)
        #expect(ppu > 2.5)
        // Au plus étroit, un écart de 5 lève l'étiquette du milieu et un écart de 20 ne la lève pas.
        #expect(Logic.labelPlacements(for: LevelThresholds(medium: 60, high: 65, critical: 95), pointsPerUnit: ppu)[.red]?.raised == true)
        #expect(Logic.labelPlacements(for: LevelThresholds(medium: 60, high: 80, critical: 95), pointsPerUnit: ppu)[.red]?.raised == false)
        #expect(ThresholdTrackMetrics.pointsPerUnit(forWidth: 0) == 0)
        #expect(ThresholdTrackMetrics.pointsPerUnit(forWidth: 10) == 0)      // plus étroit que les marges
    }
}
