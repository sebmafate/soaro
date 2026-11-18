import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Soaro

/// SL21 : l'icône de batterie « comme celle de macOS » (contour, bout, remplissage continu, éclair en charge).
/// Ici : la géométrie pure, la règle des couleurs et le rendu hors écran du glyphe lu en pixels. La vraie barre de menus (teinte réelle, Mac à encoche) se vérifie à la main.

// MARK: Géométrie pure

@Suite struct BatteryGlyphGeometryTests {
    /// Le corps de la barre de menus : 20 x 9,5 pt, trait de 1,2 pt, jeu de 0,8 pt : l'intérieur fait 16 x 5,5 pt.
    private let bar = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)

    @Test func theSizesAreTheOnesWrittenInTheDesign() {
        #expect(BatteryGlyphGeometry.menuBarBody == CGSize(width: 20, height: 9.5))
        #expect(BatteryGlyphGeometry.cardBody == CGSize(width: 28, height: 13))
        #expect(BatteryGlyphGeometry.tabBody == CGSize(width: 32, height: 15))
        #expect(BatteryGlyphGeometry.lineWidth(increasedContrast: false) == 1.2)
        #expect(BatteryGlyphGeometry.lineWidth(increasedContrast: true) == 1.5)
        #expect(BatteryGlyphGeometry.gap == 0.8)
        #expect(BatteryGlyphGeometry.minSliver == 1)
        #expect(BatteryGlyphGeometry.step == 0.5)
    }

    @Test func theInnerRectIsTheBodyInsetByTheLineAndTheGap() {
        #expect(bar.innerRect == CGRect(x: 2, y: 2, width: 16, height: 5.5))
        let tight = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody, increasedContrast: true)
        #expect(abs(tight.innerRect.minX - 2.3) < 1e-9, "trait de 1,5 pt : le remplissage recule, il ne touche jamais le contour")
        #expect(abs(tight.innerRect.width - 15.4) < 1e-9)
    }

    @Test func theNubSitsAtTheRightOfTheBodyAndIsCentredVertically() {
        #expect(bar.nubRect.minX == bar.bodyRect.maxX)
        #expect(abs(bar.nubRect.midY - bar.bodyRect.midY) < 1e-9)
        #expect(bar.nubRect.height < bar.bodyRect.height / 2 + 0.01)
        #expect(bar.totalSize == CGSize(width: bar.bodyRect.width + bar.nubRect.width, height: 9.5))
    }

    @Test func fullIsTheExactInnerWidthAndEmptyIsZero() {
        #expect(bar.fillWidth(percent: 100) == bar.innerRect.width)
        #expect(bar.fillWidth(percent: 0) == 0)
    }

    @Test func thePercentIsClampedAndNotANumberIsEmpty() {
        #expect(bar.fillWidth(percent: -20) == 0)
        #expect(bar.fillWidth(percent: 100.4) == bar.innerRect.width)
        #expect(bar.fillWidth(percent: 250) == bar.innerRect.width)
        #expect(bar.fillWidth(percent: .nan) == 0)
        #expect(bar.fillWidth(percent: .infinity) == bar.innerRect.width)
        #expect(bar.fillWidth(percent: -.infinity) == 0)
    }

    @Test func aLowLevelStillShowsASliverOfAtLeastOnePoint() {
        for percent in [0.1, 1, 2, 3, 4, 5] as [Double] {
            #expect(bar.fillWidth(percent: percent) >= BatteryGlyphGeometry.minSliver, "\(percent) %")
        }
        #expect(bar.fillWidth(percent: 1) == 1, "1 % de 16 pt = 0,16 pt : relevé au minimum de 1 pt")
    }

    @Test func theWidthIsRoundedToHalfAPointWhichIsOnePixelAtTwoX() {
        // 16 pt x p / 100, arrondi au demi-point le plus proche.
        #expect(bar.fillWidth(percent: 50) == 8)
        #expect(bar.fillWidth(percent: 67) == 10.5, "10,72 pt")
        #expect(bar.fillWidth(percent: 20) == 3, "3,2 pt")
        #expect(bar.fillWidth(percent: 33) == 5.5, "5,28 pt")
        #expect(bar.fillWidth(percent: 90) == 14.5, "14,4 pt")
        for percent in stride(from: 1.0, to: 100.0, by: 1.0) {
            let w = bar.fillWidth(percent: percent)
            #expect((w / BatteryGlyphGeometry.step).rounded() == w / BatteryGlyphGeometry.step, "\(percent) % : \(w) n'est pas un multiple de 0,5")
        }
    }

    @Test func ninetyNineIsNeverDrawnAsFull() {
        // 99 % de 16 pt = 15,84 pt s'arrondirait à 16 pt : on garde un demi-point de moins pour que seul 100 % soit plein.
        #expect(bar.fillWidth(percent: 99) == bar.innerRect.width - BatteryGlyphGeometry.step)
        #expect(bar.fillWidth(percent: 99.9) < bar.innerRect.width)
    }

    @Test func theWidthNeverShrinksWhenThePercentGrows() {
        for body in [BatteryGlyphGeometry.menuBarBody, BatteryGlyphGeometry.cardBody, BatteryGlyphGeometry.tabBody] {
            for contrast in [false, true] {
                let g = BatteryGlyphGeometry(body: body, increasedContrast: contrast)
                var previous: CGFloat = -1
                for tenth in 0...1000 {
                    let w = g.fillWidth(percent: Double(tenth) / 10)
                    #expect(w >= previous, "\(Double(tenth) / 10) % sur \(body)")
                    #expect(w <= g.innerRect.width)
                    previous = w
                }
            }
        }
    }

    @Test func theFillRectStaysInsideTheInnerRectAndStartsOnTheLeft() {
        for percent in [0.0, 1, 33, 67, 99, 100] {
            let r = bar.fillRect(percent: percent)
            #expect(r.minX == bar.innerRect.minX)
            #expect(r.minY == bar.innerRect.minY && r.height == bar.innerRect.height)
            #expect(r.maxX <= bar.innerRect.maxX + 1e-9)
        }
    }

    @Test func theBoltFitsInsideTheBodyAndIsCentred() {
        let box = bar.boltRect
        #expect(bar.bodyRect.contains(box))
        #expect(abs(box.midX - bar.bodyRect.midX) < 1e-9 && abs(box.midY - bar.bodyRect.midY) < 1e-9)
        let points = BatteryGlyphGeometry.boltPoints
        #expect(points.count == 6)
        #expect(points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) }, "le contour de l'éclair est dans le carré unité")
        #expect(points.map(\.y).min() == 0 && points.map(\.y).max() == 1)
    }

    @Test func theSameGlyphScalesToTheCardAndTheTab() {
        let card = BatteryGlyphGeometry(body: BatteryGlyphGeometry.cardBody)
        #expect(abs(card.innerRect.width - 24) < 1e-9)
        #expect(abs(card.fillWidth(percent: 100) - 24) < 1e-9)
        #expect(card.totalSize.height == 13)
        let tab = BatteryGlyphGeometry(body: BatteryGlyphGeometry.tabBody)
        #expect(tab.totalSize.height == 15 && tab.totalSize.width > 32)
    }
}

// MARK: Couleurs

@Suite struct BatteryGlyphColorTests {
    @Test func theFillFollowsTheLevelColourAndTheBaseColourWhenNormal() {
        #expect(BatteryGlyphColors.fill(level: .normal, base: .black) == .black)
        #expect(BatteryGlyphColors.fill(level: .normal, base: .white) == .white)
        #expect(BatteryGlyphColors.fill(level: .medium, base: .white) == .orange)
        #expect(BatteryGlyphColors.fill(level: .high, base: .black) == .red)
        #expect(BatteryGlyphColors.fill(level: .critical, base: .white) == PressureLevel.scarlet)
    }

    @Test func theOutlineAndTheNubAlwaysKeepTheBaseColour() {
        for level in [PressureLevel.normal, .medium, .high, .critical] {
            #expect(BatteryGlyphColors.outline(level: level, base: .white) == .white)
            #expect(BatteryGlyphColors.outline(level: level, base: .black) == .black)
        }
    }
}

// MARK: Rendus hors écran

/// Pixels d'une image, lus à l'échelle demandée (RGBA non prémultiplié).
struct GlyphInk {
    let width: Int, height: Int
    let scale: CGFloat
    private let data: [UInt8]

    init(cg: CGImage, scale: CGFloat) throws {
        width = cg.width; height = cg.height; self.scale = scale
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        data = buffer
    }

    /// Image d'une image AppKit (le libellé de la barre de menus), à l'échelle 2.
    init(image: NSImage) throws {
        var rect = CGRect(origin: .zero, size: CGSize(width: image.size.width * 2, height: image.size.height * 2))
        let cg = try #require(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        try self.init(cg: cg, scale: CGFloat(cg.width) / image.size.width)
    }

    func pixel(_ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double, a: Double) {
        guard x >= 0, y >= 0, x < width, y < height else { return (0, 0, 0, 0) }
        let i = (y * width + x) * 4
        let a = Double(data[i + 3]) / 255
        guard a > 0 else { return (0, 0, 0, 0) }
        return (Double(data[i]) / 255 / a, Double(data[i + 1]) / 255 / a, Double(data[i + 2]) / 255 / a, a)
    }

    func alpha(_ x: Int, _ y: Int) -> Double { pixel(x, y).a }

    /// Colonnes (en pixels) où la ligne `y` est opaque, dans `columns`.
    func opaqueRun(row y: Int, columns: Range<Int>) -> [Int] {
        columns.filter { alpha($0, y) > 0.5 }
    }

    /// Nombre de pixels opaques dans un rectangle (en points, origine en haut à gauche).
    func opaqueCount(in rect: CGRect, origin: CGPoint = .zero) -> Int {
        let x0 = Int(((rect.minX + origin.x) * scale).rounded()), x1 = Int(((rect.maxX + origin.x) * scale).rounded())
        let y0 = Int(((rect.minY + origin.y) * scale).rounded()), y1 = Int(((rect.maxY + origin.y) * scale).rounded())
        var n = 0
        for x in x0..<x1 { for y in y0..<y1 where alpha(x, y) > 0.5 { n += 1 } }
        return n
    }

    func clearCount(in rect: CGRect) -> Int {
        let x0 = Int((rect.minX * scale).rounded()), x1 = Int((rect.maxX * scale).rounded())
        let y0 = Int((rect.minY * scale).rounded()), y1 = Int((rect.maxY * scale).rounded())
        var n = 0
        for x in x0..<x1 { for y in y0..<y1 where alpha(x, y) < 0.1 { n += 1 } }
        return n
    }
}

@MainActor @Suite(.serialized) struct BatteryGlyphRenderTests {
    private static let scale: CGFloat = 4

    /// Le glyphe seul, sur fond transparent, à l'échelle 4 (un pixel = 0,25 pt).
    private func glyph(percent: Double, charging: Bool = false, level: PressureLevel = .normal, base: Color = .black,
                       body: CGSize = BatteryGlyphGeometry.menuBarBody, contrast: Bool = false) throws -> GlyphInk {
        let view = BatteryGlyph(percent: percent, charging: charging, level: level, base: base, body: body, increasedContrast: contrast)
        let renderer = ImageRenderer(content: view)
        renderer.scale = Self.scale
        return try GlyphInk(cg: try #require(renderer.cgImage), scale: Self.scale)
    }

    private func fillRun(_ ink: GlyphInk, body: CGSize = BatteryGlyphGeometry.menuBarBody, contrast: Bool = false) -> [Int] {
        let g = BatteryGlyphGeometry(body: body, increasedContrast: contrast)
        let row = Int((g.innerRect.midY * Self.scale).rounded())
        let lo = Int((g.innerRect.minX * Self.scale).rounded()), hi = Int((g.innerRect.maxX * Self.scale).rounded())
        return ink.opaqueRun(row: row, columns: lo..<hi)
    }

    @Test func theGlyphFrameIsTheBodyPlusTheNub() throws {
        let renderer = ImageRenderer(content: BatteryGlyph(percent: 50, charging: false, level: .normal, base: .black, body: BatteryGlyphGeometry.menuBarBody))
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        #expect(abs(image.size.width - g.totalSize.width) < 0.01 && abs(image.size.height - g.totalSize.height) < 0.01)
    }

    // MARK: remplissage proportionnel

    @Test(arguments: [10.0, 50.0, 90.0, 100.0])
    func theFillWidthIsProportionalToTheLevel(percent: Double) throws {
        let ink = try glyph(percent: percent)
        let run = fillRun(ink)
        let expected = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody).fillWidth(percent: percent) * Self.scale
        #expect(abs(Double(run.count) - Double(expected)) <= 1.5, "\(percent) % : \(run.count) px lus, \(expected) px attendus")
        // Le remplissage est d'un seul tenant et part de la gauche.
        if let first = run.first, let last = run.last { #expect(last - first + 1 == run.count) }
        #expect(run.first.map { Double($0) / Double(Self.scale) } ?? 99 <= 2.0 + 0.3)
    }

    @Test func fillGrowsWithTheLevel() throws {
        var previous = -1
        for percent in [0.0, 1, 5, 10, 25, 50, 75, 90, 99, 100] {
            let n = fillRun(try glyph(percent: percent)).count
            #expect(n >= previous, "\(percent) %")
            previous = n
        }
        #expect(fillRun(try glyph(percent: 0)).isEmpty)
    }

    @Test func aLevelOfOneToFourPercentStillShowsASliver() throws {
        for percent in [1.0, 2, 3, 4] {
            #expect(fillRun(try glyph(percent: percent)).count >= Int(BatteryGlyphGeometry.minSliver * Self.scale) - 1, "\(percent) %")
        }
    }

    @Test func onlyAFullBatteryFillsTheWholeInside() throws {
        let full = fillRun(try glyph(percent: 100)).count
        let almost = fillRun(try glyph(percent: 99)).count
        #expect(full > almost)
    }

    @Test func theOutlineAndTheNubAreAlwaysThereEvenOnAnEmptyBattery() throws {
        let ink = try glyph(percent: 0)
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        // Ligne du milieu : le contour à gauche, rien à l'intérieur, le contour à droite, puis le bout.
        let row = Int((g.bodyRect.midY * Self.scale).rounded())
        #expect(ink.alpha(1, row) > 0.5, "contour gauche")
        #expect(ink.alpha(Int(g.bodyRect.maxX * Self.scale) - 2, row) > 0.5, "contour droit")
        #expect(ink.alpha(Int((g.nubRect.midX) * Self.scale), row) > 0.5, "bout")
        #expect(ink.opaqueCount(in: g.innerRect) == 0, "rien à l'intérieur à 0 %")
        // Le bout n'est pas plus haut que la moitié du corps.
        let nubColumn = Int(g.nubRect.midX * Self.scale)
        let nubPixels = (0..<ink.height).filter { ink.alpha(nubColumn, $0) > 0.5 }.count
        #expect(Double(nubPixels) / Double(Self.scale) <= g.bodyRect.height / 2 + 0.5)
    }

    // MARK: éclair

    @Test func noBoltWhenNotChargingAndABoltWhenCharging() throws {
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        for percent in [0.0, 50, 100] {
            let plain = try glyph(percent: percent), charging = try glyph(percent: percent, charging: true)
            var different = 0
            for x in 0..<plain.width { for y in 0..<plain.height where abs(plain.alpha(x, y) - charging.alpha(x, y)) > 0.5 { different += 1 } }
            // L'éclair mesure environ 3,5 x 6 pt : au moins quelques dizaines de pixels à l'échelle 4.
            #expect(different > 25, "\(percent) % : \(different) pixels de différence")
            // Rien ne change hors du corps : le contour et le bout restent identiques.
            let outside = (0..<plain.width).flatMap { x in (0..<plain.height).map { (x, $0) } }.filter { x, y in
                !g.boltRect.insetBy(dx: -1.5, dy: -1.5).contains(CGPoint(x: Double(x) / Double(Self.scale), y: Double(y) / Double(Self.scale)))
            }
            #expect(outside.allSatisfy { abs(plain.alpha($0.0, $0.1) - charging.alpha($0.0, $0.1)) < 0.5 }, "\(percent) % : l'éclair déborde de sa zone")
        }
    }

    @Test func theBoltIsVisibleInAMonochromeImageOnAnEmptyAndOnAFullBattery() throws {
        // Image modèle : seul l'alpha compte. Sur une batterie vide, l'éclair est de l'encre là où il n'y avait rien ;
        // sur une batterie pleine, c'est un trou transparent dans l'encre du remplissage.
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        let emptyPlain = try glyph(percent: 0), emptyBolt = try glyph(percent: 0, charging: true)
        #expect(emptyBolt.opaqueCount(in: g.boltRect) > emptyPlain.opaqueCount(in: g.boltRect) + 20)
        let fullPlain = try glyph(percent: 100), fullBolt = try glyph(percent: 100, charging: true)
        #expect(fullBolt.clearCount(in: g.innerRect) > fullPlain.clearCount(in: g.innerRect) + 25, "le trou en forme d'éclair se voit dans le remplissage")
        #expect(fullBolt.opaqueCount(in: g.boltRect) < fullPlain.opaqueCount(in: g.boltRect), "il y a moins d'encre là où est l'éclair")
    }

    @Test func theBoltNeverEatsTheOutline() throws {
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        let plain = try glyph(percent: 100), charging = try glyph(percent: 100, charging: true)
        let top = Int(g.bodyRect.midX * Self.scale)
        for y in 0..<Int(g.lineWidth * Self.scale) - 1 {
            #expect(abs(plain.alpha(top, y) - charging.alpha(top, y)) < 0.2, "ligne \(y) du contour haut")
        }
    }

    // MARK: couleurs, barre claire et sombre

    @Test func aNormalBatteryIsPureInkOfTheBaseColour() throws {
        for base in [Color.black, .white] {
            let ink = try glyph(percent: 60, charging: true, base: base)
            let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
            let p = ink.pixel(Int(g.innerRect.minX * Self.scale) + 3, Int(g.innerRect.midY * Self.scale))
            let expected = base == .white ? 1.0 : 0.0
            #expect(p.a > 0.9 && abs(p.r - expected) < 0.1 && abs(p.g - expected) < 0.1 && abs(p.b - expected) < 0.1, "remplissage en couleur de base")
        }
    }

    @Test(arguments: [(PressureLevel.medium, 1.0, 0.5, 0.0), (.high, 1.0, 0.2, 0.2), (.critical, 1.0, 0.14, 0.0)])
    func aColouredLevelColoursTheFillButNotTheOutline(level: PressureLevel, r: Double, g gg: Double, b: Double) throws {
        for base in [Color.black, .white] {
            let ink = try glyph(percent: 40, level: level, base: base)
            let geo = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
            let fill = ink.pixel(Int(geo.innerRect.minX * Self.scale) + 3, Int(geo.innerRect.midY * Self.scale))
            #expect(fill.a > 0.9)
            #expect(abs(fill.r - r) < 0.15 && abs(fill.g - gg) < 0.3 && abs(fill.b - b) < 0.3, "remplissage \(level) : \(fill)")
            let outline = ink.pixel(2, Int(geo.bodyRect.midY * Self.scale))
            let expected = base == .white ? 1.0 : 0.0
            #expect(outline.a > 0.9 && abs(outline.r - expected) < 0.1 && abs(outline.g - expected) < 0.1, "contour de la couleur de base")
        }
    }

    // MARK: Accessibilité : contraste renforcé

    @Test func increaseContrastThickensTheOutline() throws {
        let g1 = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        let row = Int(g1.bodyRect.midY * Self.scale)
        func leftOutline(_ contrast: Bool) throws -> Int {
            let ink = try glyph(percent: 0, contrast: contrast)
            return ink.opaqueRun(row: row, columns: 0..<Int(4 * Self.scale)).count
        }
        let normal = try leftOutline(false), strong = try leftOutline(true)
        #expect(strong > normal, "\(strong) px contre \(normal) px")
        #expect(abs(Double(normal) - 1.2 * Double(Self.scale)) <= 1.5)
        #expect(abs(Double(strong) - 1.5 * Double(Self.scale)) <= 1.5)
    }
}

