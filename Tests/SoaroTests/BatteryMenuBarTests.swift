import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Soaro

/// SL21 : l'icône de batterie dans le libellé de la barre de menus (élément, infobulle, image modèle, mise en page).

// MARK: Élément de la barre de menus

@Suite struct BatteryMenuBarItemTests {
    private func snapshot(battery: BatteryStats?) -> SystemSnapshot {
        SystemSnapshot(
            date: Date(), cpu: CPUStats(user: 0.33, system: 0.10),
            memory: MemoryStats(total: 16_000_000_000, app: 8, wired: 3, compressed: 2, cached: 1, swapUsed: 0, pressure: .normal),
            disk: DiskStats(total: 1_000_000_000_000, available: 140_000_000_000), thermalState: .nominal, uptime: 100,
            battery: battery
        )
    }

    private func battery(_ percent: Double, charging: Bool = false, plugged: Bool = false) -> BatteryStats {
        BatteryStats(percent: percent, isCharging: charging, isPluggedIn: plugged, isFullyCharged: false, minutesRemaining: nil, cycleCount: 1,
                     health: 1, designCapacity: nil, maxCapacity: nil, temperature: nil, batteryPower: nil, systemPower: nil, adapterWatts: nil)
    }

    private func items(_ b: BatteryStats?, thresholds: PressureThresholds = .default) -> [MenuBarItem] {
        MenuBarItem.items(for: snapshot(battery: b), cpu: false, gpu: false, memory: false, disk: false, network: false, battery: true, thresholds: thresholds)
    }

    @Test func theBatteryItemCarriesPercentChargingAndLevelWithoutALabel() {
        #expect(items(battery(67, charging: true, plugged: true)) == [.battery(percent: 67, power: .charging, level: .normal)])
        #expect(items(battery(67)) == [.battery(percent: 67, power: .onBattery, level: .normal)])
    }

    @Test func noBatteryGivesNoItemAndAnUnticketedBatteryGivesNoItemEither() {
        #expect(items(nil).isEmpty)
        let off = MenuBarItem.items(for: snapshot(battery: battery(50)), cpu: false, gpu: false, memory: false, disk: false, network: false, battery: false)
        #expect(off.isEmpty)
    }

    @Test func theLevelColoursAreUnchanged() {
        #expect(items(battery(50)).first?.level == .normal)
        #expect(items(battery(18)).first?.level == .medium)
        #expect(items(battery(9)).first?.level == .high)
        #expect(items(battery(4)).first?.level == .critical)
        // Sur secteur, un niveau bas n'est pas préoccupant (règle d'origine).
        #expect(items(battery(3, charging: true, plugged: true)).first?.level == .normal)
        #expect(items(battery(3, plugged: true)).first?.level == .normal)
        // Seuils réglables : ils sont respectés.
        let custom = PressureThresholds(load: PressureThresholds.default.load, disk: PressureThresholds.default.disk, battery: LevelThresholds(medium: 50, high: 30, critical: 10))
        #expect(items(battery(45), thresholds: custom).first?.level == .medium)
        #expect(items(battery(25), thresholds: custom).first?.level == .high)
        #expect(items(battery(10), thresholds: custom).first?.level == .critical)
    }

    @Test func thePercentIsRoundedToAWholeNumberAndClampedForTheGlyphAndTheText() {
        #expect(items(battery(66.6)).first == .battery(percent: 67, power: .onBattery, level: .normal))
        #expect(items(battery(0.2)).first == .battery(percent: 0, power: .onBattery, level: .critical))
        #expect(items(battery(100)).first == .battery(percent: 100, power: .onBattery, level: .normal))
        #expect(items(battery(140)).first == .battery(percent: 100, power: .onBattery, level: .normal))
        #expect(items(battery(-3)).first == .battery(percent: 0, power: .onBattery, level: .critical))
    }

    @Test func theItemIsNotAFlagAndAChargingDifferenceMakesItDifferent() {
        #expect(!MenuBarItem.battery(percent: 5, power: .charging).isFlag)
        #expect(MenuBarItem.battery(percent: 5, power: .charging) != .battery(percent: 5, power: .onBattery))
        #expect(MenuBarItem.battery(percent: 5, power: .onBattery) != .battery(percent: 6, power: .onBattery))
        #expect(MenuBarItem.battery(percent: 5, power: .onBattery) != .battery(percent: 5, power: .onBattery, level: .high))
        #expect(MenuBarItem.battery(percent: 5, power: .onBattery, level: .high).level == .high)
    }

    @Test func theBatteryStillComesLastAfterTheFlag() {
        let net = NetworkStats(downRate: 13_000, upRate: 99_000, localIP: nil, wifi: nil, latencyMs: nil)
        var s = snapshot(battery: battery(80))
        s.network = net
        let list = MenuBarItem.items(for: s, cpu: false, gpu: false, memory: false, disk: false, network: true, battery: true, publicIPCountryCode: "FR")
        #expect(list.last == .battery(percent: 80, power: .onBattery, level: .normal))
        #expect(list.contains(.flag(countryCode: "FR")))
    }

    // Texte sur une ligne : la forme « BAT 67% » reste, un « ⚡︎ » signale la charge.
    @Test func inlineTextKeepsTheBatForm() {
        let on = MenuBarItem.battery(percent: 67, power: .onBattery)
        #expect(MenuBarItem.inlineText([on]) == "BAT \(Format.percent(0.67))")
        let charging = MenuBarItem.battery(percent: 67, power: .charging)
        #expect(MenuBarItem.inlineText([.stacked(label: "CPU", value: "43%"), charging]) == "CPU 43% · BAT ⚡︎ \(Format.percent(0.67))")
    }

    // Infobulle : la charge se dit, et la phrase des valeurs colorées est celle d'avant.
    @Test func theTooltipSaysTheBatteryIsCharging() {
        let s = snapshot(battery: battery(67, charging: true, plugged: true))
        let text = MenuBarTooltip.text(recommendations: [], snapshot: s, items: [.battery(percent: 67, power: .charging)], locale: Locale(identifier: "en"))
        #expect(text == "Soaro: everything is fine\n\nBattery: \(Format.percent(0.67)) · Charging")
        #expect(!text.contains("Colored values"))
    }

    @Test func theTooltipSaysNothingForANormalBatteryOnBattery() {
        let s = snapshot(battery: battery(67))
        let text = MenuBarTooltip.text(recommendations: [], snapshot: s, items: [.battery(percent: 67, power: .onBattery)], locale: Locale(identifier: "en"))
        #expect(text == "Soaro: everything is fine")
    }

    @Test func aColouredBatteryIsExplainedLikeBefore() {
        let s = snapshot(battery: battery(9))
        let item = MenuBarItem.battery(percent: 9, power: .onBattery, level: .high)
        let lines = MenuBarTooltip.explanations(for: [item], snapshot: s)
        #expect(lines == ["Battery at \(Format.percent(0.09)), not plugged in (level: high)"])
        let text = MenuBarTooltip.text(recommendations: [], snapshot: s, items: [item], locale: Locale(identifier: "en"))
        #expect(text.contains("Colored values:\n• Battery at"))
        #expect(!text.contains("Charging"))
    }

    @Test func theTwoWordsOfTheChargingLineAreAlreadyInTheCatalogInNineLanguages() throws {
        let strings = try DockerStringsTests.catalogStrings()
        for key in ["Battery", "Charging"] {
            let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            for language in TranslationCatalog.requiredTranslations {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String ?? ""
                #expect(!value.isEmpty, "\(key) / \(language)")
            }
        }
    }
}

/// Le libellé complet de la barre de menus : image modèle ou colorée, mise en page, voisins inchangés.
@MainActor @Suite(.serialized) struct BatteryMenuBarLabelTests {
    private static let cpu = MenuBarItem.stacked(label: "CPU", value: "43%")
    private static let pair = MenuBarItem.pair(top: "↑ 99 KB/s", bottom: "↓ 13 KB/s")

    private func render(_ items: [MenuBarItem], compact: Bool = true, dark: Bool = false, severity: Severity? = nil, contrast: Bool = false) throws -> NSImage {
        try #require(MenuBarRenderer.image(severity: severity, compact: compact, items: items, darkBar: dark, increasedContrast: contrast))
    }

    // MARK: règle de l'image modèle

    @Test func aNormalBatteryKeepsTheLabelATemplateImage() throws {
        for charging in [false, true] {
            for percent in [100, 67, 21, 20 + 1] {
                #expect(try render([Self.cpu, .battery(percent: percent, power: charging ? .charging : .onBattery)]).isTemplate, "\(percent) %, charging \(charging)")
            }
        }
        #expect(try render([.battery(percent: 67, power: .charging)], compact: false).isTemplate)
    }

    @Test func aColouredLevelMakesTheLabelACarriedColourImage() throws {
        for level in [PressureLevel.medium, .high, .critical] {
            #expect(try !render([.battery(percent: 8, power: .onBattery, level: level)]).isTemplate, "\(level)")
        }
    }

    @Test func aFlagStillMakesItNonTemplateWithABatteryNextToIt() throws {
        let image = try render([Self.pair, .flag(countryCode: "FR"), .battery(percent: 67, power: .charging)])
        #expect(!image.isTemplate)
    }

    @Test func everyDisplayedValueChangesTheImage() throws {
        let base = try render([.battery(percent: 67, power: .onBattery)])
        #expect(try render([.battery(percent: 67, power: .onBattery)]) === base, "même liste : le cache sert la même image")
        let other = try render([.battery(percent: 66, power: .onBattery)])
        #expect(other !== base, "le pourcentage fait partie de la clé de cache")
        let charging = try render([.battery(percent: 66, power: .charging)])
        #expect(charging !== other, "la charge aussi")
        let level = try render([.battery(percent: 66, power: .charging, level: .medium)])
        #expect(level !== charging && !level.isTemplate && charging.isTemplate, "et le niveau")
        let contrast = try render([.battery(percent: 66, power: .charging, level: .medium)], contrast: true)
        #expect(contrast !== level, "et le contraste renforcé (le trait change)")
    }

    // MARK: mise en page

    @Test func theHeightStays22PointsInBothStyles() throws {
        for compact in [true, false] {
            for charging in [false, true] {
                #expect(try render([Self.cpu, .battery(percent: 67, power: charging ? .charging : .onBattery)], compact: compact).size.height == 22, "compact \(compact)")
            }
        }
    }

    @Test func theLabelWidthDoesNotChangeBetween9And100Percent() throws {
        let nine = try render([Self.cpu, .battery(percent: 9, power: .onBattery)])
        let hundred = try render([Self.cpu, .battery(percent: 100, power: .onBattery)])
        let fifty = try render([Self.cpu, .battery(percent: 50, power: .charging)])
        #expect(nine.size.width == hundred.size.width, "largeur mini de \(MenuBarLabelLayout.batteryMinWidth) pt : « 9% » et « 100% » ne décalent rien")
        #expect(fifty.size.width == hundred.size.width)
    }

    @Test func theBatteryItemIsAsWideAsTheWrittenMinimum() throws {
        let without = try render([Self.cpu])
        let with = try render([Self.cpu, .battery(percent: 100, power: .onBattery)])
        #expect(abs((with.size.width - without.size.width) - CGFloat(MenuBarLabelLayout.batteryMinWidth + 9)) < 1.0, "icône + valeur + l'espace entre blocs")
        let classic = try render([Self.cpu, .battery(percent: 100, power: .onBattery)], compact: false)
        let classicWithout = try render([Self.cpu], compact: false)
        #expect(classic.size.width > classicWithout.size.width + 30)
    }

    @Test func theOtherItemsDoNotMoveWhenTheBatteryIsAdded() throws {
        let items = [Self.cpu, Self.pair]
        let without = try GlyphInk(image: render(items))
        let with = try GlyphInk(image: render(items + [.battery(percent: 67, power: .charging)]))
        var moved = 0
        for x in 0..<without.width { for y in 0..<without.height where abs(without.alpha(x, y) - with.alpha(x, y)) > 0.1 { moved += 1 } }
        #expect(moved == 0, "\(moved) pixels ont bougé")
        #expect(with.width > without.width)
    }

    @Test func noBatteryLabelTextRemainsInTheItem() throws {
        // L'ancien libellé « BAT » (7,5 pt) a disparu : l'élément tient sur une ligne de 22 pt, vide au-dessus et en dessous de l'icône.
        let without = try GlyphInk(image: render([Self.cpu]))
        let with = try GlyphInk(image: render([Self.cpu, .battery(percent: 67, power: .onBattery)]))
        let originX = (CGFloat(without.width) / without.scale) + 9
        let rows = (0..<with.height).filter { y in
            (Int(originX * with.scale)..<with.width).contains { with.alpha($0, y) > 0.5 }
        }
        let top = Double(rows.first ?? 0) / Double(with.scale), bottom = Double(rows.last ?? 0) / Double(with.scale)
        // L'ensemble est centré dans les 22 pt : autant de marge en haut qu'en bas, à un demi-point près.
        #expect(abs(top - (22 - bottom - 1 / Double(with.scale))) < 1.0, "marge haute \(top), basse \(22 - bottom)")
    }

    // MARK: l'icône dans le libellé

    /// Origine (en points) de l'icône dans le libellé : le dernier élément, juste après l'espace entre blocs.
    /// Le rendu arrondit la largeur de l'image au point : on cherche le bord gauche du contour à un point près de l'estimation.
    private func glyphOrigin(items: [MenuBarItem], compact: Bool, in ink: GlyphInk? = nil) throws -> CGPoint {
        let before = try render(items, compact: compact)
        let spacing: CGFloat = compact ? 9 : 6
        var origin = before.size.width + spacing
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        let y = (22 - g.totalSize.height) / 2
        if let ink {
            let row = Int(((y + g.bodyRect.midY) * ink.scale).rounded())
            let start = Int(((origin - 1.5) * ink.scale).rounded())
            if let x = ink.opaqueRun(row: row, columns: start..<min(ink.width, start + Int(3 * ink.scale))).first { origin = CGFloat(x) / ink.scale }
        }
        return CGPoint(x: origin, y: y)
    }

    /// Le libellé lu en pixels, avec l'origine trouvée de l'icône.
    private func label(_ battery: MenuBarItem, dark: Bool = false, contrast: Bool = false) throws -> (ink: GlyphInk, origin: CGPoint) {
        let ink = try GlyphInk(image: render([Self.cpu, battery], dark: dark, contrast: contrast))
        return (ink, try glyphOrigin(items: [Self.cpu], compact: true, in: ink))
    }

    @Test func theIconIsLeftOfTheValueAndItsFillIsProportionalInTheRealLabel() throws {
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        for percent in [10, 50, 90, 100] {
            let (ink, origin) = try label(.battery(percent: percent, power: .onBattery))
            let row = Int(((origin.y + g.innerRect.midY) * ink.scale).rounded())
            let lo = Int(((origin.x + g.innerRect.minX) * ink.scale).rounded()), hi = Int(((origin.x + g.innerRect.maxX) * ink.scale).rounded())
            let run = ink.opaqueRun(row: row, columns: lo..<hi).count
            let expected = g.fillWidth(percent: Double(percent)) * ink.scale
            #expect(abs(Double(run) - Double(expected)) <= 1.5, "\(percent) % : \(run) px, \(expected) attendus")
        }
    }

    @Test func theValueTextSitsRightOfTheIcon() throws {
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        let (ink, origin) = try label(.battery(percent: 67, power: .onBattery))
        let afterIcon = Int(((origin.x + g.totalSize.width + 1) * ink.scale).rounded())
        let inkAfter = (afterIcon..<ink.width).reduce(0) { sum, x in sum + (0..<ink.height).filter { ink.alpha(x, $0) > 0.5 }.count }
        #expect(inkAfter > 40, "le pourcentage est à droite de l'icône")
    }

    @Test func theBoltAppearsInTheTemplateLabelOnlyWhenCharging() throws {
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        let (off, offOrigin) = try label(.battery(percent: 0, power: .onBattery))
        let (on, onOrigin) = try label(.battery(percent: 0, power: .charging))
        let box = g.boltRect.insetBy(dx: -BatteryGlyphGeometry.haloWidth, dy: -BatteryGlyphGeometry.haloWidth)
        // Dans la boîte du repère et de son halo, l'image charge et l'image sur batterie diffèrent nettement (encre du repère, jeu du halo).
        var differing = 0
        let x0 = Int(((box.minX + onOrigin.x) * on.scale).rounded()), x1 = Int(((box.maxX + onOrigin.x) * on.scale).rounded())
        let y0 = Int(((box.minY + onOrigin.y) * on.scale).rounded()), y1 = Int(((box.maxY + onOrigin.y) * on.scale).rounded())
        for x in x0..<x1 { for y in y0..<y1 where abs(on.alpha(x, y) - off.alpha(x - Int(((onOrigin.x - offOrigin.x) * on.scale).rounded()), y)) > 0.5 { differing += 1 } }
        #expect(differing > 12, "\(differing) pixels (à 2x) diffèrent dans la boîte du repère")
        #expect(on.opaqueCount(in: g.boltRect, origin: onOrigin) > 6, "de l'encre pleine pour l'éclair dans le libellé")
        #expect(try render([Self.cpu, .battery(percent: 0, power: .charging)]).isTemplate)
    }

    @Test func theIconIsDrawnOnBothBarTonesInTheColouredImage() throws {
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        for dark in [false, true] {
            let (ink, origin) = try label(.battery(percent: 40, power: .onBattery, level: .high), dark: dark)
            let y = Int(((origin.y + g.bodyRect.midY) * ink.scale).rounded())
            // Le trait (1,2 pt) tombe à cheval sur les pixels : on prend le plus opaque de ses colonnes.
            let first = Int((origin.x * ink.scale).rounded())
            let outline = (first..<first + 2).map { ink.pixel($0, y) }.max { $0.a < $1.a }!
            let expected = dark ? 1.0 : 0.0
            #expect(outline.a > 0.8 && abs(outline.r - expected) < 0.15 && abs(outline.b - expected) < 0.15, "contour, barre \(dark ? "sombre" : "claire") : \(outline)")
            let fill = ink.pixel(Int(((origin.x + g.innerRect.minX + 1.5) * ink.scale).rounded()), y)
            #expect(fill.a > 0.8 && fill.r > 0.85 && fill.g < 0.35, "remplissage rouge : \(fill)")
        }
    }

    @Test func theScarletCriticalFillAndThePillStayTogether() throws {
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        let (ink, origin) = try label(.battery(percent: 40, power: .onBattery, level: .critical), dark: true)
        let y = Int(((origin.y + g.bodyRect.midY) * ink.scale).rounded())
        let fill = ink.pixel(Int(((origin.x + g.innerRect.minX + 1.5) * ink.scale).rounded()), y)
        #expect(fill.a > 0.8 && fill.r > 0.9 && fill.g < 0.3 && fill.b < 0.1, "remplissage écarlate : \(fill)")
        // La pastille écarlate du texte (SL antérieures) est à droite : des pixels écarlates au-delà de l'icône.
        var scarletAfter = 0
        for x in Int(((origin.x + g.totalSize.width + 1) * ink.scale).rounded())..<ink.width {
            for yy in 0..<ink.height { let p = ink.pixel(x, yy); if p.a > 0.8 && p.r > 0.9 && p.g < 0.3 && p.b < 0.1 { scarletAfter += 1 } }
        }
        #expect(scarletAfter > 40)
    }

    @Test func increaseContrastThickensTheOutlineInTheLabel() throws {
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        func outlineRun(_ contrast: Bool) throws -> Int {
            let (ink, origin) = try label(.battery(percent: 0, power: .onBattery), contrast: contrast)
            let y = Int(((origin.y + g.bodyRect.midY) * ink.scale).rounded())
            let lo = Int((origin.x * ink.scale).rounded())
            return ink.opaqueRun(row: y, columns: lo..<(lo + Int(3 * ink.scale))).count
        }
        #expect(try outlineRun(true) > outlineRun(false))
    }
}

