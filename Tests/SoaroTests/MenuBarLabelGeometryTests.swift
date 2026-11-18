import CoreGraphics
import Foundation
import Testing
@testable import Soaro

/// SL23, étape 2 : la grille de pixels. Géométrie pure : des nombres entiers pour chaque échelle, aucune forme à cheval sur deux pixels.
@Suite struct PixelGridTests {
    @Test func pointsBecomeWholePixelsRoundedHalfUp() {
        #expect(PixelGrid.px(7.5, scale: 1) == 8)
        #expect(PixelGrid.px(7.5, scale: 2) == 15)
        #expect(PixelGrid.px(7.5, scale: 3) == 23)
        #expect(PixelGrid.px(4.5, scale: 2) == 9)
        #expect(PixelGrid.px(0.4, scale: 1) == 0)
        #expect(PixelGrid.px(19.5, scale: 1) == 20)
    }

    @Test func evenPixelsAreTheNearestEvenNumber() {
        #expect(PixelGrid.evenPx(4.2, scale: 1) == 4)
        #expect(PixelGrid.evenPx(4.2, scale: 2) == 8)
        #expect(PixelGrid.evenPx(4.2, scale: 3) == 12)
        #expect(PixelGrid.evenPx(6.6, scale: 1) == 6)
        #expect(PixelGrid.evenPx(6.6, scale: 2) == 14)
        #expect(PixelGrid.evenPx(0.1, scale: 1) == 2, "jamais zéro")
    }

    @Test func snappingGivesAWholeNumberOfPixels() {
        for scale in [1, 2, 3, 4] {
            for points in stride(from: 0.0, through: 30.0, by: 0.37) {
                let snapped = PixelGrid.snap(CGFloat(points), scale: scale)
                #expect(PixelGrid.isWhole(snapped * CGFloat(scale)), "\(points) pt à \(scale)x : \(snapped)")
                #expect(abs(snapped - CGFloat(points)) <= 0.5 / CGFloat(scale) + 1e-9)
            }
        }
        #expect(!PixelGrid.isWhole(7.5))
        #expect(PixelGrid.isWhole(8))
    }
}

@Suite struct BatteryPixelGeometryTests {
    @Test func theBodyIsTwentyByTenPointsAtEveryScale() {
        for scale in 1...4 {
            let g = BatteryPixelGeometry(scale: scale)
            #expect(g.body == PixelRect(x: 0, y: 0, width: 20 * scale, height: 10 * scale))
        }
        #expect(BatteryPixelGeometry(scale: 1).body == PixelRect(x: 0, y: 0, width: 20, height: 10), "20 x 10 pixels en 1x")
    }

    @Test func theLineAndTheGapAreWholePixelsWithTheirOwnNumbersAtEachScale() {
        let table: [(scale: Int, line: Int, contrast: Int, gap: Int)] = [(1, 1, 2, 1), (2, 2, 3, 2), (3, 4, 5, 2), (4, 5, 6, 3)]
        for row in table {
            let normal = BatteryPixelGeometry(scale: row.scale), strong = BatteryPixelGeometry(scale: row.scale, increasedContrast: true)
            #expect(normal.lineWidth == row.line && strong.lineWidth == row.contrast && normal.gap == row.gap, "\(row.scale)x : \(normal.lineWidth), \(strong.lineWidth), \(normal.gap)")
            #expect(strong.lineWidth > normal.lineWidth, "« Augmenter le contraste » épaissit le trait à toutes les échelles")
        }
        let one = BatteryPixelGeometry(scale: 1)
        #expect(one.inner == PixelRect(x: 2, y: 2, width: 16, height: 6))
    }

    @Test func theNubIsCentredOnWholePixelsAndTheTotalIsTheBodyPlusTheNub() {
        for scale in 1...4 {
            let g = BatteryPixelGeometry(scale: scale)
            #expect(g.nub.x == g.body.width)
            #expect(g.nub.height % 2 == 0, "hauteur paire : le centrage tombe sur un pixel entier")
            #expect(g.nub.y * 2 + g.nub.height == g.body.height, "\(scale)x : centré")
            #expect(g.nub.height * 2 < g.body.height + 1)
            #expect(g.total == CGSize(width: g.body.width + g.nub.width, height: g.body.height))
        }
        #expect(BatteryPixelGeometry(scale: 1).nub == PixelRect(x: 20, y: 3, width: 2, height: 4))
    }

    @Test func theFillIsAWholeNumberOfPixelsBetweenNothingAndTheInnerWidth() {
        for scale in 1...3 {
            let g = BatteryPixelGeometry(scale: scale)
            #expect(g.fillWidth(percent: 0) == 0 && g.fillWidth(percent: -5) == 0 && g.fillWidth(percent: .nan) == 0)
            #expect(g.fillWidth(percent: 100) == g.inner.width && g.fillWidth(percent: 300) == g.inner.width)
            var previous = 0
            for percent in stride(from: 0.5, to: 100, by: 0.5) {
                let w = g.fillWidth(percent: percent)
                #expect(w >= previous, "monotone \(percent) %")
                #expect(w >= scale && w <= g.inner.width - 1, "1 pt au moins, et seul 100 % est plein : \(percent) % → \(w)")
                previous = w
            }
        }
        let one = BatteryPixelGeometry(scale: 1)
        #expect(one.fillWidth(percent: 50) == 8)
        #expect(one.fillWidth(percent: 1) == 1)
        #expect(one.fillRect(percent: 50) == PixelRect(x: 2, y: 2, width: 8, height: 6))
    }

    @Test func theMarkIsTwelvePointsHighCentredAndOverflowsByOnePoint() {
        for scale in 1...4 {
            let g = BatteryPixelGeometry(scale: scale)
            #expect(g.markHeight == 12 * scale && g.verticalOverflow == scale)
            for mark in [BatteryGlyphMark.bolt, .plug] {
                let r = g.markRect(mark)
                #expect(r.height == g.markHeight && r.y == -g.verticalOverflow)
                #expect(r.width % 2 == 0 && r.x * 2 + r.width == g.body.width, "\(mark) \(scale)x : centré sur des pixels entiers")
            }
            #expect(g.haloWidth >= 1)
        }
        let one = BatteryPixelGeometry(scale: 1)
        #expect(one.boltRect == PixelRect(x: 7, y: -1, width: 6, height: 12))
        #expect(one.plugRect == PixelRect(x: 6, y: -1, width: 8, height: 12))
    }

    @Test func thePlugIsMadeOfWholePixelRectanglesThatAreSymmetricAndInsideItsBox() {
        for scale in 1...4 {
            let g = BatteryPixelGeometry(scale: scale)
            let rects = g.plugRects, box = g.plugRect
            #expect(rects.count == 4)
            for r in rects {
                #expect(r.width >= 1 && r.height >= 1)
                #expect(r.x >= box.x && r.maxX <= box.maxX && r.y >= box.y && r.maxY <= box.maxY)
            }
            // Les deux dents sont l'image l'une de l'autre dans un miroir droite-gauche.
            #expect(rects[0].x - box.x == box.maxX - rects[1].maxX && rects[0].width == rects[1].width, "dents symétriques, \(scale)x")
            #expect(rects[3].x - box.x == box.maxX - rects[3].maxX, "cordon centré, \(scale)x")
        }
    }

    @Test func theBoltVerticesStayInsideItsBox() {
        let g = BatteryPixelGeometry(scale: 2), r = g.boltRect.cgRect
        for p in g.boltPoints { #expect(r.insetBy(dx: -0.001, dy: -0.001).contains(p)) }
        #expect(g.boltPoints.count == 6)
    }

    @Test func theNamedConstantsOfEarlierSlicesStillExist() {
        #expect(BatteryGlyphGeometry.markScale == 1.2 && BatteryGlyphGeometry.haloWidth == 0.9 && BatteryGlyphGeometry.step == 0.5)
        #expect(BatteryGlyphGeometry.menuBarBody == CGSize(width: 20, height: 9.5), "la carte et l'onglet gardent leur géométrie en points")
    }
}

@Suite struct BrandPixelGeometryTests {
    @Test func theStrokeIsAWholeNumberOfPixels() {
        #expect(BrandPixelGeometry(scale: 1).strokeWidth == 1, "2 px en 1x empâtent les vagues (vu à l'œil) : 1 px")
        #expect(BrandPixelGeometry(scale: 2).strokeWidth == 3)
        #expect(BrandPixelGeometry(scale: 3).strokeWidth == 5)
    }

    @Test func theGroundLineCoversWholeRowsAndBothEndsAreInsideTheSixteenPointBox() {
        for scale in 1...4 {
            let g = BrandPixelGeometry(scale: scale)
            let rows = g.groundRows
            #expect(rows.count == g.strokeWidth)
            #expect(PixelGrid.isWhole(g.pathRect.maxY - CGFloat(g.strokeWidth) / 2) && PixelGrid.isWhole(g.pathRect.maxY + CGFloat(g.strokeWidth) / 2),
                    "les deux bords du trait sont sur des frontières de pixels, \(scale)x")
            #expect(g.pathRect.minX - CGFloat(g.strokeWidth) / 2 >= 0, "le bout rond gauche n'est plus coupé")
            #expect(g.pathRect.maxX + CGFloat(g.strokeWidth) / 2 <= CGFloat(16 * scale) + 1e-9)
            #expect(g.pathRect.height == CGFloat(12 * scale))
            #expect(abs((g.pathRect.maxY) - CGFloat(17 * scale)) <= 0.5 + 1e-9, "le bas de la boîte reste à 17 pt du haut")
        }
    }

    @Test func theBadgeWidthsAreWholePoints() {
        #expect(BrandPixelGeometry.widthPoints(for: nil) == 16)
        #expect(BrandPixelGeometry.widthPoints(for: .info) == 16)
        #expect(BrandPixelGeometry.widthPoints(for: .warning) == 22)
        #expect(BrandPixelGeometry.widthPoints(for: .critical) == 28)
    }

    @Test func theBadgeShapesAreWholePixelRectsAlignedOnTheTopOfTheGlyph() {
        for scale in 1...3 {
            let g = BrandPixelGeometry(scale: scale)
            #expect(g.circleRect.x == 16 * scale + scale && g.circleRect.width == g.circleRect.height)
            #expect(g.circleRect.y == g.topPixels && g.topPixels == 5 * scale)
            #expect(g.triangleRect.x == g.circleRect.x && g.triangleRect.height == 8 * scale)
            #expect(g.circleRect.maxX <= (16 + 1 + 5) * scale + 1 && g.triangleRect.maxX <= (16 + 1 + 11) * scale)
        }
    }
}
