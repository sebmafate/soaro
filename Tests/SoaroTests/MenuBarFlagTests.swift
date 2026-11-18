import AppKit
import CoreText
import Foundation
import SwiftUI
import Testing
@testable import Soaro

/// SL19 : le drapeau du pays de l'IP publique, à droite de l'activité réseau dans la barre de menus.
/// Il n'utilise QUE la recherche d'IP publique facultative qui existe déjà : aucun appel réseau, aucun réglage nouveau.
/// Le rendu réel dans la vraie barre de menus (clair/sombre, Mac à encoche) se vérifie à la main ; ici, la logique pure
/// et des rendus hors écran du libellé.
@Suite struct MenuBarFlagLogicTests {
    private let GB: UInt64 = 1_000_000_000

    private func snapshot(network: Bool = true) -> SystemSnapshot {
        SystemSnapshot(
            date: Date(), cpu: CPUStats(user: 0.33, system: 0.10),
            memory: MemoryStats(total: 16 * GB, app: 8 * GB, wired: 3 * GB, compressed: 2 * GB, cached: GB, swapUsed: 0, pressure: .normal),
            disk: DiskStats(total: 1_000 * GB, available: 140 * GB),
            thermalState: .nominal, uptime: 100,
            gpu: nil,
            battery: BatteryStats(percent: 100, isCharging: true, isPluggedIn: true, isFullyCharged: false, minutesRemaining: nil, cycleCount: 1,
                                  health: 1, designCapacity: nil, maxCapacity: nil, temperature: nil, batteryPower: nil, systemPower: nil, adapterWatts: nil),
            network: network ? NetworkStats(downRate: 13_000, upRate: 99_000, localIP: nil, wifi: nil, latencyMs: nil) : nil
        )
    }

    private func info(code: String?) -> PublicIPInfo {
        PublicIPInfo(ip: "203.0.113.42", countryCode: code, country: "France", city: nil, provider: nil, fetchedAt: Date())
    }

    // MARK: Quel code donne un drapeau

    @Test(arguments: ["FR", "fr", "US", "DE", "JP", "GB", "CH", "BR", "CN", "KR", "IT", "ES", "CA", "AU", "IN", "NL", "SE", "EU"])
    func aRealCountryCodeGivesItsFlag(code: String) {
        let flag = MenuBarFlag.emoji(forCountryCode: code)
        #expect(flag != nil)
        #expect(flag == PublicIPService.flagEmoji(code))
    }

    @Test(arguments: ["XX", "ZZ", "AA", "QQ", "YY", "EZ", "QO"])
    func aTwoLetterCodeWithNoFlagGlyphGivesNothingNotAPlaceholderBox(code: String) {
        // « XX » ferait deux lettres encadrées côte à côte : on n'affiche rien.
        #expect(PublicIPService.flagEmoji(code) != nil, "le service le croit valide : c'est bien ce que MenuBarFlag doit rattraper")
        #expect(MenuBarFlag.emoji(forCountryCode: code) == nil)
    }

    @Test(arguments: ["", " ", "F", "FRA", "1F", "é!", "F R", "fr\n"])
    func anInvalidCodeGivesNothing(code: String) {
        #expect(MenuBarFlag.emoji(forCountryCode: code) == nil)
    }

    @Test func noCodeGivesNothing() {
        #expect(MenuBarFlag.emoji(forCountryCode: nil) == nil)
    }

    @Test func everyCodeThatGivesAFlagIsExactlyOneGlyphOfTheEmojiFont() {
        let font = CTFontCreateWithName("Apple Color Emoji" as CFString, 12, nil)
        var accepted = 0
        for a in UnicodeScalar("A").value...UnicodeScalar("Z").value {
            for b in UnicodeScalar("A").value...UnicodeScalar("Z").value {
                let code = String(UnicodeScalar(a)!) + String(UnicodeScalar(b)!)
                guard let flag = MenuBarFlag.emoji(forCountryCode: code) else { continue }
                accepted += 1
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: flag, attributes: [.font: font]))
                let glyphs = (CTLineGetGlyphRuns(line) as? [CTRun] ?? []).reduce(0) { $0 + CTRunGetGlyphCount($1) }
                #expect(glyphs == 1, "\(code) ne tient pas en un seul glyphe")
            }
        }
        #expect(accepted > 240, "le balayage ne doit pas être vide : \(accepted) codes acceptés")
    }

    // MARK: Quand la recherche est faite

    @Test func theCodeComesFromTheLookupOnlyWhenTheOptInIsOnOrInDemo() {
        #expect(MenuBarFlag.countryCode(lookupEnabled: true, demo: false, info: info(code: "FR")) == "FR")
        #expect(MenuBarFlag.countryCode(lookupEnabled: false, demo: false, info: info(code: "FR")) == nil, "réglage coupé : rien, même si une valeur traîne en mémoire")
        #expect(MenuBarFlag.countryCode(lookupEnabled: false, demo: true, info: info(code: "FR")) == "FR", "démo : la France de DemoData")
        #expect(MenuBarFlag.countryCode(lookupEnabled: true, demo: false, info: nil) == nil, "pas encore de réponse, ou échec")
        #expect(MenuBarFlag.countryCode(lookupEnabled: true, demo: false, info: info(code: nil)) == nil)
        #expect(MenuBarFlag.countryCode(lookupEnabled: true, demo: false, info: info(code: "XX")) == nil)
        #expect(MenuBarFlag.countryCode(lookupEnabled: true, demo: false, info: info(code: "fr")) == "FR")
    }

    @Test func theDemoPublicIPIsFrance() {
        #expect(MenuBarFlag.countryCode(lookupEnabled: false, demo: true, info: DemoData.publicIP()) == "FR")
    }

    // MARK: Éléments de la barre

    @Test func theFlagFollowsTheNetworkPairAndComesBeforeTheBattery() {
        let items = MenuBarItem.items(for: snapshot(), cpu: true, gpu: false, memory: false, disk: false, network: true, battery: true, publicIPCountryCode: "FR")
        #expect(items == [
            .stacked(label: "CPU", value: Format.percent(0.43)),
            .pair(top: "↑ 99 KB/s", bottom: "↓ 13 KB/s"),
            .flag(countryCode: "FR"),
            .stacked(label: "BAT ⚡︎", value: Format.percent(1)),
        ])
    }

    @Test func noFlagWithoutACountryCodeAndTheListIsUnchanged() {
        let without = MenuBarItem.items(for: snapshot(), cpu: true, gpu: false, memory: false, disk: false, network: true, battery: true)
        let withNil = MenuBarItem.items(for: snapshot(), cpu: true, gpu: false, memory: false, disk: false, network: true, battery: true, publicIPCountryCode: nil)
        #expect(without == withNil)
        #expect(!without.contains { if case .flag = $0 { true } else { false } })
    }

    @Test func theFlagIsShownOnlyWhenTheNetworkItemIsShown() {
        // Réseau décoché dans les réglages.
        let off = MenuBarItem.items(for: snapshot(), cpu: true, gpu: false, memory: false, disk: false, network: false, battery: false, publicIPCountryCode: "FR")
        #expect(off == [.stacked(label: "CPU", value: Format.percent(0.43))])
        // Réseau coché mais sans mesure (pas encore de débit) : pas de bloc réseau, donc pas de drapeau.
        let noMeasure = MenuBarItem.items(for: snapshot(network: false), cpu: true, gpu: false, memory: false, disk: false, network: true, battery: false, publicIPCountryCode: "FR")
        #expect(noMeasure == [.stacked(label: "CPU", value: Format.percent(0.43))])
    }

    @Test func anUnknownOrInvalidCodeAddsNothing() {
        for code in ["XX", "ZZ", "", "FRA", "1F"] {
            let items = MenuBarItem.items(for: snapshot(), cpu: false, gpu: false, memory: false, disk: false, network: true, battery: false, publicIPCountryCode: code)
            #expect(items == [.pair(top: "↑ 99 KB/s", bottom: "↓ 13 KB/s")], "code \(code.debugDescription)")
        }
    }

    @Test func aLowercaseCodeIsNormalised() {
        let items = MenuBarItem.items(for: snapshot(), cpu: false, gpu: false, memory: false, disk: false, network: true, battery: false, publicIPCountryCode: "fr")
        #expect(items.last == .flag(countryCode: "FR"))
    }

    @Test func theFlagHasNoPressureLevel() {
        #expect(MenuBarItem.flag(countryCode: "FR").level == .normal)
    }

    // MARK: Style classique (une ligne de texte)

    @Test func inlineTextPutsTheFlagRightAfterTheNetworkPairWithoutASeparator() {
        let items: [MenuBarItem] = [.stacked(label: "CPU", value: "43%"), .pair(top: "↑ 1 KB/s", bottom: "↓ 2 KB/s"), .flag(countryCode: "FR"), .stacked(label: "BAT", value: "100%")]
        #expect(MenuBarItem.inlineText(items) == "CPU 43% · ↓ 2 KB/s ↑ 1 KB/s 🇫🇷 · BAT 100%")
        #expect(MenuBarItem.inlineText([.pair(top: "↑ 1 KB/s", bottom: "↓ 2 KB/s"), .flag(countryCode: "FR")]) == "↓ 2 KB/s ↑ 1 KB/s 🇫🇷")
    }

    @Test func inlineTextIsUnchangedWithoutAFlag() {
        #expect(MenuBarItem.inlineText([.stacked(label: "CPU", value: "43%"), .pair(top: "↑ 1 KB/s", bottom: "↓ 2 KB/s")]) == "CPU 43% · ↓ 2 KB/s ↑ 1 KB/s")
    }

    // MARK: Infobulle

    @Test func theTooltipNamesTheCountryAndNeverTheIPAddress() {
        let items: [MenuBarItem] = [.pair(top: "↑ 1 KB/s", bottom: "↓ 2 KB/s"), .flag(countryCode: "FR")]
        let text = MenuBarTooltip.text(recommendations: [], snapshot: snapshot(), items: items, locale: Locale(identifier: "en"))
        #expect(text == "Soaro: everything is fine\n\nPublic IP country: France")
        #expect(!text.contains("203.0.113"))
        #expect(!text.contains("🇫🇷"))
    }

    @Test func theTooltipCountryFollowsTheLanguage() {
        #expect(MenuBarTooltip.countryName(code: "FR", locale: Locale(identifier: "fr")) == "France")
        #expect(MenuBarTooltip.countryName(code: "FR", locale: Locale(identifier: "ja")) == "フランス")
        #expect(MenuBarTooltip.countryName(code: "DE", locale: Locale(identifier: "en")) == "Germany")
    }

    @Test func theTooltipIsUnchangedWithoutAFlag() {
        let text = MenuBarTooltip.text(recommendations: [], snapshot: snapshot(), items: [.pair(top: "↑ 1 KB/s", bottom: "↓ 2 KB/s")], locale: Locale(identifier: "en"))
        #expect(text == "Soaro: everything is fine")
    }

    @Test func theCountrySentenceIsInTheCatalogInNineLanguages() throws {
        let strings = try DockerStringsTests.catalogStrings()
        let key = "Public IP country: %@"
        let entry = strings[key] as? [String: Any]
        #expect(entry != nil, "clé absente du catalogue : \(key.debugDescription)")
        let localizations = entry?["localizations"] as? [String: Any] ?? [:]
        for language in TranslationCatalog.requiredTranslations {
            let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
            let value = unit?["value"] as? String ?? ""
            #expect(!value.isEmpty, "\(key.debugDescription) / \(language)")
            #expect(TranslationCatalog.placeholderProblems(source: key, translation: value).isEmpty, "\(language) : \(TranslationCatalog.placeholderProblems(source: key, translation: value))")
            #expect(unit?["state"] as? String == "translated", "\(language)")
            #expect((localizations[language] as? [String: Any])?["variations"] == nil)
        }
    }
}

/// Garde de source : le drapeau ne déclenche aucune recherche de son côté (R9, T6 de TESTING.md).
@Suite struct MenuBarFlagPrivacyTests {
    private func read(_ path: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
    }

    @Test func theFlagCodeReferencesNoNetworkAPINorTheLookup() throws {
        for path in ["Sources/Soaro/Views/MenuBarWidgets.swift", "Sources/Soaro/Views/MenuBarFlag.swift", "Sources/Soaro/SoaroApp.swift"] {
            let source = try read(path)
            for word in ["URLSession", "NWConnection", "PublicIPService.fetch", "refreshPublicIP", "Data(contentsOf", "Process(", "curl"] {
                #expect(!source.contains(word), "\(path) mentionne \(word)")
            }
        }
    }

    @Test func onlyTheThreeExistingFilesTriggerTheLookup() throws {
        let files = try NetworkAllowlist.sourceFiles(root: RepositoryRoot.url())
        let callers = files.filter { $0.contents.contains("refreshPublicIP(") }.map(\.path)
        #expect(callers == ["Sources/Soaro/AppState.swift", "Sources/Soaro/Views/NetworkTab.swift", "Sources/Soaro/Views/SettingsView.swift"])
    }

    @Test func noNewSettingKeyIsAddedForTheFlag() {
        #expect(SettingsKey.defaults[SettingsKey.publicIP] as? Bool == false, "la recherche reste facultative et coupée par défaut")
        #expect(SettingsKey.defaults.keys.allSatisfy { !$0.lowercased().contains("flag") })
    }

    @Test func theLabelReadsTheExistingOptInAndDemoNotTheNetwork() throws {
        let source = try read("Sources/Soaro/SoaroApp.swift")
        #expect(source.contains("@AppStorage(SettingsKey.publicIP)"))
        #expect(source.contains("MenuBarFlag.countryCode("))
        #expect(source.contains("publicIPCountryCode:"))
    }
}

/// Rendus hors écran du libellé : l'image modèle est monochrome, donc un drapeau en couleur impose une image qui porte ses couleurs.
@MainActor @Suite(.serialized) struct MenuBarFlagRenderTests {
    private static let cpu = MenuBarItem.stacked(label: "CPU", value: "43%")
    private static let pair = MenuBarItem.pair(top: "↑ 99 KB/s", bottom: "↓ 13 KB/s")
    private static let flag = MenuBarItem.flag(countryCode: "FR")

    private func render(_ items: [MenuBarItem], compact: Bool = true, dark: Bool = false, severity: Severity? = nil) throws -> NSImage {
        try #require(MenuBarRenderer.image(severity: severity, compact: compact, items: items, darkBar: dark))
    }

    /// Pixels RGBA non prémultipliés d'une image, ligne par ligne.
    private struct Pixels {
        let width: Int, height: Int
        let data: [UInt8]
        let scale: CGFloat

        init(_ image: NSImage) throws {
            var rect = CGRect(origin: .zero, size: CGSize(width: image.size.width * 2, height: image.size.height * 2))      // demande la représentation @2x
            let cg = try #require(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
            width = cg.width; height = cg.height
            scale = CGFloat(cg.width) / image.size.width
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let context = try #require(CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            data = buffer
        }

        func pixel(_ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double, a: Double) {
            let i = (y * width + x) * 4
            let a = Double(data[i + 3]) / 255
            guard a > 0 else { return (0, 0, 0, 0) }
            return (Double(data[i]) / 255 / a, Double(data[i + 1]) / 255 / a, Double(data[i + 2]) / 255 / a, a)
        }

        /// Pixel opaque dont les canaux s'écartent nettement : une vraie couleur, pas du noir, du blanc ou du gris.
        func isColoured(_ x: Int, _ y: Int) -> Bool {
            let p = pixel(x, y)
            return p.a > 0.5 && (max(p.r, p.g, p.b) - min(p.r, p.g, p.b)) > 0.25
        }

        var colouredColumns: ClosedRange<Int>? {
            var first: Int?, last: Int?
            for x in 0..<width { for y in 0..<height where isColoured(x, y) { first = first ?? x; last = x } }
            return first.flatMap { f in last.map { f...$0 } }
        }

        var colouredCount: Int {
            var n = 0
            for x in 0..<width { for y in 0..<height where isColoured(x, y) { n += 1 } }
            return n
        }

        /// Luminance moyenne des pixels bien opaques qui ne sont pas colorés (le texte et le glyphe de la marque). La bande blanche du drapeau est neutre aussi : on s'arrête avant lui.
        func meanLuminanceOfNeutralInk(upToColumn limit: Int? = nil) -> Double {
            var sum = 0.0, n = 0.0
            for x in 0..<min(width, limit ?? width) { for y in 0..<height {
                let p = pixel(x, y)
                guard p.a > 0.9, !isColoured(x, y) else { continue }
                sum += 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b; n += 1
            } }
            return n > 0 ? sum / n : -1
        }
    }

    // MARK: Image modèle ou image colorée

    @Test func withoutAFlagAndWithNothingColouredTheImageStaysATemplate() throws {
        #expect(try render([Self.cpu, Self.pair]).isTemplate)
    }

    @Test func withAFlagTheImageCarriesItsOwnColoursSoItIsNotATemplate() throws {
        // Cause : une image modèle est monochrome (seul son canal alpha compte, macOS la teinte) : un drapeau en couleur y deviendrait une silhouette.
        let image = try render([Self.cpu, Self.pair, Self.flag])
        #expect(!image.isTemplate)
        #expect(try Pixels(image).colouredCount > 40, "le drapeau garde ses couleurs")
    }

    @Test func theFlagStaysInColourOnBothBarsAndBothStyles() throws {
        for dark in [false, true] {
            for compact in [true, false] {
                let image = try render([Self.cpu, Self.pair, Self.flag], compact: compact, dark: dark)
                #expect(!image.isTemplate, "dark \(dark), compact \(compact)")
                #expect(try Pixels(image).colouredCount > 40, "dark \(dark), compact \(compact)")
            }
        }
    }

    @Test func aFlagWithOnlyTheBrandStillGivesAColourImage() throws {
        // Cas limite voulu : un drapeau seul n'a pas de sens (il suit le réseau), mais le rendu ne doit pas planter.
        #expect(try !render([Self.flag]).isTemplate)
    }

    @Test func theTemplateStateFollowsTheFlagThroughTheCache() throws {
        let plain = try render([Self.cpu, Self.pair])
        let flagged = try render([Self.cpu, Self.pair, Self.flag])
        let plainAgain = try render([Self.cpu, Self.pair])
        #expect(plain.isTemplate && !flagged.isTemplate && plainAgain.isTemplate)
        #expect(plain !== flagged, "la clé de cache contient le drapeau")
        // Même liste : le cache sert la même image.
        #expect(try render([Self.cpu, Self.pair, Self.flag]) !== plain)
        let a = try render([Self.cpu, Self.pair, Self.flag])
        let b = try render([Self.cpu, Self.pair, Self.flag])
        #expect(a === b)
    }

    @Test func anotherCountryIsAnotherImage() throws {
        let fr = try render([Self.pair, .flag(countryCode: "FR")])
        let de = try render([Self.pair, .flag(countryCode: "DE")])
        #expect(fr !== de)
        #expect(!de.isTemplate)
    }

    // MARK: Barre claire et barre sombre

    /// Luminance de l'encre neutre du libellé, drapeau exclu (sa bande blanche serait comptée).
    private func inkLuminance(_ items: [MenuBarItem], dark: Bool) throws -> Double {
        let without = items.filter { !$0.isFlag }
        let limit = try render(without, dark: dark).size.width
        let pixels = try Pixels(render(items, dark: dark))
        return pixels.meanLuminanceOfNeutralInk(upToColumn: Int((limit * pixels.scale).rounded(.down)))
    }

    @Test func theNeutralInkIsWhiteOnADarkBarAndBlackOnALightBarEvenWithAFlag() throws {
        let dark = try inkLuminance([Self.cpu, Self.pair, Self.flag], dark: true)
        let light = try inkLuminance([Self.cpu, Self.pair, Self.flag], dark: false)
        #expect(dark > 0.85, "texte clair sur barre sombre : \(dark)")
        #expect(light >= 0 && light < 0.15, "texte foncé sur barre claire : \(light)")
    }

    @Test func aColouredValueTogetherWithAFlagStillWorksOnBothBars() throws {
        let items: [MenuBarItem] = [.stacked(label: "CPU", value: "97%", level: .high), Self.pair, Self.flag]
        for dark in [false, true] {
            let image = try render(items, dark: dark)
            #expect(!image.isTemplate)
        }
        let darkInk = try inkLuminance(items, dark: true)
        let lightInk = try inkLuminance(items, dark: false)
        #expect(darkInk > lightInk + 0.5)
    }

    // MARK: Place, hauteur et largeur

    @Test func theHeightIs22PointsWithOrWithoutTheFlagInBothStyles() throws {
        for compact in [true, false] {
            let without = try render([Self.cpu, Self.pair], compact: compact)
            let with = try render([Self.cpu, Self.pair, Self.flag], compact: compact)
            #expect(without.size.height == 22)
            #expect(with.size.height == 22, "compact \(compact)")
        }
    }

    @Test func theFlagOnlyAddsItsOwnWidthAtTheRightOfTheRates() throws {
        for compact in [true, false] {
            let without = try render([Self.cpu, Self.pair], compact: compact)
            let with = try render([Self.cpu, Self.pair, Self.flag], compact: compact)
            let added = with.size.width - without.size.width
            #expect(added > 10 && added < 30, "le drapeau ajoute \(added) pt (compact \(compact))")

            // Tout ce qui est en couleur est à droite de ce que le libellé sans drapeau occupait, moins l'espace entre blocs.
            let pixels = try Pixels(with)
            let columns = try #require(pixels.colouredColumns)
            let limit = (without.size.width - (compact ? 9 : 6)) * pixels.scale
            #expect(CGFloat(columns.lowerBound) >= limit - 1, "le drapeau est à droite des débits (compact \(compact))")
            #expect(columns.upperBound < pixels.width)
        }
    }

    @Test func theOtherItemsDoNotMoveWhenTheFlagIsAdded() throws {
        let without = try render([Self.cpu, Self.pair])
        let with = try render([Self.cpu, Self.pair, Self.flag])
        let a = try Pixels(without), b = try Pixels(with)
        #expect(a.height == b.height)
        // Les colonnes du libellé sans drapeau sont identiques, pixel pour pixel, dans l'image avec drapeau.
        var different = 0
        for x in 0..<a.width { for y in 0..<a.height {
            let p = a.pixel(x, y), q = b.pixel(x, y)
            if abs(p.a - q.a) > 0.1 { different += 1 }
        } }
        #expect(different == 0, "\(different) pixels ont bougé")
    }

    @Test func anUnknownCodeLeavesTheImageExactlyAsWithoutAFlag() throws {
        let items = MenuBarItem.items(for: SystemSnapshot(
            date: Date(), cpu: CPUStats(user: 0.1, system: 0.1),
            memory: MemoryStats(total: 16_000_000_000, app: 1, wired: 1, compressed: 1, cached: 1, swapUsed: 0, pressure: .normal),
            disk: DiskStats(total: 1_000_000_000_000, available: 900_000_000_000), thermalState: .nominal, uptime: 1,
            network: NetworkStats(downRate: 13_000, upRate: 99_000, localIP: nil, wifi: nil, latencyMs: nil)),
            cpu: false, gpu: false, memory: false, disk: false, network: true, battery: false, publicIPCountryCode: "XX")
        let image = try render(items)
        #expect(image.isTemplate)
        #expect(image.size.width == (try render([Self.pair])).size.width)
        #expect(try Pixels(image).colouredCount == 0, "aucune case de remplacement")
    }

    @Test func theAlertBadgeStillWorksNextToTheFlag() throws {
        let image = try render([Self.cpu, Self.pair, Self.flag], severity: .warning)
        #expect(!image.isTemplate)
        #expect(image.size.height == 22)
    }
}
