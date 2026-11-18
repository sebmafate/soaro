import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Soaro

/// SL23, étape 3 : la mise en page du libellé en points entiers, et les images qui en sortent à chaque échelle.
@MainActor @Suite(.serialized) struct MenuBarLabelLayoutTests {
    private static let cpu = MenuBarItem.stacked(label: "CPU", value: "43%")
    private static let ram = MenuBarItem.stacked(label: "RAM", value: "61%")
    private static let pair = MenuBarItem.pair(top: "↑ 99 KB/s", bottom: "↓ 13 KB/s")
    private static let flag = MenuBarItem.flag(countryCode: "FR")
    private static func battery(_ percent: Int) -> MenuBarItem { .battery(percent: percent, power: .onBattery) }

    private func layout(_ items: [MenuBarItem], compact: Bool = true, severity: Severity? = nil) -> MenuBarLabelLayout {
        MenuBarLabelLayout(items: items, compact: compact, severity: severity)
    }

    @Test func theBrandAloneIsSixteenPointsAndTheBadgeAddsItsOwnWidth() {
        #expect(layout([]).widthPoints == 16 && layout([]).blocks.isEmpty)
        #expect(layout([], severity: .warning).widthPoints == 22)
        #expect(layout([], severity: .critical).widthPoints == 28)
        #expect(layout([Self.cpu], severity: .warning).blocks[0].x == 22 + 9, "les blocs suivent le badge")
    }

    @Test func theBlocksFollowEachOtherInWholePointsWithTheStyleSpacing() {
        for compact in [true, false] {
            let l = layout([Self.cpu, Self.ram, Self.pair, Self.flag, Self.battery(67)], compact: compact)
            let spacing = MenuBarLabelLayout.spacing(compact: compact)
            #expect(spacing == (compact ? 9 : 6))
            var x = l.brandWidth
            for block in l.blocks {
                #expect(block.x == x + spacing && block.width > 0)
                x = block.x + block.width
            }
            #expect(l.widthPoints == x)
        }
    }

    @Test func theMinimumWidthsOfTheCompactBlocksHold() {
        #expect(layout([Self.cpu]).blocks[0].width == 31)
        #expect(layout([.stacked(label: "CPU", value: "9%")]).blocks[0].width == 31)
        #expect(layout([.stacked(label: "CPU", value: "100%")]).blocks[0].width >= 31, "« 100% » élargit le bloc au besoin")
        #expect(layout([Self.pair]).blocks[0].width == 54)
        #expect(layout([.pair(top: "↑ 999 KB/s", bottom: "↓ 999 KB/s")]).blocks[0].width == 54, "54 pt tiennent « ↓ 999 KB/s »")
        #expect(MenuBarLabelLayout.batteryMinWidth == 65 && layout([Self.battery(9)]).blocks[0].width == 65)
    }

    @Test func theBatteryBlockDoesNotChangeBetween9And100Percent() {
        #expect(Set([0, 9, 50, 100].map { layout([Self.battery($0)]).blocks[0].width }).count == 1)
        for power in [BatteryPowerState.onBattery, .charging, .pluggedNotCharging] {
            #expect(layout([.battery(percent: 67, power: power)]).blocks[0].width == 65, "l'état ne change pas la place")
        }
    }

    @Test func aCriticalValueWidensItsBlockByThePillPadding() {
        let plain = MenuBarLabelLayout.blockWidth(.stacked(label: "SSD", value: "97%"), compact: false)
        let pill = MenuBarLabelLayout.blockWidth(.stacked(label: "SSD", value: "97%", level: .critical), compact: false)
        #expect(pill == plain + 6)
        #expect(MenuBarLabelLayout.blockWidth(.stacked(label: "SSD", value: "97%", level: .critical), compact: true) >= 31 + 0)
    }

    @Test func theFlagTakesItsOwnWidthAndNothingElseMoves() {
        let without = layout([Self.cpu, Self.pair]), with = layout([Self.cpu, Self.pair, Self.flag])
        #expect(with.blocks.prefix(2).elementsEqual(without.blocks), "les autres blocs ne bougent pas")
        let flagWidth = with.blocks[2].width
        #expect((14...20).contains(flagWidth), "largeur du drapeau : \(flagWidth)")
        #expect(with.widthPoints == without.widthPoints + 9 + flagWidth)
    }

    @Test func addingABatteryAtTheEndLeavesTheOthersWhereTheyWere() {
        let items = [Self.cpu, Self.pair]
        let a = layout(items), b = layout(items + [Self.battery(67)])
        #expect(b.blocks.prefix(2).elementsEqual(a.blocks))
    }

    @Test func aReorderedLabelHasTheSameBlocksInTheNewOrder() {
        let ab = layout([Self.cpu, Self.pair]), ba = layout([Self.pair, Self.cpu])
        #expect(ab.widthPoints == ba.widthPoints)
        #expect(ab.blocks[0].width == ba.blocks[1].width && ab.blocks[1].width == ba.blocks[0].width)
    }

    // MARK: images

    @Test func theImageHasTheLayoutWidthInPointsAndTwentyTwoHighAtEveryScale() throws {
        for compact in [true, false] {
            for severity in [nil, Severity.warning, .critical] as [Severity?] {
                let items = [Self.cpu, Self.pair, Self.flag, Self.battery(67)]
                let image = try #require(MenuBarRenderer.image(severity: severity, compact: compact, items: items, darkBar: false, increasedContrast: false))
                let l = layout(items, compact: compact, severity: severity)
                #expect(image.size == NSSize(width: l.widthPoints, height: 22))
                for scale in 1...3 {
                    let ink = try GlyphInk(image: image, scale: CGFloat(scale))
                    #expect(ink.width == l.widthPoints * scale && ink.height == 22 * scale, "\(scale)x, compact \(compact)")
                }
            }
        }
    }

    @Test func theLastBlockEndsWithinTheImageAndNothingIsCutAtTheEdges() throws {
        let items = [Self.cpu, Self.pair, Self.flag, Self.battery(100)]
        let image = try #require(MenuBarRenderer.image(severity: .critical, compact: true, items: items, darkBar: false, increasedContrast: false))
        for scale in 1...3 {
            let ink = try GlyphInk(image: image, scale: CGFloat(scale))
            for x in 0..<ink.width { #expect(ink.alpha(x, 0) < 0.1 || x < 0, "rangée du haut, colonne \(x), \(scale)x") }
            let right = (0..<ink.height).contains { ink.alpha(ink.width - 1, $0) > 0.1 }
            #expect(!right, "la dernière colonne est vide : le dernier bloc est entièrement dedans, \(scale)x")
        }
    }

    @Test func theBadgeIsDrawnAtEveryScale() throws {
        for scale in 1...3 {
            let g = BrandPixelGeometry(scale: scale)
            let warning = try GlyphInk(image: try #require(MenuBarRenderer.image(severity: .warning, compact: true, items: [], darkBar: false, increasedContrast: false)), scale: CGFloat(scale))
            let circle = g.circleRect
            #expect(warning.alpha(circle.x + circle.width / 2, circle.y + circle.height / 2) > 0.99, "le rond d'alerte, \(scale)x")
            let critical = try GlyphInk(image: try #require(MenuBarRenderer.image(severity: .critical, compact: true, items: [], darkBar: false, increasedContrast: false)), scale: CGFloat(scale))
            let t = g.triangleRect
            #expect(critical.alpha(t.x + t.width / 2 - 2 * scale, t.y + t.height - 2) > 0.99 && critical.alpha(t.x + t.width / 2, t.y + t.height - 1) > 0.5, "le triangle d'alerte, \(scale)x")
            // Le point d'exclamation est un trou : transparent au centre, à la hauteur de la barre.
            #expect(critical.alpha(t.x + t.width / 2, t.y + Int(CGFloat(t.height) * 0.45)) < 0.1, "point d'exclamation creusé, \(scale)x")
            let none = try GlyphInk(image: try #require(MenuBarRenderer.image(severity: nil, compact: true, items: [], darkBar: false, increasedContrast: false)), scale: CGFloat(scale))
            #expect(none.alpha(circle.x + circle.width / 2, circle.y + circle.height / 2) < 0.01)
        }
    }

    @Test func theTemplateRuleIsUnchanged() throws {
        let plain = try #require(MenuBarRenderer.image(severity: nil, compact: true, items: [Self.cpu, Self.pair, Self.battery(67)], darkBar: true, increasedContrast: false))
        #expect(plain.isTemplate)
        for scale in 1...3 {
            let ink = try GlyphInk(image: plain, scale: CGFloat(scale))
            for y in 0..<ink.height { for x in 0..<ink.width {
                let p = ink.pixel(x, y)
                if p.a > 0 { #expect(p.r < 0.01 && p.g < 0.01 && p.b < 0.01, "alpha seul, noir, même sur barre sombre : \(p)") }
            } }
        }
        for coloured in [[MenuBarItem.stacked(label: "CPU", value: "70%", level: .medium)], [Self.flag]] {
            #expect(try #require(MenuBarRenderer.image(severity: nil, compact: true, items: coloured, darkBar: true, increasedContrast: false)).isTemplate == false)
        }
    }

    @Test func theInlineStyleDrawsLabelThenValueOnOneLine() throws {
        let image = try #require(MenuBarRenderer.image(severity: nil, compact: false, items: [Self.cpu], darkBar: false, increasedContrast: false))
        let l = layout([Self.cpu], compact: false)
        #expect(image.size.width == CGFloat(l.widthPoints) && l.blocks[0].width >= 56 && l.blocks[0].width <= 64)
        for scale in 1...3 {
            let ink = try GlyphInk(image: image, scale: CGFloat(scale))
            let e = try #require(SharpnessMetric.textEdgeHardness(ink, region: CGRect(x: CGFloat(l.blocks[0].x), y: 0, width: CGFloat(l.blocks[0].width), height: 22)))
            #expect(e.rows >= 9 * scale - 1 && e.rows <= 11 * scale + 1, "une seule ligne de texte de 13 pt, \(scale)x : \(e.rows) rangées")
            if scale <= 2 { #expect(e.bottom >= 0.7, "la ligne de base, \(scale)x : \(e)") }      // en 3x le débord rond des lettres fausse le rapport (mesuré 0,20)
        }
    }

    @Test func increasedContrastThickensTheBatteryOutlineAtEveryScale() throws {
        for scale in 1...3 {
            func inkRows(_ contrast: Bool) throws -> Int {
                let image = try #require(MenuBarRenderer.image(severity: nil, compact: true, items: [Self.battery(0)], darkBar: false, increasedContrast: contrast))
                let ink = try GlyphInk(image: image, scale: CGFloat(scale))
                let x = (16 + 9 + 10) * scale
                return (0..<ink.height).filter { ink.alpha(x, $0) > 0.5 }.count
            }
            #expect(try inkRows(true) > inkRows(false), "\(scale)x")
        }
    }

    // MARK: la vraie image, lue à chaque échelle

    private func realLabel(_ items: [MenuBarItem], severity: Severity? = nil, scale: Int, contrast: Bool = false) throws -> (ink: GlyphInk, layout: MenuBarLabelLayout) {
        let image = try #require(MenuBarRenderer.image(severity: severity, compact: true, items: items, darkBar: false, increasedContrast: contrast))
        return (try GlyphInk(image: image, scale: CGFloat(scale)), layout(items, severity: severity))
    }

    @Test(arguments: [1, 2, 3])
    func theLabelIsLaidOutForTheScaleItIsDrawnAt(scale: Int) throws {
        // Le trait du glyphe et le contour de la batterie ont, à chaque échelle, le nombre de pixels de leur table : pas ceux d'une autre échelle étirés.
        let (ink, l) = try realLabel([Self.battery(50)], scale: scale)
        let brand = BrandPixelGeometry(scale: scale)
        let groundColumn = 8 * scale
        let ground = (0..<ink.height).filter { ink.alpha(groundColumn, $0) > 0.5 && $0 >= brand.groundRows.lowerBound - 1 }.count
        #expect(ground == brand.strokeWidth, "ligne droite du glyphe : \(ground) rangées, attendu \(brand.strokeWidth) à \(scale)x")
        let battery = BatteryPixelGeometry(scale: scale)
        let column = (l.blocks[0].x + 10) * scale
        let top = (0..<ink.height / 2).filter { ink.alpha(column, $0) > 0.5 }
        #expect(top.first == (22 * scale - battery.body.height) / 2, "le haut du contour du corps, \(scale)x")
        #expect(top.prefix(while: { $0 < (top.first ?? 0) + battery.lineWidth }).count == battery.lineWidth, "contour de \(battery.lineWidth) px à \(scale)x")
    }

    @Test(arguments: [1, 2, 3])
    func theShapesOfTheRealLabelHaveNoIntermediatePixelOnTheirStraightEdges(scale: Int) throws {
        let items: [MenuBarItem] = [Self.battery(67), .stacked(label: "SSD", value: "97%", level: .critical)]
        for contrast in [false, true] {
            let (ink, l) = try realLabel(items, scale: scale, contrast: contrast)
            let g = BatteryPixelGeometry(scale: scale, increasedContrast: contrast)
            let x0 = l.blocks[0].x * scale, y0 = (22 * scale - g.body.height) / 2
            let r = Int(g.cornerRadius.rounded(.up)) + 1, flat = g.body.width - 2 * r
            let fill = g.fillRect(percent: 67)
            let areas: [(String, PixelRect)] = [
                ("haut", PixelRect(x: x0 + r, y: y0, width: flat, height: g.lineWidth)),
                ("bas", PixelRect(x: x0 + r, y: y0 + g.body.height - g.lineWidth, width: flat, height: g.lineWidth)),
                ("gauche", PixelRect(x: x0, y: y0 + r, width: g.lineWidth, height: g.body.height - 2 * r)),
                ("remplissage", PixelRect(x: x0 + fill.maxX - 1, y: y0 + fill.y + 1, width: 2, height: max(1, fill.height - 2))),
            ]
            for (name, area) in areas {
                let e = SharpnessMetric.edgeSoftness(ink, xs: area.x..<area.maxX, ys: area.y..<area.maxY)
                #expect(e.inked > 0 && e.soft == 0, "\(name), \(scale)x, contraste \(contrast) : \(e)")
            }
        }
        let (ink, l) = try realLabel(items, scale: scale)
        let pill = try #require(SharpnessMetric.bounds(of: ink) { $0.a > 0.5 && $0.r > 0.9 && $0.g < 0.3 && $0.b < 0.1 })
        let pr = Int((CGFloat(PixelGrid.px(3.5, scale: scale))).rounded(.up)) + 1
        let px = Int((pill.minX * CGFloat(scale)).rounded()), py = Int((pill.minY * CGFloat(scale)).rounded())
        let pw = Int((pill.width * CGFloat(scale)).rounded()), ph = Int((pill.height * CGFloat(scale)).rounded())
        for area in [PixelRect(x: px + pr, y: py, width: pw - 2 * pr, height: 2), PixelRect(x: px + pr, y: py + ph - 2, width: pw - 2 * pr, height: 2),
                     PixelRect(x: px, y: py + pr, width: 2, height: ph - 2 * pr), PixelRect(x: px + pw - 2, y: py + pr, width: 2, height: ph - 2 * pr)] {
            let e = SharpnessMetric.edgeSoftness(ink, xs: area.x..<area.maxX, ys: area.y..<area.maxY)
            #expect(e.inked > 0 && e.soft == 0, "pastille, \(scale)x : \(e)")
        }
        _ = l
    }
}

/// SL23 : SwiftUI redessine l'image dynamique à l'échelle où il rend (l'aperçu des Réglages et le repli du libellé en dépendent).
@MainActor @Suite(.serialized) struct MenuBarLabelInSwiftUITests {
    @Test(arguments: [1, 2, 3])
    func anImageViewDrawsTheLabelAtTheScaleItIsRenderedAt(scale: Int) throws {
        let items: [MenuBarItem] = [.battery(percent: 67, power: .onBattery)]
        let image = MenuBarRenderer.previewImage(severity: nil, compact: true, items: items, darkStrip: false, increasedContrast: false)
        let renderer = ImageRenderer(content: Image(nsImage: image))
        renderer.scale = CGFloat(scale)
        let ink = try GlyphInk(cg: try #require(renderer.cgImage), scale: CGFloat(scale))
        #expect(ink.width == Int(image.size.width) * scale && ink.height == 22 * scale, "\(scale)x : \(ink.width) x \(ink.height)")
        let g = BatteryPixelGeometry(scale: scale)
        let l = MenuBarLabelLayout(items: items, compact: true, severity: nil)
        let x0 = l.blocks[0].x * scale, y0 = (22 * scale - g.body.height) / 2
        let r = Int(g.cornerRadius.rounded(.up)) + 1
        let top = SharpnessMetric.edgeSoftness(ink, xs: (x0 + r)..<(x0 + g.body.width - r), ys: y0..<(y0 + g.lineWidth))
        #expect(top.inked > 0 && top.soft == 0, "le haut du contour est net à \(scale)x : \(top)")
    }
}
