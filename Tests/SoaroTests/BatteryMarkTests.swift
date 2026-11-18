import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Soaro

/// SL21, retour de l'auteur : l'éclair et la prise sont GRANDS (au moins la hauteur du corps, jusqu'à dépasser un peu le contour),
/// ne sont plus limités à la zone de remplissage, et sont cernés d'un jeu transparent (halo) creusé dans le contour et le remplissage ;
/// le repère lui-même est de l'encre pleine. Tout est en alpha : l'image modèle reste monochrome.

@Suite struct BatteryMarkGeometryTests {
    private static let bodies = [BatteryGlyphGeometry.menuBarBody, BatteryGlyphGeometry.cardBody, BatteryGlyphGeometry.tabBody]

    @Test func theTwoTuningConstantsAreNamedAndInTheirRange() {
        // Un seul réglage pour la taille (la hauteur du repère, en fraction de la hauteur du corps), un seul pour le halo (en points).
        #expect(BatteryGlyphGeometry.markScale >= 1, "au moins aussi haut que le corps")
        #expect(BatteryGlyphGeometry.markScale <= 1.4, "un peu au-delà du contour, pas plus")
        #expect((0.8...1.0).contains(BatteryGlyphGeometry.haloWidth), "halo de 0,8 à 1 pt")
        // Les valeurs choisies (voir PLAN) : 1,2 fois la hauteur du corps, halo de 0,9 pt.
        #expect(BatteryGlyphGeometry.markScale == 1.2 && BatteryGlyphGeometry.haloWidth == 0.9)
        #expect(abs(BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody).markHeight - 11.4) < 1e-9)
    }

    @Test func theMarkIsAsTallAsTheWholeBodyTimesTheScaleAtEverySize() {
        for body in Self.bodies {
            let g = BatteryGlyphGeometry(body: body)
            for mark in [BatteryGlyphMark.bolt, .plug] {
                let r = g.markRect(mark)
                #expect(abs(r.height - body.height * BatteryGlyphGeometry.markScale) < 1e-9, "\(mark) \(body)")
                #expect(r.height >= body.height - 1e-9, "pas limité au remplissage : au moins la hauteur du corps")
                #expect(r.height > g.innerRect.height, "plus haut que la zone de remplissage")
                #expect(abs(r.midX - g.bodyRect.midX) < 1e-9 && abs(r.midY - g.bodyRect.midY) < 1e-9, "centré sur le corps")
            }
        }
    }

    @Test func theMarkNeverWidensTheItem() {
        for body in Self.bodies {
            let g = BatteryGlyphGeometry(body: body)
            for mark in [BatteryGlyphMark.bolt, .plug] {
                let r = g.markRect(mark)
                #expect(r.minX - BatteryGlyphGeometry.haloWidth >= g.bodyRect.minX + g.lineWidth, "le halo reste dans le corps, à droite et à gauche")
                #expect(r.maxX + BatteryGlyphGeometry.haloWidth <= g.bodyRect.maxX - g.lineWidth)
            }
            #expect(g.totalSize.width == body.width + g.nubRect.width, "la largeur de l'icône ne dépend pas du repère")
        }
    }

    @Test func theVerticalOverflowIsHalfTheExcessAndNotMore() {
        for body in Self.bodies {
            let g = BatteryGlyphGeometry(body: body)
            let excess = max(0, body.height * BatteryGlyphGeometry.markScale - body.height)
            #expect(abs(g.verticalOverflow - excess / 2) < 1e-9)
            #expect(g.markRect(.bolt).minY >= -g.verticalOverflow - 1e-9 && g.markRect(.plug).maxY <= body.height + g.verticalOverflow + 1e-9)
        }
    }

    @Test func theMenuBarMarkFitsTheTwentyTwoPointLabel() {
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        // Le libellé fait 22 pt, le corps 9,5 pt centré : de la marge de chaque côté pour le repère et son halo.
        let room = (22 - g.body.height) / 2
        #expect(g.verticalOverflow + BatteryGlyphGeometry.haloWidth < room, "le repère dépasse de \(g.verticalOverflow) pt, il reste \(room) pt")
    }

    @Test func theBoltAndThePlugAreDistinctShapesOfTheSameHeight() {
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        #expect(g.boltRect.height == g.plugRect.height)
        #expect(g.boltRect != g.plugRect)
        #expect(g.markPath(.bolt).boundingRect != g.markPath(.plug).boundingRect)
    }

    @Test func theHaloIsTheMarkWidenedByTheHaloWidthOnEverySide() {
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        for mark in [BatteryGlyphMark.bolt, .plug] {
            let halo = g.haloPath(mark)
            let base = g.markPath(mark).boundingRect
            let box = halo.boundingRect
            #expect(box.minX <= base.minX - BatteryGlyphGeometry.haloWidth + 0.01 && box.maxX >= base.maxX + BatteryGlyphGeometry.haloWidth - 0.01)
            #expect(box.minY <= base.minY - BatteryGlyphGeometry.haloWidth + 0.01 && box.maxY >= base.maxY + BatteryGlyphGeometry.haloWidth - 0.01)
        }
    }

    // MARK: Le niveau reste lisible autour du repère

    @Test func theFillEdgeIsBehindTheMarkOnlyInAMiddleRangeOfLevels() {
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        for mark in [BatteryGlyphMark.bolt, .plug] {
            let range = g.hiddenEdgeRange(mark)
            #expect(range.lowerBound > 5 && range.upperBound < 95, "aux extrêmes le bord du remplissage se voit toujours")
            // La largeur du remplissage aux deux bouts de la plage coïncide avec les bords du halo.
            let left = g.innerRect.minX + g.fillWidth(percent: range.lowerBound)
            let right = g.innerRect.minX + g.fillWidth(percent: range.upperBound)
            #expect(left <= g.markRect(mark).minX - BatteryGlyphGeometry.haloWidth + 0.5 + BatteryGlyphGeometry.step)
            #expect(right >= g.markRect(mark).maxX + BatteryGlyphGeometry.haloWidth - 0.5 - BatteryGlyphGeometry.step)
        }
        // Le plus étroit des deux cache le moins : l'éclair.
        let bolt = g.hiddenEdgeRange(.bolt), plug = g.hiddenEdgeRange(.plug)
        #expect(bolt.upperBound - bolt.lowerBound < plug.upperBound - plug.lowerBound)
    }
}

/// Rendus hors écran du glyphe seul, avec le débordement vertical (le glyphe est posé sur une marge qui le contient).
@MainActor @Suite(.serialized) struct BatteryMarkRenderTests {
    private static let scale: CGFloat = 4

    /// L'image complète (corps + débordement du repère), et la hauteur de marge en points.
    private func full(_ power: BatteryPowerState, percent: Double, level: PressureLevel = .normal, base: Color = .black,
                      body: CGSize = BatteryGlyphGeometry.menuBarBody) throws -> GlyphInk {
        let g = BatteryGlyphGeometry(body: body)
        let view = BatteryGlyph(percent: percent, power: power, level: level, base: base, body: body, increasedContrast: false).padding(.vertical, g.verticalOverflow)
        let renderer = ImageRenderer(content: view)
        renderer.scale = Self.scale
        return try GlyphInk(cg: try #require(renderer.cgImage), scale: Self.scale)
    }

    private func point(_ x: Int, _ y: Int, body: CGSize) -> CGPoint {
        let g = BatteryGlyphGeometry(body: body)
        return CGPoint(x: (CGFloat(x) + 0.5) / Self.scale, y: (CGFloat(y) + 0.5) / Self.scale - g.verticalOverflow)
    }

    private func isInside(_ p: CGPoint, _ path: Path, margin: CGFloat) -> Bool {
        path.contains(p) && !path.strokedPath(StrokeStyle(lineWidth: 2 * margin)).contains(p)
    }

    /// Hors du repère, hors de la marge de 0,3 pt de son contour, dans l'anneau du halo (à 0,3 pt de chaque bord du halo).
    private func isInHalo(_ p: CGPoint, mark: Path, g: BatteryGlyphGeometry) -> Bool {
        let near = mark.strokedPath(StrokeStyle(lineWidth: 0.6)).contains(p) || mark.contains(p)
        guard !near else { return false }
        return mark.strokedPath(StrokeStyle(lineWidth: 2 * (BatteryGlyphGeometry.haloWidth - 0.3), lineJoin: .round)).contains(p)
    }

    @Test(arguments: [BatteryGlyphMark.bolt, .plug])
    func theMarkIsSolidInkAndTheHaloIsATransparentGapAtEveryLevel(mark: BatteryGlyphMark) throws {
        let power: BatteryPowerState = mark == .bolt ? .charging : .pluggedNotCharging
        for body in [BatteryGlyphGeometry.menuBarBody, BatteryGlyphGeometry.cardBody, BatteryGlyphGeometry.tabBody] {
            let g = BatteryGlyphGeometry(body: body)
            let path = g.markPath(mark)
            for percent in [0.0, 30, 55, 75, 100] {
                let ink = try full(power, percent: percent, body: body)
                var markPixels = 0, haloPixels = 0
                for x in 0..<ink.width { for y in 0..<ink.height {
                    let p = point(x, y, body: body)
                    if isInside(p, path, margin: 0.3) {
                        markPixels += 1
                        #expect(ink.alpha(x, y) > 0.9, "repère plein de ton \(mark) à \(p) (\(percent) %)")
                    } else if isInHalo(p, mark: path, g: g) {
                        haloPixels += 1
                        #expect(ink.alpha(x, y) < 0.1, "halo transparent à \(p) (\(percent) %, \(mark))")
                    }
                } }
                #expect(markPixels > 40 && haloPixels > 40, "\(mark) \(body) : \(markPixels) pixels de repère, \(haloPixels) de halo")
            }
        }
    }

    @Test(arguments: [BatteryGlyphMark.bolt, .plug])
    func theHaloIsCutOutOfTheOutlineAndOutOfTheFill(mark: BatteryGlyphMark) throws {
        let power: BatteryPowerState = mark == .bolt ? .charging : .pluggedNotCharging
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        let plain = try full(.onBattery, percent: 100), marked = try full(power, percent: 100)
        var cutOutline = 0, cutFill = 0
        for x in 0..<plain.width { for y in 0..<plain.height {
            guard plain.alpha(x, y) > 0.9, marked.alpha(x, y) < 0.1 else { continue }
            let p = point(x, y, body: g.body)
            if p.y < g.lineWidth || p.y > g.body.height - g.lineWidth { cutOutline += 1 } else { cutFill += 1 }
        } }
        #expect(cutOutline >= 6, "\(mark) : le contour est coupé sous le halo (\(cutOutline) pixels)")
        #expect(cutFill >= 40, "\(mark) : le remplissage est coupé autour du repère (\(cutFill) pixels)")
    }

    @Test(arguments: [BatteryGlyphMark.bolt, .plug])
    func theMarkIsNotConfinedToTheFillArea(mark: BatteryGlyphMark) throws {
        let power: BatteryPowerState = mark == .bolt ? .charging : .pluggedNotCharging
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        let path = g.markPath(mark)
        let ink = try full(power, percent: 0)
        var aboveFill = 0, belowFill = 0
        for x in 0..<ink.width { for y in 0..<ink.height where ink.alpha(x, y) > 0.9 {
            let p = point(x, y, body: g.body)
            guard isInside(p, path, margin: 0.3) else { continue }
            if p.y < g.innerRect.minY { aboveFill += 1 }
            if p.y > g.innerRect.maxY { belowFill += 1 }
        } }
        #expect(aboveFill > 0 && belowFill > 0, "\(mark) : de l'encre du repère au-dessus (\(aboveFill)) et au-dessous (\(belowFill)) de la zone de remplissage")
    }

    @Test(arguments: [BatteryGlyphMark.bolt, .plug])
    func theMarkReachesItsNominalTopAndBottomAndIsNotClipped(mark: BatteryGlyphMark) throws {
        let power: BatteryPowerState = mark == .bolt ? .charging : .pluggedNotCharging
        for body in [BatteryGlyphGeometry.menuBarBody, BatteryGlyphGeometry.cardBody, BatteryGlyphGeometry.tabBody] {
            let g = BatteryGlyphGeometry(body: body)
            let r = g.markRect(mark), path = g.markPath(mark)
            let ink = try full(power, percent: 0, body: body)
            var top = CGFloat.infinity, bottom = -CGFloat.infinity
            for x in 0..<ink.width { for y in 0..<ink.height where ink.alpha(x, y) > 0.9 {
                let p = point(x, y, body: body)
                guard path.contains(p) else { continue }
                top = min(top, p.y); bottom = max(bottom, p.y)
            } }
            #expect(top <= r.minY + 1.6, "\(mark) \(body) : haut à \(top), attendu \(r.minY)")
            #expect(bottom >= r.maxY - 1.6, "\(mark) \(body) : bas à \(bottom), attendu \(r.maxY)")
            if BatteryGlyphGeometry.markScale > 1 { #expect(top < 0 && bottom > body.height, "le repère dépasse du corps en haut et en bas") }
        }
    }

    @Test func theImageIsTemplateCompatibleAlphaOnlyInTheBaseColour() throws {
        // Image modèle : le repère, son halo et le reste ne portent que de l'alpha ; en noir, aucun pixel n'est autre chose que du noir.
        for power in [BatteryPowerState.charging, .pluggedNotCharging] {
            for percent in [0.0, 50, 100] {
                let ink = try full(power, percent: percent)
                for x in 0..<ink.width { for y in 0..<ink.height {
                    let p = ink.pixel(x, y)
                    if p.a > 0 { #expect(p.r < 0.02 && p.g < 0.02 && p.b < 0.02, "pixel (\(x), \(y)) n'est pas noir : \(p)") }
                } }
            }
        }
    }

    @Test func theMarkIsInTheBaseColourNotTheLevelColourAndTheFillKeepsTheLevelColour() throws {
        let g = BatteryGlyphGeometry(body: BatteryGlyphGeometry.menuBarBody)
        let ink = try full(.charging, percent: 100, level: .high, base: .white)
        let r = g.boltRect
        // Au centre du repère (à mi-hauteur) : blanc ; dans le remplissage loin du repère : rouge.
        var white = 0
        for x in 0..<ink.width { for y in 0..<ink.height {
            let p = point(x, y, body: g.body)
            if isInside(p, g.boltPath(), margin: 0.3) { let c = ink.pixel(x, y); if c.a > 0.9 && c.r > 0.9 && c.g > 0.9 && c.b > 0.9 { white += 1 } }
        } }
        #expect(white > 30)
        let fill = ink.pixel(Int((g.innerRect.minX + 0.8) * Self.scale), Int((g.innerRect.midY + g.verticalOverflow) * Self.scale))
        #expect(fill.a > 0.9 && fill.r > 0.9 && fill.g < 0.3, "remplissage rouge loin du repère : \(fill) (repère à \(r))")
    }
}

/// Le libellé de 22 pt : le repère dépasse du corps mais pas du libellé, et ne l'élargit pas.
@MainActor @Suite(.serialized) struct BatteryMarkLabelTests {
    private func render(_ items: [MenuBarItem], compact: Bool = true, dark: Bool = false) throws -> NSImage {
        try #require(MenuBarRenderer.image(severity: nil, compact: compact, items: items, darkBar: dark, increasedContrast: false))
    }

    @Test func theLabelKeepsItsHeightAndItsWidthInEveryStateAndStyle() throws {
        for compact in [true, false] {
            for percent in [5, 50, 100] {
                let sizes = try [BatteryPowerState.onBattery, .charging, .pluggedNotCharging].map { try render([.battery(percent: percent, power: $0)], compact: compact).size }
                #expect(Set(sizes.map(\.width)).count == 1, "largeur identique, compact \(compact) \(percent) %")
                #expect(sizes.allSatisfy { $0.height == 22 })
            }
        }
    }

    @Test func theMarkIsNotClippedByTheLabelTopOrBottom() throws {
        for compact in [true, false] {
            for power in [BatteryPowerState.charging, .pluggedNotCharging] {
                for dark in [false, true] {
                    let ink = try GlyphInk(image: render([.battery(percent: 0, power: power)], compact: compact, dark: dark))
                    // Première et dernière lignes transparentes : rien n'est coupé en haut ni en bas du libellé.
                    for x in 0..<ink.width {
                        #expect(ink.alpha(x, 0) < 0.1 && ink.alpha(x, ink.height - 1) < 0.1, "colonne \(x), \(power)")
                    }
                }
            }
        }
    }
}
