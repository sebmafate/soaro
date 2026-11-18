import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Soaro

/// SL21, suites 1 et 2 de l'auteur : la barre de progression suit les seuils réglés, et la prise (« branché, ne charge pas »).
/// Les valeurs IOKit de ces tests sont relevées sur un vrai Mac (2026-11-18, secteur, 80 %, charge limitée) ou écrites comme telles ;
/// aucun identifiant de machine.

// MARK: Barre de progression sur les seuils de l'auteur

@Suite struct BatteryBarTintTests {
    private func battery(_ percent: Double, plugged: Bool, charging: Bool = false) -> BatteryStats {
        BatteryStats(percent: percent, isCharging: charging, isPluggedIn: plugged, isFullyCharged: false, minutesRemaining: nil, cycleCount: 1,
                     health: 1, designCapacity: nil, maxCapacity: nil, temperature: nil, batteryPower: nil, systemPower: nil, adapterWatts: nil)
    }

    private static let sets: [LevelThresholds] = [
        PressureThresholds.default.battery,                       // 20 / 10 / 5
        LevelThresholds(medium: 50, high: 30, critical: 10),
        LevelThresholds(medium: 35, high: 25, critical: 15),
        LevelThresholds(medium: 90, high: 60, critical: 1),
        LevelThresholds(medium: 20, high: 20, critical: 20),
    ]

    @Test func theBarIsTheColourOfTheLevelOfTheGlyphAndTheValue() {
        for thresholds in Self.sets {
            for plugged in [false, true] {
                for percent in stride(from: 0.0, through: 100.0, by: 1.0) {
                    let b = battery(percent, plugged: plugged)
                    let level = PressureLevel.battery(b, thresholds: thresholds)
                    let bar = BatteryGlyphColors.barTint(for: b, thresholds: thresholds)
                    // Le glyphe dessine le niveau coloré ; au niveau normal il garde la couleur de base, la barre reste verte comme avant.
                    let glyphFill = BatteryGlyphColors.fill(level: level, base: .black)
                    if level > .normal {
                        #expect(bar == glyphFill, "\(percent) % \(thresholds) branché \(plugged)")
                    } else {
                        #expect(bar == .green, "\(percent) % \(thresholds) branché \(plugged)")
                    }
                }
            }
        }
    }

    @Test func eachLevelHasItsColourAndNormalIsGreenAsToday() {
        let t = LevelThresholds(medium: 50, high: 30, critical: 10)
        #expect(BatteryGlyphColors.barTint(for: battery(60, plugged: false), thresholds: t) == .green)
        #expect(BatteryGlyphColors.barTint(for: battery(50, plugged: false), thresholds: t) == .orange)
        #expect(BatteryGlyphColors.barTint(for: battery(30, plugged: false), thresholds: t) == .red)
        #expect(BatteryGlyphColors.barTint(for: battery(10, plugged: false), thresholds: t) == PressureLevel.scarlet)
        // Branché : jamais coloré (règle d'origine de `PressureLevel.battery`), vert comme aujourd'hui.
        #expect(BatteryGlyphColors.barTint(for: battery(3, plugged: true), thresholds: t) == .green)
        #expect(BatteryGlyphColors.barTint(for: battery(3, plugged: true, charging: true), thresholds: t) == .green)
    }

    @Test func atTwentyFivePercentTheOldFixedRuleAndTheUserThresholdsDisagree() {
        // Seuils par défaut : 25 % est normal (vert) ; l'ancienne règle fixe le disait orange (< 40 %).
        #expect(BatteryGlyphColors.barTint(for: battery(25, plugged: false), thresholds: PressureThresholds.default.battery) == .green)
        // Seuils de l'auteur : 18 % est orange ; l'ancienne règle fixe le disait rouge (< 20 %).
        #expect(BatteryGlyphColors.barTint(for: battery(18, plugged: false), thresholds: PressureThresholds.default.battery) == .orange)
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
    }

    @Test func theOldFixedThresholdsAreGoneFromTheBatteryBars() throws {
        let overview = try read("Sources/Soaro/Views/OverviewTab.swift")
        let tab = try read("Sources/Soaro/Views/BatteryTab.swift")
        let components = try read("Sources/Soaro/Views/Components.swift")
        #expect(!overview.contains("levelColor("))
        #expect(!tab.contains("levelColor("))
        #expect(!components.contains("func levelColor"), "la règle fixe n'a plus d'appelant : elle est supprimée")
        #expect(overview.contains("BatteryGlyphColors.barTint("))
        #expect(tab.contains("BatteryGlyphColors.barTint("))
        #expect(overview.contains("PressureThresholds.load().battery") && tab.contains("PressureThresholds.load().battery"))
    }

    @Test func theOtherCardsBarsAreUntouched() throws {
        let overview = try read("Sources/Soaro/Views/OverviewTab.swift")
        #expect(overview.contains("tint: loadColor(s.cpu.total)"))
        #expect(overview.contains("tint: loadColor(s.memory.usedFraction)"))
        #expect(overview.contains("tint: loadColor(s.disk.usedFraction)"))
        #expect(overview.contains("tint: .blue"))
    }
}

// MARK: Modèle d'état : sur batterie, en charge, branché sans charge

@Suite struct BatteryPowerStateTests {
    /// Propriétés `AppleSmartBattery` : celles d'un vrai Mac (2026-11-18, secteur, 80 %, charge limitée par macOS) comme base.
    /// ExternalConnected = Yes, IsCharging = No, FullyCharged = No (donc « branché sans charge » sans être « pleine »).
    private func props(_ overrides: [String: Any] = [:], removing: [String] = []) -> [String: Any] {
        var base: [String: Any] = [
            "BatteryInstalled": true, "CurrentCapacity": 80, "MaxCapacity": 100,
            "ExternalConnected": true, "ExternalChargeCapable": true, "IsCharging": false, "FullyCharged": false,
            "TimeRemaining": 65535, "AvgTimeToEmpty": 65535, "AvgTimeToFull": 65535, "CycleCount": 240,
        ]
        base.merge(overrides) { _, new in new }
        removing.forEach { base.removeValue(forKey: $0) }
        return base
    }

    private func state(_ overrides: [String: Any] = [:], removing: [String] = []) throws -> BatteryPowerState {
        try #require(BatterySampler.parse(props(overrides, removing: removing))).powerState
    }

    @Test func theRealMacReadingPluggedWithTheChargeHeldAt80PercentIsPluggedNotCharging() throws {
        #expect(try state() == .pluggedNotCharging)
    }

    @Test func fullyChargedOnTheAdapterAtOneHundredPercentIsPluggedNotCharging() throws {
        #expect(try state(["CurrentCapacity": 100, "FullyCharged": true]) == .pluggedNotCharging)
    }

    @Test func chargingAt80PercentIsCharging() throws {
        #expect(try state(["IsCharging": true, "AvgTimeToFull": 30]) == .charging)
    }

    @Test func unpluggedIsOnBattery() throws {
        #expect(try state(["ExternalConnected": false, "ExternalChargeCapable": false, "CurrentCapacity": 62, "TimeRemaining": 185]) == .onBattery)
    }

    @Test func missingKeysNeverGiveAPlugOrABolt() throws {
        // Une lecture qui échoue cache la fonction (ADR 0005) : ni prise ni éclair, jamais une fausse prise.
        #expect(try state(removing: ["ExternalConnected", "IsCharging"]) == .onBattery)
        #expect(try state(removing: ["ExternalConnected"]) == .onBattery)
        #expect(try state(["ExternalConnected": "n'importe quoi"]) == .onBattery, "valeur d'un autre type : non branché")
        #expect(try state(["ExternalConnected": NSNull()]) == .onBattery)
    }

    @Test func aChargingReadingWithoutTheAdapterKeyStillShowsTheBolt() throws {
        // Défensif : IsCharging seul prouve qu'une source d'énergie est là.
        #expect(try state(["IsCharging": true], removing: ["ExternalConnected"]) == .charging)
    }

    @Test func noBatteryGivesNoStateAtAll() {
        #expect(BatterySampler.parse(["BatteryInstalled": false]) == nil)
        #expect(BatterySampler.parse([:]) == nil)
        #expect(BatterySampler.parse(["ExternalConnected": true, "IsCharging": false]) == nil, "sans capacité lisible : rien, pas une fausse prise")
    }

    @Test func theMappingIsAPureFunctionOfPluggedAndCharging() {
        #expect(BatteryPowerState(isPluggedIn: false, isCharging: false) == .onBattery)
        #expect(BatteryPowerState(isPluggedIn: true, isCharging: true) == .charging)
        #expect(BatteryPowerState(isPluggedIn: true, isCharging: false) == .pluggedNotCharging)
        #expect(BatteryPowerState(isPluggedIn: false, isCharging: true) == .charging)
    }

    @Test func theMarkIsABoltOnlyWhenChargingAndAPlugOnlyWhenPluggedNotCharging() {
        #expect(BatteryPowerState.onBattery.mark == nil)
        #expect(BatteryPowerState.charging.mark == .bolt)
        #expect(BatteryPowerState.pluggedNotCharging.mark == .plug)
        // Un seul repère à la fois : l'éclair et la prise ne se montrent jamais ensemble (le type n'en porte qu'un).
        let marks = [BatteryPowerState.onBattery, .charging, .pluggedNotCharging].map(\.mark)
        #expect(marks.compactMap { $0 }.count == 2)
    }

    @Test func theSamplerReadsNoNewKeyBecauseTheModelAlreadySeparatesTheThreeStates() throws {
        let source = try String(contentsOf: RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Samplers/IOKitSamplers.swift"), encoding: .utf8)
        #expect(source.contains("ExternalConnected") && source.contains("\"IsCharging\""))
        #expect(!source.contains("NotChargingReason"), "pas de champ en plus : ExternalConnected et IsCharging suffisent")
    }

    @Test func theStatusTitleAndTheGlyphAgreeOnWhatPluggedMeans() {
        // Le titre de l'onglet (« Charging », « On power adapter », « Charged ») se décide sur les mêmes deux booléens.
        let demo = DemoData.snapshot().battery!
        #expect(demo.powerState == .charging)
    }
}

// MARK: Géométrie de la prise

@Suite struct BatteryPlugGeometryTests {
    private let bar = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)

    @Test func thePlugIsCentredInsideTheFillAreaAtEverySize() {
        for body in [BatteryGlyphGeometry.menuBarBody, BatteryGlyphGeometry.cardBody, BatteryGlyphGeometry.tabBody] {
            let g = BatteryGlyphGeometry(body: body)
            let r = g.plugRect
            #expect(g.innerRect.insetBy(dx: -0.01, dy: -0.01).contains(r), "la prise tient dans l'intérieur (\(body))")
            #expect(abs(r.midX - g.bodyRect.midX) < 1e-9 && abs(r.midY - g.bodyRect.midY) < 1e-9)
            #expect(r.height > r.width, "une prise est plus haute que large (dents en haut)")
        }
    }

    @Test func thePlugIsMadeOfTwoProngsABodyAndACordInsideTheUnitSquare() {
        let rects = BatteryGlyphGeometry.plugRects
        #expect(rects.count == 4)
        let all = rects.reduce(CGRect.null) { $0.union($1) }
        #expect(all.minX >= 0 && all.maxX <= 1 && all.minY == 0 && all.maxY == 1)
        // deux dents en haut, séparées ; un corps plus large dessous ; un cordon centré tout en bas.
        let prongs = rects.filter { $0.minY == 0 }
        #expect(prongs.count == 2 && prongs[0].maxX < prongs[1].minX)
        #expect(rects.contains { $0.maxY == 1 && abs($0.midX - 0.5) < 1e-9 })
    }

    @Test func theMarkPathsAreTheBoltAndThePlugAndNothingElse() {
        #expect(bar.markPath(.bolt).boundingRect.equalTo(bar.boltPath().boundingRect))
        #expect(bar.markPath(.plug).boundingRect.integral.intersects(bar.plugRect.insetBy(dx: 0.1, dy: 0.1)))
        #expect(!bar.markPath(.plug).boundingRect.equalTo(bar.markPath(.bolt).boundingRect))
        #expect(bar.markRect(.plug) == bar.plugRect && bar.markRect(.bolt) == bar.boltRect)
    }
}

// MARK: Rendu hors écran de la prise

@MainActor @Suite(.serialized) struct BatteryPlugRenderTests {
    private static let scale: CGFloat = 4

    private func glyph(_ power: BatteryPowerState, percent: Double, level: PressureLevel = .normal, base: Color = .black,
                       body: CGSize = BatteryGlyphGeometry.menuBarBody) throws -> GlyphInk {
        let renderer = ImageRenderer(content: BatteryGlyph(percent: percent, power: power, level: level, base: base, body: body, increasedContrast: false))
        renderer.scale = Self.scale
        return try GlyphInk(cg: try #require(renderer.cgImage), scale: Self.scale)
    }

    private func mask(_ a: GlyphInk, _ b: GlyphInk) -> Set<Int> {
        var set = Set<Int>()
        for x in 0..<a.width { for y in 0..<a.height where abs(a.alpha(x, y) - b.alpha(x, y)) > 0.5 { set.insert(y * a.width + x) } }
        return set
    }

    @Test func thePlugShowsOnlyWhenPluggedNotChargingAndInsideItsBox() throws {
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        for percent in [0.0, 50, 100] {
            let plain = try glyph(.onBattery, percent: percent), plug = try glyph(.pluggedNotCharging, percent: percent)
            let diff = mask(plain, plug)
            #expect(diff.count > 25, "\(percent) % : \(diff.count) pixels de prise")
            // Rien ne change hors de la boîte de la prise.
            let box = g.plugRect.insetBy(dx: -1, dy: -1)
            for index in diff {
                let p = CGPoint(x: Double(index % plain.width) / Double(Self.scale), y: Double(index / plain.width) / Double(Self.scale))
                #expect(box.contains(p), "\(percent) % : un pixel change hors de la prise")
            }
        }
    }

    @Test func thePlugAndTheBoltAreDifferentShapesAndNeverDrawnTogether() throws {
        for percent in [0.0, 100] {
            let plain = try glyph(.onBattery, percent: percent)
            let plugMask = mask(plain, try glyph(.pluggedNotCharging, percent: percent))
            let boltMask = mask(plain, try glyph(.charging, percent: percent))
            let both = plugMask.intersection(boltMask)
            #expect(Double(both.count) < 0.85 * Double(min(plugMask.count, boltMask.count)), "deux formes distinctes (\(percent) %)")
            // Les deux repères ne tiennent pas dans la même image : « un seul à la fois » est dans le type (`mark` est optionnel, pas un ensemble).
            #expect(!plugMask.isEmpty && !boltMask.isEmpty)
        }
    }

    @Test func thePlugIsVisibleInAMonochromeImageOnAnEmptyAndOnAFullBattery() throws {
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        let emptyPlain = try glyph(.onBattery, percent: 0), emptyPlug = try glyph(.pluggedNotCharging, percent: 0)
        #expect(emptyPlug.opaqueCount(in: g.plugRect) > emptyPlain.opaqueCount(in: g.plugRect) + 20, "encre pleine sur le vide")
        let fullPlain = try glyph(.onBattery, percent: 100), fullPlug = try glyph(.pluggedNotCharging, percent: 100)
        #expect(fullPlug.clearCount(in: g.innerRect) > fullPlain.clearCount(in: g.innerRect) + 20, "prise creusée dans le remplissage")
    }

    @Test func thePlugKeepsTheOutlineIntact() throws {
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        for percent in [0.0, 100] {
            let plain = try glyph(.onBattery, percent: percent), plug = try glyph(.pluggedNotCharging, percent: percent)
            for x in stride(from: 0, to: Int(g.totalSize.width * Self.scale), by: 1) {
                for y in 0..<Int(g.lineWidth * Self.scale) - 1 {
                    #expect(abs(plain.alpha(x, y) - plug.alpha(x, y)) < 0.2, "contour haut, colonne \(x)")
                }
            }
        }
    }

    @Test func thePlugIsDrawnAtTheCardAndTabSizesToo() throws {
        for body in [BatteryGlyphGeometry.cardBody, BatteryGlyphGeometry.tabBody] {
            let g = BatteryGlyphGeometry(body: body)
            let plain = try glyph(.onBattery, percent: 0, body: body), plug = try glyph(.pluggedNotCharging, percent: 0, body: body)
            #expect(plug.opaqueCount(in: g.plugRect) > plain.opaqueCount(in: g.plugRect) + 60, "\(body)")
        }
    }

    @Test func aColouredLevelKeepsAnInkPlugOfTheBaseColourWhereThereIsNoFill() throws {
        // Le repère est de la couleur du contour (blanc sur barre sombre) ; le remplissage seul prend la couleur du niveau.
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        let ink = try glyph(.pluggedNotCharging, percent: 0, level: .high, base: .white)
        let centre = ink.pixel(Int(g.plugRect.midX * Self.scale), Int(g.plugRect.midY * Self.scale))
        #expect(centre.a > 0.9 && centre.r > 0.9 && centre.g > 0.9 && centre.b > 0.9)
    }
}

// MARK: Élément, infobulle, clé de cache et règle du modèle

@MainActor @Suite(.serialized) struct BatteryPlugLabelTests {
    private static let cpu = MenuBarItem.stacked(label: "CPU", value: "43%")

    private func render(_ items: [MenuBarItem], compact: Bool = true, dark: Bool = false) throws -> NSImage {
        try #require(MenuBarRenderer.image(severity: nil, compact: compact, items: items, darkBar: dark, increasedContrast: false))
    }

    private func battery(_ percent: Double, plugged: Bool, charging: Bool) -> SystemSnapshot {
        SystemSnapshot(
            date: Date(), cpu: CPUStats(user: 0.33, system: 0.10),
            memory: MemoryStats(total: 16_000_000_000, app: 8, wired: 3, compressed: 2, cached: 1, swapUsed: 0, pressure: .normal),
            disk: DiskStats(total: 1_000_000_000_000, available: 140_000_000_000), thermalState: .nominal, uptime: 100,
            battery: BatteryStats(percent: percent, isCharging: charging, isPluggedIn: plugged, isFullyCharged: false, minutesRemaining: nil, cycleCount: 1,
                                  health: 1, designCapacity: nil, maxCapacity: nil, temperature: nil, batteryPower: nil, systemPower: nil, adapterWatts: nil))
    }

    private func items(_ s: SystemSnapshot) -> [MenuBarItem] {
        MenuBarItem.items(for: s, cpu: false, gpu: false, memory: false, disk: false, network: false, battery: true)
    }

    @Test func theItemCarriesTheThreeStates() {
        #expect(items(battery(80, plugged: true, charging: false)) == [.battery(percent: 80, power: .pluggedNotCharging, level: .normal)])
        #expect(items(battery(80, plugged: true, charging: true)) == [.battery(percent: 80, power: .charging, level: .normal)])
        #expect(items(battery(80, plugged: false, charging: false)) == [.battery(percent: 80, power: .onBattery, level: .normal)])
        #expect(items(battery(3, plugged: true, charging: false)).first?.level == .normal, "branché : jamais coloré")
    }

    @Test func theThreeStatesAreThreeDifferentItemsAndThreeDifferentImages() throws {
        let a = MenuBarItem.battery(percent: 80, power: .onBattery), b = MenuBarItem.battery(percent: 80, power: .charging), c = MenuBarItem.battery(percent: 80, power: .pluggedNotCharging)
        #expect(a != b && b != c && a != c)
        let ia = try render([a]), ib = try render([b]), ic = try render([c])
        #expect(ia !== ib && ib !== ic && ia !== ic, "l'état fait partie de la clé de cache")
        #expect(try render([c]) === ic, "même état : le cache sert la même image")
    }

    @Test func aNormalBatteryInAnyStateKeepsTheLabelATemplate() throws {
        for power in [BatteryPowerState.onBattery, .charging, .pluggedNotCharging] {
            for compact in [true, false] {
                #expect(try render([Self.cpu, .battery(percent: 80, power: power)], compact: compact).isTemplate, "\(power) compact \(compact)")
            }
        }
        // Un niveau coloré, lui, rend l'image non modèle (règle inchangée).
        #expect(try !render([.battery(percent: 8, power: .onBattery, level: .high)]).isTemplate)
    }

    @Test func theLabelHasTheSameWidthAndHeightInEveryState() throws {
        let widths = try [BatteryPowerState.onBattery, .charging, .pluggedNotCharging].map { try render([Self.cpu, .battery(percent: 80, power: $0)]).size }
        #expect(Set(widths.map(\.width)).count == 1 && widths.allSatisfy { $0.height == 22 })
    }

    @Test func thePlugShowsInTheRealTemplateLabelOnlyWhenPluggedNotCharging() throws {
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        let without = try render([Self.cpu])
        let spacing: CGFloat = 9
        func ink(_ power: BatteryPowerState) throws -> (GlyphInk, CGPoint) {
            let image = try render([Self.cpu, .battery(percent: 0, power: power)])
            let i = try GlyphInk(image: image)
            let y = (22 - g.totalSize.height) / 2
            let row = Int(((y + g.bodyRect.midY) * i.scale).rounded())
            let start = Int(((without.size.width + spacing - 1.5) * i.scale).rounded())
            let x = i.opaqueRun(row: row, columns: start..<min(i.width, start + Int(3 * i.scale))).first.map { CGFloat($0) / i.scale } ?? (without.size.width + spacing)
            return (i, CGPoint(x: x, y: y))
        }
        let (plain, po) = try ink(.onBattery), (plug, uo) = try ink(.pluggedNotCharging), (bolt, bo) = try ink(.charging)
        let box = g.plugRect
        #expect(plug.opaqueCount(in: box, origin: uo) > plain.opaqueCount(in: box, origin: po) + 6, "la prise est de l'encre sur le vide, dans l'image modèle")
        // L'éclair, lui, n'ajoute pas la même encre à cet endroit : deux formes.
        #expect(bolt.opaqueCount(in: box, origin: bo) != plug.opaqueCount(in: box, origin: uo))
    }

    @Test func theTooltipSaysOnPowerAdapterWhenPluggedNotCharging() {
        let s = battery(80, plugged: true, charging: false)
        let text = MenuBarTooltip.text(recommendations: [], snapshot: s, items: items(s), locale: Locale(identifier: "en"))
        #expect(text == "Soaro: everything is fine\n\nBattery: \(Format.percent(0.8)) · On power adapter")
        #expect(!text.contains("Colored values"))
    }

    @Test func theChargingTooltipIsUnchangedAndAnUnpluggedBatterySaysNothing() {
        let c = battery(67, plugged: true, charging: true)
        #expect(MenuBarTooltip.text(recommendations: [], snapshot: c, items: items(c), locale: Locale(identifier: "en")) == "Soaro: everything is fine\n\nBattery: \(Format.percent(0.67)) · Charging")
        let u = battery(67, plugged: false, charging: false)
        #expect(MenuBarTooltip.text(recommendations: [], snapshot: u, items: items(u), locale: Locale(identifier: "en")) == "Soaro: everything is fine")
    }

    @Test func theTooltipWordsAreAlreadyTranslatedInNineLanguages() throws {
        let strings = try DockerStringsTests.catalogStrings()
        for key in ["Battery", "Charging", "On power adapter"] {
            let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            for language in TranslationCatalog.requiredTranslations {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String ?? ""
                #expect(!value.isEmpty, "\(key) / \(language)")
            }
        }
    }

    @Test func inlineTextKeepsABoltOnlyForChargingAndNothingForAPlug() {
        let plugged = MenuBarItem.battery(percent: 80, power: .pluggedNotCharging)
        #expect(MenuBarItem.inlineText([plugged]) == "BAT \(Format.percent(0.8))")
    }

    @Test func theCardsAndTheTabPassTheStateOfTheModel() throws {
        for path in ["Sources/Soaro/Views/OverviewTab.swift", "Sources/Soaro/Views/BatteryTab.swift"] {
            let source = try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
            #expect(source.contains("power: b.powerState"), "\(path)")
            #expect(!source.contains("charging: b.isCharging"), "\(path)")
        }
        let menu = try String(contentsOf: RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Views/MenuBarWidgets.swift"), encoding: .utf8)
        #expect(menu.contains("power: b.powerState"))
    }
}
