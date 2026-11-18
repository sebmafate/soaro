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
