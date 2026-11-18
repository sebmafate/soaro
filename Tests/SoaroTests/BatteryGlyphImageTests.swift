import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Soaro

/// SL24 : l'icône de batterie de la carte de l'aperçu (28 x 13 pt) et de l'onglet Batterie (32 x 15 pt) passe par le MÊME dessin à pixels entiers que le
/// libellé de la barre de menus (SL23). Ici : le rendu lu en pixels, à 1x, 2x et 3x, dans chaque état ; le thème clair et sombre ; « Augmenter le contraste » ;
/// la vue SwiftUI ; et le code source (l'ancien dessin SwiftUI a disparu).

/// Les rendus de l'icône, à une échelle EXPLICITE (comme les tests du libellé : un test ne dépend pas de l'écran de la machine qui le lance).
@MainActor enum BatteryGlyphRender {
    static let cardBody = BatteryGlyphGeometry.cardBody
    static let tabBody = BatteryGlyphGeometry.tabBody
    static let bodies: [(name: String, body: CGSize)] = [("carte", cardBody), ("onglet", tabBody)]

    /// Encre opaque noire (le blanc et le noir à 56 % du jeton rendraient la mesure de netteté dépendante de l'opacité).
    static let opaque = LabelPalette(base: CGColor(gray: 0, alpha: 1), orange: CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1),
                                     red: CGColor(srgbRed: 1, green: 0.2, blue: 0.2, alpha: 1), scarlet: CGColor(srgbRed: 1, green: 0.14, blue: 0, alpha: 1),
                                     white: CGColor(gray: 1, alpha: 1))

    static func nub(_ body: CGSize) -> CGFloat { BatteryPixelGeometry.nubPoints(forBody: body) }
    static func margin(_ body: CGSize) -> Int { Int(BatteryPixelGeometry.overflowPoints(bodyPoints: body)) }

    static func environment(dark: Bool) -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.colorScheme = dark ? .dark : .light
        return environment
    }

    /// L'image dynamique, dessinée par AppKit à l'échelle demandée.
    static func direct(_ body: CGSize, percent: Double, power: BatteryPowerState = .onBattery, level: PressureLevel = .normal, scale: Int,
                       contrast: Bool = false, palette: LabelPalette = opaque) throws -> GlyphInk {
        let image = BatteryGlyphDrawing.image(percent: percent, power: power, level: level, bodyPoints: body, nubPoints: nub(body), palette: palette, increasedContrast: contrast)
        return try GlyphInk(image: image, scale: CGFloat(scale))
    }

    /// La vue SwiftUI, rendue hors écran à l'échelle demandée (avec la marge du repère, que la vue compense par un remplissage négatif).
    static func swiftUI(_ body: CGSize, percent: Double, power: BatteryPowerState = .onBattery, level: PressureLevel = .normal, scale: Int,
                        dark: Bool = false, contrast: Bool = false) throws -> GlyphInk {
        let view = BatteryGlyphImage(percent: percent, power: power, level: level, body: body, increasedContrast: contrast)
            .padding(.vertical, CGFloat(margin(body)))
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = CGFloat(scale)
        return try GlyphInk(cg: try #require(renderer.cgImage), scale: CGFloat(scale))
    }

    static func geometry(_ body: CGSize, scale: Int, contrast: Bool = false) -> BatteryPixelGeometry {
        BatteryPixelGeometry(bodyPoints: body, nubPoints: nub(body), scale: scale, increasedContrast: contrast)
    }

    static let powers: [(name: String, power: BatteryPowerState, level: PressureLevel)] = [
        ("normal", .onBattery, .normal), ("orange", .onBattery, .medium), ("rouge", .onBattery, .high), ("critique", .onBattery, .critical),
        ("éclair", .charging, .normal), ("prise", .pluggedNotCharging, .normal),
    ]
    static let percents: [Double] = [0, 4, 20, 50, 67, 80, 100]

    /// Les bords alignés sur les axes du corps (le haut, le bas, le côté gauche, le flanc du bout, le bord droit du remplissage), avec l'origine du corps en pixels.
    static func edges(_ g: BatteryPixelGeometry, percent: Double, origin: (x: Int, y: Int)) -> [(name: String, rect: PixelRect)] {
        let r = Int(g.cornerRadius.rounded(.up)) + 1
        let line = g.lineWidth
        let flat = g.body.width - 2 * r
        var list: [(String, PixelRect)] = [
            ("haut", PixelRect(x: origin.x + r, y: origin.y, width: flat, height: line)),
            ("bas", PixelRect(x: origin.x + r, y: origin.y + g.body.height - line, width: flat, height: line)),
            ("gauche", PixelRect(x: origin.x, y: origin.y + r, width: line, height: g.body.height - 2 * r)),
            ("bout, flanc", PixelRect(x: origin.x + g.nub.x, y: origin.y + g.nub.y, width: 1, height: g.nub.height)),
        ]
        let fill = g.fillRect(percent: percent)
        if fill.width > 0 {
            let radius = Int(g.cornerRadius.rounded(.up)) - g.lineWidth + 1
            let rows = max(1, fill.height - 2 * radius)
            list.append(("bord du remplissage", PixelRect(x: origin.x + fill.maxX - 1, y: origin.y + fill.y + (fill.height - rows) / 2, width: 2, height: rows)))
        }
        return list
    }

    static func soft(_ ink: GlyphInk, _ rect: PixelRect, relative: Bool = false) -> EdgeSoftness {
        let xs = max(0, rect.x)..<min(ink.width, rect.maxX), ys = max(0, rect.y)..<min(ink.height, rect.maxY)
        return relative ? SharpnessMetric.relativeEdgeSoftness(ink, xs: xs, ys: ys) : SharpnessMetric.edgeSoftness(ink, xs: xs, ys: ys)
    }
}

// MARK: - Netteté

/// Les bords alignés sur les axes tombent sur des pixels entiers à 1x, 2x et 3x : AUCUN pixel d'alpha intermédiaire. La tolérance est zéro : la mesure
/// de départ (SL23, dessin SwiftUI) donnait 0,73 (carte) et 0,96 (onglet) de pixels intermédiaires en 1x, 0,49 et 0,33 en 2x ; ici le dessin est le même
/// que celui de la barre de menus, dont les tests (SL23) fixent aussi zéro.
@MainActor @Suite(.serialized) struct BatteryGlyphSharpnessTests {
    @Test(arguments: [1, 2, 3])
    func theCardAndTabEdgesAreOnWholePixelsInEveryStateAndLevel(scale: Int) throws {
        for (bodyName, body) in BatteryGlyphRender.bodies {
            let o = BatteryGlyphRender.margin(body) * scale
            let g = BatteryGlyphRender.geometry(body, scale: scale)
            for (stateName, power, level) in BatteryGlyphRender.powers where power == .onBattery {
                for percent in BatteryGlyphRender.percents {
                    let ink = try BatteryGlyphRender.direct(body, percent: percent, power: power, level: level, scale: scale)
                    for edge in BatteryGlyphRender.edges(g, percent: percent, origin: (0, o)) {
                        let result = BatteryGlyphRender.soft(ink, edge.rect)
                        #expect(result.inked > 0, "\(bodyName) \(scale)x \(stateName) \(percent) % \(edge.name) : de l'encre dans la zone mesurée")
                        #expect(result.soft == 0, "\(bodyName) \(scale)x \(stateName) \(percent) % \(edge.name) : \(result.soft) pixels intermédiaires sur \(result.inked)")
                    }
                }
            }
        }
    }

    @Test(arguments: [1, 2, 3])
    func theEdgesAreAlsoOnWholePixelsWithIncreaseContrast(scale: Int) throws {
        for (bodyName, body) in BatteryGlyphRender.bodies {
            let o = BatteryGlyphRender.margin(body) * scale
            let g = BatteryGlyphRender.geometry(body, scale: scale, contrast: true)
            for percent in [0.0, 4, 50, 100] {
                let ink = try BatteryGlyphRender.direct(body, percent: percent, scale: scale, contrast: true)
                for edge in BatteryGlyphRender.edges(g, percent: percent, origin: (0, o)) {
                    let result = BatteryGlyphRender.soft(ink, edge.rect)
                    #expect(result.soft == 0 && result.inked > 0, "\(bodyName) \(scale)x \(percent) % \(edge.name) : \(result)")
                }
            }
        }
    }

    @Test(arguments: [1, 2, 3])
    func theMarksHaveStraightEdgesOnWholePixelsWhereTheyAreRectangles(scale: Int) throws {
        // La prise est faite de rectangles : son corps et le haut de ses dents sont des rangées et des colonnes entières. L'éclair a des arêtes en diagonale (lissage normal).
        for (bodyName, body) in BatteryGlyphRender.bodies {
            let o = BatteryGlyphRender.margin(body) * scale
            let g = BatteryGlyphRender.geometry(body, scale: scale)
            let ink = try BatteryGlyphRender.direct(body, percent: 0, power: .pluggedNotCharging, scale: scale)
            let plug = g.plugRects
            let main = plug[2]
            let inside = BatteryGlyphRender.soft(ink, PixelRect(x: main.x + 1, y: o + main.y + 1, width: main.width - 2, height: max(1, main.height - 2)))
            #expect(inside.soft == 0 && inside.inked > 0, "\(bodyName) \(scale)x, corps de la prise : \(inside)")
            let tooth = BatteryGlyphRender.soft(ink, PixelRect(x: plug[0].x, y: o + g.plugRect.y, width: plug[0].width, height: 1))
            #expect(tooth.soft == 0 && tooth.inked > 0, "\(bodyName) \(scale)x, haut d'une dent : \(tooth)")
        }
    }

    @Test(arguments: [1, 2, 3])
    func theViewRendersTheSameSharpPixelsThroughSwiftUI(scale: Int) throws {
        // Même mesure, mais à travers `Image(nsImage:)` et `ImageRenderer` : la vue ne rééchantillonne pas l'image dynamique.
        // L'encre de la vue est le jeton « texte de soutien » (opacité de 56 %) : mesure relative au pixel le plus opaque de chaque zone.
        for (bodyName, body) in BatteryGlyphRender.bodies {
            let o = BatteryGlyphRender.margin(body) * scale
            let g = BatteryGlyphRender.geometry(body, scale: scale)
            for dark in [false, true] {
                for percent in [4.0, 50, 100] {
                    let ink = try BatteryGlyphRender.swiftUI(body, percent: percent, scale: scale, dark: dark)
                    for edge in BatteryGlyphRender.edges(g, percent: percent, origin: (0, o)) {
                        let result = BatteryGlyphRender.soft(ink, edge.rect, relative: true)
                        #expect(result.soft == 0 && result.inked > 0, "\(bodyName) \(scale)x \(dark ? "sombre" : "clair") \(percent) % \(edge.name) : \(result)")
                    }
                }
            }
        }
    }

    @Test func theRenderedSizeMatchesTheGeometryAtEveryScale() throws {
        for (bodyName, body) in BatteryGlyphRender.bodies {
            for scale in 1...3 {
                let ink = try BatteryGlyphRender.direct(body, percent: 50, scale: scale)
                let size = BatteryPixelGeometry.imageSizePoints(bodyPoints: body, nubPoints: BatteryGlyphRender.nub(body))
                #expect(ink.width == Int(size.width) * scale && ink.height == Int(size.height) * scale, "\(bodyName) \(scale)x : \(ink.width) x \(ink.height)")
            }
        }
    }

    @Test func theDrawingIsNotAStretchedBitmapTheTwoXPixelsAreDrawnNotCopied() throws {
        for (bodyName, body) in BatteryGlyphRender.bodies {
            let one = try BatteryGlyphRender.direct(body, percent: 67, power: .charging, scale: 1)
            let two = try BatteryGlyphRender.direct(body, percent: 67, power: .charging, scale: 2)
            #expect(two.width == 2 * one.width && two.height == 2 * one.height)
            var different = 0
            for x in 0..<two.width { for y in 0..<two.height where abs(two.alpha(x, y) - one.alpha(x / 2, y / 2)) > 0.1 { different += 1 } }
            #expect(different > 20, "\(bodyName) : le bitmap 2x n'est pas le bitmap 1x agrandi (\(different) pixels diffèrent)")
        }
    }

    @Test func theOutlineIsOnePixelAtOneXTwoAtTwoXAndThreeWithIncreaseContrastAtTwoX() throws {
        for (bodyName, body) in BatteryGlyphRender.bodies {
            func run(_ scale: Int, contrast: Bool) throws -> Int {
                let ink = try BatteryGlyphRender.direct(body, percent: 0, scale: scale, contrast: contrast)
                let row = (BatteryGlyphRender.margin(body) * scale) + BatteryGlyphRender.geometry(body, scale: scale).body.height / 2
                return ink.opaqueRun(row: row, columns: 0..<(4 * scale)).count
            }
            #expect(try run(1, contrast: false) == 1 && run(2, contrast: false) == 2, "\(bodyName)")
            #expect(try run(1, contrast: true) == 2 && run(2, contrast: true) == 3, "\(bodyName) : « Augmenter le contraste » ajoute au moins un pixel")
        }
    }
}

// MARK: - Dans la vraie carte et le vrai onglet

/// La carte de l'aperçu et l'en-tête de l'onglet rendus tels que l'app les compose (`OverviewTab.batteryCard`, `BatteryTab.ring`), à 1x, 2x et 3x :
/// la position de l'icône dans la mise en page (HStack, ZStack, centrage) peut être fractionnaire ; l'icône doit rester nette.
@MainActor @Suite(.serialized) struct BatteryGlyphInContextTests {
    private func battery(_ percent: Double, power: BatteryPowerState) -> BatteryStats {
        BatteryStats(percent: percent, isCharging: power == .charging, isPluggedIn: power != .onBattery, isFullyCharged: false, minutesRemaining: nil, cycleCount: 1,
                     health: 1, designCapacity: nil, maxCapacity: nil, temperature: nil, batteryPower: nil, systemPower: nil, adapterWatts: nil)
    }

    private func render<V: View>(_ view: V, scale: Int, dark: Bool = false) throws -> GlyphInk {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = CGFloat(scale)
        return try GlyphInk(cg: try #require(renderer.cgImage), scale: CGFloat(scale))
    }

    /// L'alpha de l'icône SEULE : la carte a un fond translucide (quelques % d'opacité) sous l'icône ; l'alpha d'un pixel d'icône est celui qui, composé
    /// avec celui du fond (un pixel de la carte loin de l'icône et du titre), donne l'alpha lu.
    private func againstBackground(_ ink: GlyphInk, corner: (x: Int, y: Int)) throws -> GlyphInk {
        let bg = ink.alpha(corner.x, corner.y)
        var bytes = [UInt8](repeating: 0, count: ink.width * ink.height * 4)
        for y in 0..<ink.height { for x in 0..<ink.width {
            let a = max(0, (ink.alpha(x, y) - bg) / (1 - bg))
            bytes[(y * ink.width + x) * 4 + 3] = UInt8((min(1, a) * 255).rounded())
        } }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(width: ink.width, height: ink.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: ink.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return try GlyphInk(cg: image, scale: ink.scale)
    }

    /// Le coin haut gauche de l'encre dans une zone (en pixels) : l'origine du corps de l'icône.
    private func origin(of ink: GlyphInk, xs: Range<Int>, ys: Range<Int>) -> (x: Int, y: Int)? {
        var minX = Int.max, minY = Int.max
        for y in ys { for x in xs where ink.alpha(x, y) > 0.04 { minX = min(minX, x); minY = min(minY, y) } }
        return minX == Int.max ? nil : (minX, minY)
    }

    private func check(_ ink: GlyphInk, body: CGSize, percent: Double, scale: Int, area: (x: ClosedRange<Int>, y: ClosedRange<Int>), label: String) throws {
        let g = BatteryGlyphRender.geometry(body, scale: scale)
        let found = try #require(origin(of: ink, xs: area.x.lowerBound * scale..<(area.x.upperBound + 1) * scale, ys: area.y.lowerBound * scale..<(area.y.upperBound + 1) * scale), "\(label)")
        for edge in BatteryGlyphRender.edges(g, percent: percent, origin: found) {
            let result = BatteryGlyphRender.soft(ink, edge.rect, relative: true)
            #expect(result.soft == 0 && result.inked > 0, "\(label) \(scale)x \(percent) % \(edge.name) : \(result) (corps en \(found))")
        }
    }

    @Test(arguments: [1, 2, 3])
    func theOverviewCardIconIsSharpInTheRealCard(scale: Int) throws {
        for percent in [4.0, 20, 67, 100] {
            for dark in [false, true] {
                let card = OverviewTab.batteryCard(battery(percent, power: .onBattery), thresholds: PressureThresholds.default.battery).frame(width: 180)
                let ink = try againstBackground(try render(card, scale: scale, dark: dark), corner: (150 * scale, 14 * scale))
                try check(ink, body: BatteryGlyphGeometry.cardBody, percent: percent, scale: scale, area: (8...40, 8...30), label: "carte \(dark ? "sombre" : "claire")")
            }
        }
    }

    @Test(arguments: [1, 2, 3])
    func theBatteryTabIconIsSharpInTheRealRing(scale: Int) throws {
        for percent in [4.0, 20, 67, 100] {
            for dark in [false, true] {
                let gauge = BatteryTab().ring(battery(percent, power: .onBattery), thresholds: PressureThresholds.default.battery)
                let ink = try render(gauge, scale: scale, dark: dark)
                try check(ink, body: BatteryGlyphGeometry.tabBody, percent: percent, scale: scale, area: (30...80, 62...86), label: "onglet \(dark ? "sombre" : "clair")")
            }
        }
    }

    @Test(arguments: [false, true])
    func theCardDrawnByARealHostingViewIsSharpAtTheBackingScaleInLightAndDark(dark: Bool) throws {
        // Le chemin de `--snapshot` et de la vraie fenêtre : une vue AppKit qui héberge la carte, dessinée à l'échelle de l'écran de la machine (1x ou 2x).
        let width: CGFloat = 180
        let card = OverviewTab.batteryCard(battery(67, power: .onBattery), thresholds: PressureThresholds.default.battery).frame(width: width)
        let host = NSHostingView(rootView: card)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 120)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = host.appearance
        window.contentView = host
        for _ in 0..<4 { RunLoop.main.run(until: Date().addingTimeInterval(0.03)); host.layoutSubtreeIfNeeded() }
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let cg = try #require(rep.cgImage)
        let scale = Int((CGFloat(cg.width) / width).rounded())
        let raw = try GlyphInk(cg: cg, scale: CGFloat(scale))
        let ink = try againstBackground(raw, corner: (150 * scale, 14 * scale))
        try check(ink, body: BatteryGlyphGeometry.cardBody, percent: 67, scale: scale, area: (8...40, 8...30), label: "carte hébergée \(dark ? "sombre" : "claire")")
        // Le thème de la vue hôte, pas celui du système : l'encre est blanche en sombre, noire en clair.
        let outline = raw.pixel(10 * scale, 16 * scale)
        #expect(dark ? outline.r > 0.7 : outline.r < 0.3, "contour \(outline) en thème \(dark ? "sombre" : "clair")")
    }

    @Test func theCardKeepsItsLayoutSize() throws {
        // Le glyphe garde sa taille de mise en page : le corps plus le bout (au point entier), la hauteur du corps. Avant SL24 : 30,21 x 13 et 34,55 x 15.
        for (body, expected) in [(BatteryGlyphGeometry.cardBody, CGSize(width: 30, height: 13)), (BatteryGlyphGeometry.tabBody, CGSize(width: 35, height: 15))] {
            let renderer = ImageRenderer(content: BatteryGlyphImage(percent: 50, power: .charging, body: body))
            renderer.scale = 2
            let size = try #require(renderer.nsImage).size
            #expect(size == expected, "\(body) : \(size)")
            let old = BatteryGlyphGeometry(body: body).totalSize
            #expect(abs(size.width - old.width) < 0.5 && size.height == old.height, "à moins d'un demi-point de l'ancienne taille \(old)")
        }
    }

    @Test func theOverviewCardLayoutIsTheSameAsWithoutTheMarkMargin() throws {
        // Le repère déborde en haut et en bas SANS changer la hauteur de la carte : charge, prise et batterie normale ont la même taille.
        let sizes = try [BatteryPowerState.onBattery, .charging, .pluggedNotCharging].map { power -> CGSize in
            let renderer = ImageRenderer(content: OverviewTab.batteryCard(battery(67, power: power), thresholds: PressureThresholds.default.battery).frame(width: 180))
            return try #require(renderer.nsImage).size
        }
        #expect(Set(sizes.map(\.height)).count == 1 && Set(sizes.map(\.width)).count == 1, "\(sizes)")
    }
}

// MARK: - Clair, sombre, couleurs

@MainActor @Suite(.serialized) struct BatteryGlyphColourTests {
    private let scale = 2

    private func pixel(_ ink: GlyphInk, _ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double, a: Double) { ink.pixel(x, y) }

    @Test func theOutlineIsTheSupportingTextColourInLightAndDark() throws {
        for (bodyName, body) in BatteryGlyphRender.bodies {
            let g = BatteryGlyphRender.geometry(body, scale: scale)
            let y = BatteryGlyphRender.margin(body) * scale + g.body.height / 2
            for dark in [false, true] {
                let ink = try BatteryGlyphRender.swiftUI(body, percent: 50, scale: scale, dark: dark)
                let outline = pixel(ink, 0, y)
                let expected = DesignTokens.supportingTextColor(dark: dark, contrastIncreased: false).resolve(in: BatteryGlyphRender.environment(dark: dark))
                #expect(abs(outline.a - Double(expected.opacity)) < 0.02, "\(bodyName) \(dark ? "sombre" : "clair") : alpha \(outline.a)")
                #expect(abs(outline.r - Double(expected.red)) < 0.03 && abs(outline.g - Double(expected.green)) < 0.03 && abs(outline.b - Double(expected.blue)) < 0.03,
                        "\(bodyName) \(dark ? "sombre" : "clair") : \(outline), attendu \(expected)")
            }
        }
    }

    @Test func theLightAndTheDarkGlyphsAreNotTheSameImage() throws {
        let light = try BatteryGlyphRender.swiftUI(BatteryGlyphRender.cardBody, percent: 50, scale: scale, dark: false)
        let dark = try BatteryGlyphRender.swiftUI(BatteryGlyphRender.cardBody, percent: 50, scale: scale, dark: true)
        let a = light.pixel(0, BatteryGlyphRender.margin(BatteryGlyphRender.cardBody) * scale + 13), b = dark.pixel(0, BatteryGlyphRender.margin(BatteryGlyphRender.cardBody) * scale + 13)
        #expect(a.r < 0.1 && b.r > 0.9, "noir en clair, blanc en sombre")
    }

    @Test func theFillFollowsTheLevelColourAndTheOutlineKeepsTheBaseColour() throws {
        let body = BatteryGlyphRender.cardBody
        let g = BatteryGlyphRender.geometry(body, scale: scale)
        let o = BatteryGlyphRender.margin(body) * scale
        for dark in [false, true] {
            let environment = BatteryGlyphRender.environment(dark: dark)
            for (level, color) in [(PressureLevel.medium, Color.orange), (.high, .red), (.critical, PressureLevel.scarlet)] {
                let ink = try BatteryGlyphRender.swiftUI(body, percent: 60, level: level, scale: scale, dark: dark)
                let fill = pixel(ink, g.inner.x + 3, o + g.inner.y + g.inner.height / 2)
                let expected = color.resolve(in: environment)
                #expect(fill.a > 0.99 && abs(fill.r - Double(expected.red)) < 0.03 && abs(fill.g - Double(expected.green)) < 0.03 && abs(fill.b - Double(expected.blue)) < 0.03,
                        "\(level) \(dark ? "sombre" : "clair") : \(fill), attendu \(expected)")
                let outline = pixel(ink, g.body.width / 2, o)
                #expect(outline.a < 0.7, "le contour garde le jeton « texte de soutien » (56 %), pas la couleur du niveau : \(outline)")
            }
            // Niveau normal : le remplissage est de la couleur de base.
            let normal = try BatteryGlyphRender.swiftUI(body, percent: 60, scale: scale, dark: dark)
            let fill = pixel(normal, g.inner.x + 3, o + g.inner.y + g.inner.height / 2), outline = pixel(normal, g.body.width / 2, o)
            #expect(abs(fill.a - outline.a) < 0.02 && abs(fill.r - outline.r) < 0.03, "remplissage normal : \(fill), contour : \(outline)")
        }
    }

    @Test func theMarkIsInTheBaseColourAndTheNubToo() throws {
        let body = BatteryGlyphRender.cardBody
        let g = BatteryGlyphRender.geometry(body, scale: scale)
        let o = BatteryGlyphRender.margin(body) * scale
        let ink = try BatteryGlyphRender.swiftUI(body, percent: 0, power: .pluggedNotCharging, level: .high, scale: scale, dark: true)
        let centre = pixel(ink, g.plugRect.x + g.plugRect.width / 2, o + g.body.height / 2)
        #expect(centre.a > 0.5 && centre.r > 0.9 && centre.g > 0.9, "prise blanche en thème sombre, même à un niveau rouge : \(centre)")
        let nub = pixel(ink, g.nub.x + 1, o + g.body.height / 2)
        #expect(nub.a > 0.5 && nub.r > 0.9 && nub.g > 0.9, "bout de la couleur de base : \(nub)")
    }

    @Test func aTranslucentInkIsNotDoubledWhereTheMarkSitsOnTheFill() throws {
        // Les cartes dessinent avec le jeton « texte de soutien » (56 % d'opacité) : le repère creuse le remplissage ET le halo, puis se dessine seul.
        // Sous le repère il ne doit rester aucun remplissage (sinon l'encre se superpose : 0,56 + 0,56 x 0,44 = 0,80, un repère plus sombre que le reste).
        let translucent = LabelPalette(base: CGColor(gray: 0, alpha: 0.5), orange: BatteryGlyphRender.opaque.orange, red: BatteryGlyphRender.opaque.red,
                                       scarlet: BatteryGlyphRender.opaque.scarlet, white: BatteryGlyphRender.opaque.white)
        for (bodyName, body) in BatteryGlyphRender.bodies {
            for scale in 1...3 {
                let g = BatteryGlyphRender.geometry(body, scale: scale)
                let o = BatteryGlyphRender.margin(body) * scale
                for (mark, power) in [(BatteryGlyphMark.bolt, BatteryPowerState.charging), (.plug, .pluggedNotCharging)] {
                    let full = try BatteryGlyphRender.direct(body, percent: 100, power: power, scale: scale, palette: translucent)
                    let empty = try BatteryGlyphRender.direct(body, percent: 0, power: power, scale: scale, palette: translucent)
                    let box = g.markRect(mark)
                    var doubled = 0, same = 0
                    for x in box.x..<box.maxX { for y in (o + box.y)..<(o + box.maxY) {
                        let e = empty.alpha(x, y)
                        guard e > 0.45, e < 0.55, x > box.x, x < box.maxX - 1 else { continue }      // un pixel plein du repère sur la batterie vide
                        same += 1
                        if full.alpha(x, y) > 0.55 { doubled += 1 }
                    } }
                    #expect(same > 4 * scale, "\(bodyName) \(scale)x \(mark) : \(same) pixels pleins du repère")
                    #expect(doubled == 0, "\(bodyName) \(scale)x \(mark) : \(doubled) pixels du repère plus sombres sur le remplissage")
                    _ = g
                }
            }
        }
    }

    @Test func theMonochromePaletteGivesAnAlphaOnlyImage() throws {
        // Un seul jeu de couleurs : la palette noire opaque ne produit que du noir (alpha seul), comme pour une image modèle de la barre de menus.
        for (_, body) in BatteryGlyphRender.bodies {
            for power in [BatteryPowerState.charging, .pluggedNotCharging, .onBattery] {
                let ink = try BatteryGlyphRender.direct(body, percent: 50, power: power, scale: 2)
                for x in 0..<ink.width { for y in 0..<ink.height {
                    let p = ink.pixel(x, y)
                    if p.a > 0 { #expect(p.r < 0.01 && p.g < 0.01 && p.b < 0.01) }
                } }
            }
        }
    }

    @Test func thePaletteIsResolvedFromTheEnvironmentNotFromTheScreenOrTheCurrentAppearance() {
        let light = BatteryGlyphDrawing.palette(in: BatteryGlyphRender.environment(dark: false)), dark = BatteryGlyphDrawing.palette(in: BatteryGlyphRender.environment(dark: true))
        #expect(light.base != dark.base)
        #expect(light.color(for: .normal) == nil && light.color(for: .medium) != nil && light.color(for: .high) != nil && light.color(for: .critical) != nil)
        // La règle des niveaux est celle de la valeur à côté de l'icône : orange, rouge, écarlate, rien au niveau normal (`PressureLevel.color`).
        #expect(PressureLevel.normal.color == nil && PressureLevel.medium.color == .orange && PressureLevel.high.color == .red && PressureLevel.critical.color == PressureLevel.scarlet)
    }
}

// MARK: - Repères et remplissage lus en pixels (portés des tests SL21 du dessin SwiftUI)

@MainActor @Suite(.serialized) struct BatteryGlyphPixelTests {
    private let scale = 2

    private func fillRun(_ ink: GlyphInk, body: CGSize, scale: Int, contrast: Bool = false) -> [Int] {
        let g = BatteryGlyphRender.geometry(body, scale: scale, contrast: contrast)
        let row = BatteryGlyphRender.margin(body) * scale + g.inner.y + g.inner.height / 2
        return ink.opaqueRun(row: row, columns: g.inner.x..<g.inner.maxX)
    }

    @Test func theFillIsProportionalToTheLevelAndGrowsMonotonically() throws {
        for (bodyName, body) in BatteryGlyphRender.bodies {
            for scale in 1...3 {
                let g = BatteryGlyphRender.geometry(body, scale: scale)
                var previous = -1
                for percent in [0.0, 1, 4, 10, 25, 50, 67, 75, 90, 99, 100] {
                    let run = fillRun(try BatteryGlyphRender.direct(body, percent: percent, scale: scale), body: body, scale: scale)
                    #expect(run.count == g.fillWidth(percent: percent), "\(bodyName) \(scale)x \(percent) % : \(run.count) px lus, \(g.fillWidth(percent: percent)) attendus")
                    #expect(run.count >= previous)
                    if let first = run.first, let last = run.last { #expect(last - first + 1 == run.count && first == g.inner.x, "un seul tenant, depuis la gauche") }
                    previous = run.count
                }
            }
        }
    }

    @Test func aLevelOfOneToFourPercentShowsASliverAndOnlyOneHundredFillsTheInside() throws {
        for (bodyName, body) in BatteryGlyphRender.bodies {
            for scale in 1...3 {
                for percent in [1.0, 2, 3, 4] {
                    #expect(fillRun(try BatteryGlyphRender.direct(body, percent: percent, scale: scale), body: body, scale: scale).count >= scale, "\(bodyName) \(scale)x \(percent) %")
                }
                let full = fillRun(try BatteryGlyphRender.direct(body, percent: 100, scale: scale), body: body, scale: scale).count
                let almost = fillRun(try BatteryGlyphRender.direct(body, percent: 99, scale: scale), body: body, scale: scale).count
                #expect(full > almost, "\(bodyName) \(scale)x")
                #expect(fillRun(try BatteryGlyphRender.direct(body, percent: 0, scale: scale), body: body, scale: scale).isEmpty)
            }
        }
    }

    @Test func theOutlineAndTheNubAreAlwaysThereAndTheInsideIsEmptyAtZeroPercent() throws {
        for (bodyName, body) in BatteryGlyphRender.bodies {
            for scale in 1...3 {
                let g = BatteryGlyphRender.geometry(body, scale: scale)
                let ink = try BatteryGlyphRender.direct(body, percent: 0, scale: scale)
                let o = BatteryGlyphRender.margin(body) * scale, mid = o + g.body.height / 2
                #expect(ink.alpha(0, mid) > 0.99 && ink.alpha(g.body.width - 1, mid) > 0.99, "\(bodyName) \(scale)x : contour")
                #expect(ink.alpha(g.body.width / 2, o) > 0.99 && ink.alpha(g.body.width / 2, o + g.body.height - 1) > 0.99)
                #expect(ink.alpha(g.nub.x + 1, mid) > 0.99, "bout")
                #expect(ink.alpha(g.body.width / 2, mid) < 0.01, "vide à 0 %")
                // Au-dessus et au-dessous du corps : rien (pas de repère).
                #expect(ink.alpha(g.body.width / 2, o - 1) < 0.01 && ink.alpha(g.body.width / 2, o + g.body.height) < 0.01)
            }
        }
    }

    @Test func theMarkIsInkOnAnEmptyBatteryAndAHoleInTheFill() throws {
        for (bodyName, body) in BatteryGlyphRender.bodies {
            for scale in 1...3 {
                let g = BatteryGlyphRender.geometry(body, scale: scale)
                let o = BatteryGlyphRender.margin(body) * scale
                for (mark, power) in [(BatteryGlyphMark.bolt, BatteryPowerState.charging), (.plug, .pluggedNotCharging)] {
                    let plainEmpty = try BatteryGlyphRender.direct(body, percent: 0, scale: scale), markEmpty = try BatteryGlyphRender.direct(body, percent: 0, power: power, scale: scale)
                    let box = g.markRect(mark)
                    func inked(_ ink: GlyphInk) -> Int {
                        var n = 0
                        for x in box.x..<box.maxX { for y in (o + box.y)..<(o + box.maxY) where ink.alpha(x, y) > 0.5 { n += 1 } }
                        return n
                    }
                    #expect(inked(markEmpty) > inked(plainEmpty) + 6 * scale, "\(bodyName) \(scale)x \(mark) : de l'encre sur le vide")
                    let plainFull = try BatteryGlyphRender.direct(body, percent: 100, scale: scale), markFull = try BatteryGlyphRender.direct(body, percent: 100, power: power, scale: scale)
                    var cut = 0
                    for x in 0..<plainFull.width { for y in 0..<plainFull.height where plainFull.alpha(x, y) > 0.9 && markFull.alpha(x, y) < 0.1 { cut += 1 } }
                    #expect(cut >= 4 * scale, "\(bodyName) \(scale)x \(mark) : le halo est creusé dans le remplissage et le contour (\(cut) pixels)")
                }
            }
        }
    }

    @Test func theMarkOnlyChangesPixelsInsideItsBoxAndHalo() throws {
        for (bodyName, body) in BatteryGlyphRender.bodies {
            for scale in 1...3 {
                let g = BatteryGlyphRender.geometry(body, scale: scale)
                let o = BatteryGlyphRender.margin(body) * scale
                for (mark, power) in [(BatteryGlyphMark.bolt, BatteryPowerState.charging), (.plug, .pluggedNotCharging)] {
                    let box = g.markRect(mark)
                    let area = CGRect(x: box.x - g.haloWidth - 1, y: o + box.y - g.haloWidth - 1, width: box.width + 2 * g.haloWidth + 2, height: box.height + 2 * g.haloWidth + 2)
                    for percent in [0.0, 50, 100] {
                        let plain = try BatteryGlyphRender.direct(body, percent: percent, scale: scale), marked = try BatteryGlyphRender.direct(body, percent: percent, power: power, scale: scale)
                        var different = 0
                        for x in 0..<plain.width { for y in 0..<plain.height where abs(plain.alpha(x, y) - marked.alpha(x, y)) > 0.5 {
                            different += 1
                            #expect(area.contains(CGPoint(x: x, y: y)), "\(bodyName) \(scale)x \(mark) \(percent) % : un pixel change hors du repère (\(x), \(y))")
                        } }
                        #expect(different > 8 * scale, "\(bodyName) \(scale)x \(mark) \(percent) % : \(different) pixels de repère")
                    }
                }
            }
        }
    }

    @Test func theMarkReachesAboveAndBelowTheBodyAndIsNotClippedByTheImage() throws {
        for (bodyName, body) in BatteryGlyphRender.bodies {
            for scale in 1...3 {
                let g = BatteryGlyphRender.geometry(body, scale: scale)
                let o = BatteryGlyphRender.margin(body) * scale
                #expect(g.verticalOverflow <= o, "la marge de l'image contient le repère")
                for power in [BatteryPowerState.charging, .pluggedNotCharging] {
                    let ink = try BatteryGlyphRender.direct(body, percent: 0, power: power, scale: scale)
                    let rows = (0..<ink.height).filter { y in (0..<ink.width).contains { ink.alpha($0, y) > 0.5 } }
                    // Les pointes de l'éclair sont en diagonale : leur pixel n'est couvert qu'en partie, d'où le seuil bas.
                    let tall = (0..<ink.height).filter { y in (0..<ink.width).contains { ink.alpha($0, y) > 0.1 } }
                    #expect(tall.first! < o && tall.last! >= o + g.body.height, "\(bodyName) \(scale)x \(power) : le repère dépasse du corps en haut et en bas")
                    _ = rows
                    // Rien n'est coupé : le repère nominal (sa boîte) tient dans l'image, haut et bas.
                    #expect(o + g.markRect(power.mark!).y >= 0 && o + g.markRect(power.mark!).maxY <= ink.height, "\(bodyName) \(scale)x \(power)")
                }
            }
        }
    }

    @Test func increaseContrastThickensTheOutlineAndTheFillNeverTouchesIt() throws {
        for (bodyName, body) in BatteryGlyphRender.bodies {
            for scale in 1...3 {
                let normal = BatteryGlyphRender.geometry(body, scale: scale), strong = BatteryGlyphRender.geometry(body, scale: scale, contrast: true)
                #expect(strong.lineWidth > normal.lineWidth && strong.inner.x > normal.inner.x, "\(bodyName) \(scale)x")
                let ink = try BatteryGlyphRender.direct(body, percent: 100, scale: scale, contrast: true)
                let row = BatteryGlyphRender.margin(body) * scale + strong.body.height / 2
                // Entre le trait et le remplissage il reste au moins un pixel vide.
                #expect(ink.alpha(strong.lineWidth, row) < 0.1, "\(bodyName) \(scale)x : le jeu entre le trait et le remplissage")
                #expect(ink.alpha(strong.inner.x, row) > 0.99)
            }
        }
    }
}

// MARK: - Le code : une seule façon de dessiner

@MainActor @Suite struct BatteryGlyphSourceTests {
    private func read(_ path: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
    }

    @Test func theCardAndTheTabUseTheSharedImageView() throws {
        let overview = try read("Sources/Soaro/Views/OverviewTab.swift"), tab = try read("Sources/Soaro/Views/BatteryTab.swift")
        #expect(overview.contains("BatteryGlyphImage(") && tab.contains("BatteryGlyphImage("))
        #expect(!overview.contains("BatteryGlyph(") && !tab.contains("BatteryGlyph("), "l'ancienne vue SwiftUI n'est plus appelée")
        #expect(overview.contains("BatteryGlyphGeometry.cardBody") && tab.contains("BatteryGlyphGeometry.tabBody"))
    }

    @Test func theOldSwiftUIDrawingIsGone() throws {
        let source = try read("Sources/Soaro/Views/BatteryGlyph.swift")
        #expect(!source.contains("struct BatteryGlyph:"), "la vue SwiftUI à coordonnées fractionnaires n'existe plus")
        #expect(!source.contains("Canvas"), "plus de Canvas SwiftUI")
        for gone in ["UnevenRoundedRectangle", "RoundedRectangle(", "context.stroke(", "context.fill(", "strokedPath", "boltPath()", "plugPath()", "haloPath(", "roundedRect(", ".destinationOut"] {
            #expect(!source.contains(gone), "\(gone) : ce dessin vit dans LabelShapes, en pixels entiers")
        }
        #expect(!source.contains("static func fill(level") && !source.contains("static func outline(level"), "la règle des couleurs est dans LabelPalette")
    }

    @Test func theImageIsDynamicAndReadsTheScaleFromTheDrawingContext() throws {
        let source = try read("Sources/Soaro/Views/BatteryGlyph.swift")
        #expect(source.contains("NSImage(size: size, flipped: true)"), "une image dynamique : le dessin se refait à l'échelle de l'écran où elle s'affiche")
        #expect(source.contains("MenuBarRenderer.pixelScale(of: context)"), "l'échelle vient du contexte de dessin")
        #expect(!source.contains("NSScreen") && !source.contains("backingScaleFactor") && !source.contains("displayScale"), "jamais l'échelle d'un écran pris au hasard")
        #expect(source.contains("LabelShapes.drawBattery("), "le même dessin que le libellé de la barre de menus")
        let menu = try read("Sources/Soaro/Views/MenuBarLabelDrawer.swift")
        #expect(menu.contains("LabelShapes.drawBattery("))
    }

    @Test func theViewIsHiddenFromVoiceOverAndResolvesItsColoursFromTheEnvironment() throws {
        let source = try read("Sources/Soaro/Views/BatteryGlyph.swift")
        #expect(source.contains(".accessibilityHidden(true)"))
        #expect(source.contains("SupportingTextShapeStyle.color(in: environment)") && source.contains("@Environment(\\.colorSchemeContrast)"))
    }

    @Test func thereIsOnlyOneBatteryDrawingFunction() throws {
        let views = RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Views")
        let files = try FileManager.default.contentsOfDirectory(at: views, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        let drawing = try files.filter { try String(contentsOf: $0, encoding: .utf8).contains("static func drawBattery(") }
        #expect(drawing.map(\.lastPathComponent) == ["MenuBarLabelShapes.swift"])
    }

    @Test func theCardsAccessibilityIsUnchanged() throws {
        let components = try read("Sources/Soaro/Views/Components.swift")
        #expect(components.contains(".accessibilityElement(children: .combine)"))
        let tab = try read("Sources/Soaro/Views/BatteryTab.swift")
        #expect(tab.contains(".accessibilityElement(children: .ignore)") && tab.contains(".accessibilityLabel(\"Battery level\")"))
    }
}
