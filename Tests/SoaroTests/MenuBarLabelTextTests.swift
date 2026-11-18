import AppKit
import CoreText
import Foundation
import Testing
@testable import Soaro

/// SL23, étape 3 : le texte du libellé, dessiné avec Core Text. Géométrie pure d'abord (corps en pixels entiers, lignes de base entières,
/// chiffres de même chasse, largeurs mesurées), puis rendus hors écran lus en pixels à 1x, 2x et 3x.
@Suite struct LabelTextStyleTests {
    private static let all: [LabelTextStyle] = [.caption, .value, .rate, .line, .lineDigits]

    @Test func theNominalSizesAreTheOnesOfTheDesign() {
        #expect(LabelTextStyle.caption.points == 7.5 && LabelTextStyle.caption.weight == .medium && !LabelTextStyle.caption.monospacedDigits)
        #expect(LabelTextStyle.value.points == 12 && LabelTextStyle.value.weight == .semibold && LabelTextStyle.value.monospacedDigits)
        #expect(LabelTextStyle.rate.points == 9 && LabelTextStyle.rate.weight == .medium && LabelTextStyle.rate.monospacedDigits)
        #expect(LabelTextStyle.line.points == 13 && LabelTextStyle.line.weight == .regular && !LabelTextStyle.line.monospacedDigits)
        #expect(LabelTextStyle.lineDigits.points == 13 && LabelTextStyle.lineDigits.monospacedDigits)
    }

    @Test func theFontSizeIsAWholeNumberOfPixelsAtEveryScale() {
        for style in Self.all {
            for scale in 1...4 {
                let px = style.fontSize(scale: scale) * CGFloat(scale)
                #expect(PixelGrid.isWhole(px), "\(style.points) pt à \(scale)x : \(px) px")
                #expect(abs(px - style.points * CGFloat(scale)) <= 0.5 + 1e-9, "le corps reste à un demi-pixel de la valeur écrite")
            }
        }
        #expect(LabelTextStyle.caption.pixelSize(scale: 1) == 8 && LabelTextStyle.caption.pixelSize(scale: 2) == 15, "7,5 pt : 8 px en 1x, 15 px en 2x")
        #expect(LabelTextStyle.value.pixelSize(scale: 1) == 12 && LabelTextStyle.value.pixelSize(scale: 2) == 24)
        #expect(LabelTextStyle.rate.pixelSize(scale: 1) == 9)
    }

    @Test func theDigitsKeepTheirMonospacedFeature() {
        for scale in 1...3 {
            for style in [LabelTextStyle.value, .rate, .lineDigits] {
                let narrow = style.width(of: "11%", scale: scale), wide = style.width(of: "88%", scale: scale)
                #expect(abs(narrow - wide) < 0.01, "\(style.points) pt, \(scale)x : « 11% » et « 88% » ont la même largeur (\(narrow), \(wide))")
            }
        }
        // Et sans la fonction (le libellé), les largeurs diffèrent : la mesure n'est pas toujours constante.
        #expect(abs(LabelTextStyle.line.width(of: "iii", scale: 2) - LabelTextStyle.line.width(of: "WWW", scale: 2)) > 5)
    }

    @Test func theWidestWidthCoversEveryScaleAndIsWholePoints() {
        for style in Self.all {
            for text in ["CPU", "43%", "100%", "↓ 999 KB/s", "↑ 99 KB/s"] {
                let widest = style.widestWidth(of: text)
                for scale in 1...3 { #expect(CGFloat(widest) >= style.width(of: text, scale: scale) - 1e-9, "\(text) à \(scale)x") }
            }
        }
    }

    @Test func theMinimumWidthsOfTheItemsStillHoldInPixels() {
        // 40 pt pour « 100 % » à côté de l'icône, 54 pt pour le bloc réseau, 31 pt pour un bloc compact : le texte le plus large y tient.
        for scale in 1...3 {
            let s = CGFloat(scale)
            for percent in ["100%", "100\u{00A0}%", "100 %"] {
                #expect(LabelTextStyle.value.width(of: percent, scale: scale) <= CGFloat(MenuBarLabelLayout.batteryValueMinWidth), "\(percent) à \(scale)x : \(LabelTextStyle.value.width(of: percent, scale: scale))")
                #expect(CGFloat(LabelTextStyle.value.widthPixels(of: percent, scale: scale)) <= CGFloat(MenuBarLabelLayout.batteryValueMinWidth) * s)
            }
            #expect(LabelTextStyle.rate.width(of: "↓ 999 KB/s", scale: scale) <= CGFloat(MenuBarLabelLayout.pairMinWidth))
            #expect(LabelTextStyle.value.width(of: "99%", scale: scale) <= CGFloat(MenuBarLabelLayout.stackedMinWidth))
        }
    }
}

@Suite struct LabelTextLayoutTests {
    @Test func everyBaselineIsAWholePixelWithinAHalfPixelOfTheDesign() {
        let designs: [CGFloat] = [LabelTextLayout.captionBaseline, LabelTextLayout.valueBaseline, LabelTextLayout.batteryValueBaseline, LabelTextLayout.lineBaseline] + LabelTextLayout.rateBaselines
        for scale in 1...4 {
            for design in designs {
                let px = LabelTextLayout.baseline(design, scale: scale)
                #expect(abs(CGFloat(px) - design * CGFloat(scale)) <= 0.5 + 1e-9, "\(design) pt à \(scale)x : \(px) px")
            }
        }
        #expect(LabelTextLayout.baseline(6.5, scale: 1) == 7 && LabelTextLayout.baseline(6.5, scale: 2) == 13)
        #expect(LabelTextLayout.baseline(19.5, scale: 1) == 20 && LabelTextLayout.baseline(19.5, scale: 2) == 39)
    }

    @Test func theRateLinesAreElevenPointsApartAndTheCaptionIsAboveTheValue() {
        #expect(LabelTextLayout.rateBaselines == [8.5, 19.5])
        #expect(LabelTextLayout.captionBaseline < LabelTextLayout.valueBaseline - 8)
    }

    @Test func thePillIsWholePixelsInBothStylesAndGrowsToTheBottomOfTheLabel() {
        for scale in 1...3 {
            let compact = LabelTextLayout.pillBounds(compact: true, scale: scale), line = LabelTextLayout.pillBounds(compact: false, scale: scale)
            #expect(compact.bottom == 22 * scale && compact.top < compact.bottom)
            #expect(compact.bottom - compact.top >= 14 * scale - 1 && compact.bottom - compact.top <= 15 * scale)
            #expect(line.top == PixelGrid.px(3, scale: scale) && line.bottom == PixelGrid.px(19, scale: scale))
        }
    }
}

/// Le texte dessiné, lu en pixels. Les seuils viennent de la mesure : voir PLAN.md (SL23, étape 3).
@MainActor @Suite(.serialized) struct LabelTextRenderTests {
    private func label(_ items: [MenuBarItem], compact: Bool = true, scale: Int) throws -> GlyphInk {
        let image = try #require(MenuBarRenderer.image(severity: nil, compact: compact, items: items, darkBar: false, increasedContrast: false))
        return try GlyphInk(image: image, scale: CGFloat(scale))
    }

    private func edges(_ ink: GlyphInk, _ region: CGRect) throws -> SharpnessMetric.TextEdges {
        try #require(SharpnessMetric.textEdgeHardness(ink, region: region))
    }

    /// Les bords des textes à 1x : la première rangée du texte (le haut des lettres) pèse presque autant que la suivante, et le bas (la ligne de
    /// base) tombe sur une rangée de pixels. Avant SL23, le libellé de 7,5 pt n'atteignait que 0,37 en haut.
    @Test func theCompactTextEdgesAreHardAt1x() throws {
        let cpu = try label([.stacked(label: "CPU", value: "11%")], scale: 1)
        let caption = try edges(cpu, CGRect(x: 25, y: 0, width: 31, height: 8)), value = try edges(cpu, CGRect(x: 25, y: 9, width: 31, height: 13))
        #expect(caption.top >= 0.8 && caption.bottom >= 0.95, "libellé : \(caption)")
        #expect(value.top >= 0.7 && value.bottom >= 0.95, "valeur : \(value)")
        let rates = try label([.pair(top: "↑ 99 KB/s", bottom: "↓ 13 KB/s")], scale: 1)
        for (name, region) in [("haut", CGRect(x: 25, y: 0, width: 54, height: 11)), ("bas", CGRect(x: 25, y: 11, width: 54, height: 11))] {
            let e = try edges(rates, region)
            #expect(e.bottom >= 0.95, "débit \(name) : ligne de base sur une rangée entière, \(e)")
        }
    }

    @Test(arguments: [1, 2])
    func theBaselinesLandOnAWholePixelRowAtEveryScale(scale: Int) throws {
        let cpu = try label([.stacked(label: "CPU", value: "11%")], scale: scale)
        let rates = try label([.pair(top: "↑ 99 KB/s", bottom: "↓ 13 KB/s")], scale: scale)
        for (name, ink, region) in [("libellé", cpu, CGRect(x: 25, y: 0, width: 31, height: 8)), ("valeur", cpu, CGRect(x: 25, y: 9, width: 31, height: 13)),
                                    ("débit haut", rates, CGRect(x: 25, y: 0, width: 54, height: 11)), ("débit bas", rates, CGRect(x: 25, y: 11, width: 54, height: 11))] {
            let e = try edges(ink, region)
            #expect(e.bottom >= 0.75, "\(name), \(scale)x : \(e)")
        }
    }

    @Test(arguments: [1, 2, 3])
    func theLowestInkRowOfEachTextIsItsBaselineRow(scale: Int) throws {
        // « CPU » et « 11% » : la ligne la plus basse de l'encre est la ligne de base (au débord rond des lettres près), jamais une demi-rangée plus bas.
        let ink = try label([.stacked(label: "CPU", value: "11%")], scale: scale)
        func lowestInkRow(_ region: CGRect) -> Int? {
            let p = SharpnessMetric.pixels(of: region, scale: ink.scale, in: ink)
            return p.ys.last { y in p.xs.contains { ink.alpha($0, y) > 0.3 } }
        }
        let captionBaseline = LabelTextLayout.baseline(LabelTextLayout.captionBaseline, scale: scale)
        let valueBaseline = LabelTextLayout.baseline(LabelTextLayout.valueBaseline, scale: scale)
        let caption = try #require(lowestInkRow(CGRect(x: 25, y: 0, width: 31, height: 8)))
        let value = try #require(lowestInkRow(CGRect(x: 25, y: 9, width: 31, height: 13)))
        #expect((captionBaseline - 1)...captionBaseline ~= caption, "libellé : ligne \(caption), ligne de base \(captionBaseline), \(scale)x")
        #expect((valueBaseline - 1)...valueBaseline ~= value, "valeur : ligne \(value), ligne de base \(valueBaseline), \(scale)x")
    }

    @Test(arguments: [1, 2, 3])
    func eachTextStartsOnItsSnappedColumn(scale: Int) throws {
        // Le bloc compact : « CPU » est centré dans 31 pt, sur un pixel entier : sa première colonne d'encre ne bouge pas d'une valeur à l'autre.
        let a = try label([.stacked(label: "CPU", value: "11%")], scale: scale), b = try label([.stacked(label: "CPU", value: "99%")], scale: scale)
        func firstColumn(_ ink: GlyphInk) -> Int? {
            let p = SharpnessMetric.pixels(of: CGRect(x: 25, y: 0, width: 31, height: 8), scale: ink.scale, in: ink)
            return p.xs.first { x in p.ys.contains { ink.alpha(x, $0) > 0.2 } }
        }
        #expect(firstColumn(a) == firstColumn(b), "le libellé ne bouge pas quand la valeur change")
        #expect(firstColumn(a) != nil)
    }

    @Test func theFlagIsInColourAndCentredInTheLabelAtEveryScale() throws {
        for scale in 1...3 {
            let ink = try label([.flag(countryCode: "FR")], scale: scale)
            // La zone du drapeau : à droite du glyphe (16 pt) et de l'espace de 9 pt.
            let region = CGRect(x: 25, y: 0, width: 18, height: 22)
            let p = SharpnessMetric.pixels(of: region, scale: ink.scale, in: ink)
            var minY = Int.max, maxY = -1, coloured = 0
            for y in p.ys { for x in p.xs {
                let c = ink.pixel(x, y)
                if c.a > 0.5 { minY = min(minY, y); maxY = max(maxY, y) }
                if c.a > 0.5 && (max(c.r, c.g, c.b) - min(c.r, c.g, c.b)) > 0.25 { coloured += 1 }
            } }
            #expect(coloured > 40 * scale, "le drapeau garde ses couleurs, \(scale)x : \(coloured)")
            let centre = (CGFloat(minY) + CGFloat(maxY + 1)) / 2 / CGFloat(scale)
            #expect(abs(centre - 10.5) <= 1.0, "centré à 10,5 pt du haut, \(scale)x : \(centre)")
        }
    }

    @Test func theCriticalValueIsWhiteOnAScarletPillAtEveryScale() throws {
        for scale in 1...3 {
            let ink = try label([.stacked(label: "SSD", value: "97%", level: .critical)], scale: scale)
            let pill = try #require(SharpnessMetric.bounds(of: ink) { $0.a > 0.5 && $0.r > 0.9 && $0.g < 0.3 && $0.b < 0.1 })
            #expect(abs(pill.maxY - 22) <= 0.5 / CGFloat(scale) + 1e-9, "la pastille va jusqu'au bas du libellé, \(scale)x")
            #expect(pill.height >= 13.5 && pill.height <= 15, "\(scale)x : \(pill)")
            // Du blanc dans la pastille : le texte.
            var white = 0
            let p = SharpnessMetric.pixels(of: pill, scale: ink.scale, in: ink)
            for y in p.ys { for x in p.xs { let c = ink.pixel(x, y); if c.a > 0.9 && c.r > 0.9 && c.g > 0.9 && c.b > 0.9 { white += 1 } } }
            #expect(white > 20 * scale, "texte blanc, \(scale)x : \(white)")
        }
    }

    @Test func theLabelNeverUsesSwiftUITextOrAnImageRenderer() throws {
        for path in ["Sources/Soaro/Views/MenuBarWidgets.swift", "Sources/Soaro/Views/MenuBarLabelDrawer.swift", "Sources/Soaro/Views/MenuBarLabelText.swift", "Sources/Soaro/Views/MenuBarLabelShapes.swift"] {
            let text = try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
            let code = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            #expect(!code.contains("ImageRenderer") && code.range(of: "\\bText\\(", options: .regularExpression) == nil && !code.contains("MenuBarWidgetsView"), "\(path)")
        }
        let drawer = try String(contentsOf: RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Views/MenuBarLabelText.swift"), encoding: .utf8)
        #expect(drawer.contains("CTLineDraw"))
    }
}
