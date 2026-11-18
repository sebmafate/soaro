import CoreGraphics
import Foundation
import Testing
@testable import Soaro

/// SL24, étape 1 : la géométrie en pixels entiers de l'icône de batterie pour N'IMPORTE QUELLE taille de corps (la carte 28 x 13, l'onglet 32 x 15,
/// la barre de menus 20 x 10), aux échelles 1, 2 et 3. Géométrie pure : des nombres.
@Suite struct BatteryPixelGeometryGenericTests {
    static let bodies: [(name: String, body: CGSize, nub: CGFloat)] = [
        ("barre", CGSize(width: 20, height: 10), 1.6),
        ("carte", BatteryGlyphGeometry.cardBody, BatteryPixelGeometry.nubPoints(forBody: BatteryGlyphGeometry.cardBody)),
        ("onglet", BatteryGlyphGeometry.tabBody, BatteryPixelGeometry.nubPoints(forBody: BatteryGlyphGeometry.tabBody)),
    ]

    private func geometry(_ body: CGSize, _ nub: CGFloat, _ scale: Int, contrast: Bool = false) -> BatteryPixelGeometry {
        BatteryPixelGeometry(bodyPoints: body, nubPoints: nub, scale: scale, increasedContrast: contrast)
    }

    // MARK: la barre de menus ne change pas

    @Test func theMenuBarConvenienceInitialiserIsTheGenericOneWithTheMenuBarSize() {
        for scale in 1...4 {
            for contrast in [false, true] {
                #expect(BatteryPixelGeometry(scale: scale, increasedContrast: contrast)
                        == BatteryPixelGeometry(bodyPoints: CGSize(width: 20, height: 10), nubPoints: 1.6, scale: scale, increasedContrast: contrast))
            }
        }
    }

    // MARK: tailles en points

    @Test func theCardAndTheTabKeepTheirBodySizesAndGetAWholePointNub() {
        #expect(BatteryGlyphGeometry.cardBody == CGSize(width: 28, height: 13))
        #expect(BatteryGlyphGeometry.tabBody == CGSize(width: 32, height: 15))
        for (_, body, nub) in Self.bodies.dropFirst() {
            #expect(nub == nub.rounded() && nub >= 2, "bout d'un nombre entier de points : l'image a la même taille en points à toutes les échelles")
            #expect(abs(nub - max(1.5, body.height * 0.17)) <= 0.5 + 1e-9, "proche du bout d'avant (17 % de la hauteur)")
        }
    }

    @Test func theImageSizeInPointsIsWholeAndDoesNotDependOnTheScale() {
        for (name, body, nub) in Self.bodies {
            let size = BatteryPixelGeometry.imageSizePoints(bodyPoints: body, nubPoints: nub)
            #expect(size.width == (body.width + nub.rounded(.up)) && size.height >= body.height, "\(name)")
            #expect(size.width == size.width.rounded() && size.height == size.height.rounded(), "\(name)")
            for scale in 1...3 {
                let g = geometry(body, nub, scale)
                let origin = BatteryPixelGeometry.bodyOriginPoints(bodyPoints: body)
                #expect(g.verticalOverflow <= Int(origin.y) * scale, "\(name) \(scale)x : le repère tient dans la marge de l'image")
                #expect(Int(g.total.width) <= Int(size.width) * scale, "\(name) \(scale)x")
            }
        }
    }

    // MARK: pixels entiers

    @Test func theBodyIsTheBodyInPointsTimesTheScale() {
        for (name, body, nub) in Self.bodies {
            for scale in 1...3 {
                let g = geometry(body, nub, scale)
                #expect(g.body == PixelRect(x: 0, y: 0, width: Int(body.width) * scale, height: Int(body.height) * scale), "\(name) \(scale)x")
            }
        }
    }

    @Test func theLineIsWholePixelsOneAtOneXTwoAtTwoXAndContrastAddsAtLeastOnePixel() {
        for (name, body, nub) in Self.bodies {
            let table: [(scale: Int, line: Int)] = [(1, 1), (2, 2), (3, 4)]
            for row in table {
                let normal = geometry(body, nub, row.scale), strong = geometry(body, nub, row.scale, contrast: true)
                #expect(normal.lineWidth == row.line, "\(name) \(row.scale)x : \(normal.lineWidth)")
                #expect(strong.lineWidth > normal.lineWidth, "\(name) \(row.scale)x : « Augmenter le contraste » épaissit le trait")
                #expect(normal.gap >= 1 && normal.inner.width > 0 && normal.inner.height > 0)
                #expect(strong.inner.width > 0 && strong.inner.height > 0, "l'intérieur existe même avec le trait renforcé")
            }
        }
    }

    @Test func theNubIsCentredOnWholePixelsAndHalfTheBodyHeightAtMost() {
        for (name, body, nub) in Self.bodies {
            for scale in 1...3 {
                let g = geometry(body, nub, scale)
                #expect(g.nub.x == g.body.width && g.nub.width >= 1, "\(name) \(scale)x")
                #expect(g.nub.y * 2 + g.nub.height == g.body.height, "\(name) \(scale)x : centré sur des pixels entiers (corps de \(g.body.height) px)")
                #expect(g.nub.height * 2 <= g.body.height + 1, "\(name) \(scale)x : pas plus haut que la moitié du corps")
                #expect(g.nub.height >= 2)
            }
        }
        // Le bout de la carte et de l'onglet fait un nombre entier de points : le total tient dans l'image à toutes les échelles.
        for (name, body, nub) in Self.bodies.dropFirst() {
            for scale in 1...3 { #expect(geometry(body, nub, scale).nub.width == Int(nub) * scale, "\(name)") }
        }
    }

    @Test func theFillIsWholePixelsMonotonicWithASliverAndFullOnlyAtOneHundred() {
        for (name, body, nub) in Self.bodies {
            for scale in 1...3 {
                for contrast in [false, true] {
                    let g = geometry(body, nub, scale, contrast: contrast)
                    #expect(g.fillWidth(percent: 0) == 0 && g.fillWidth(percent: -3) == 0 && g.fillWidth(percent: .nan) == 0)
                    #expect(g.fillWidth(percent: 100) == g.inner.width && g.fillWidth(percent: 250) == g.inner.width)
                    var previous = 0
                    for percent in stride(from: 0.5, to: 100, by: 0.5) {
                        let w = g.fillWidth(percent: percent)
                        #expect(w >= previous, "\(name) \(scale)x \(percent) % : monotone")
                        #expect(w >= scale, "\(name) \(scale)x \(percent) % : au moins 1 pt (\(w) px)")
                        #expect(w <= g.inner.width - 1, "\(name) \(scale)x \(percent) % : seul 100 % est plein")
                        previous = w
                    }
                }
            }
        }
    }

    @Test func theCornerRadiiAreWholePixelsAndLeaveARoomForTheLine() {
        for (name, body, nub) in Self.bodies {
            for scale in 1...3 {
                let g = geometry(body, nub, scale)
                #expect(g.cornerRadius == g.cornerRadius.rounded() && g.cornerRadius >= 2, "\(name)")
                #expect(g.cornerRadius * 2 <= CGFloat(g.body.height), "\(name)")
                #expect(g.cornerRadius > CGFloat(g.lineWidth), "\(name) \(scale)x : le rayon intérieur reste positif")
            }
        }
    }

    // MARK: repères

    @Test func theMarksAreCentredOnWholePixelsHigherThanTheBodyAndWithinTheImageMargin() {
        for (name, body, nub) in Self.bodies {
            for scale in 1...3 {
                let g = geometry(body, nub, scale)
                for mark in [BatteryGlyphMark.bolt, .plug] {
                    let r = g.markRect(mark)
                    #expect(r.x * 2 + r.width == g.body.width, "\(name) \(scale)x \(mark) : centré en x sur des pixels entiers")
                    #expect(r.y * 2 + r.height == g.body.height, "\(name) \(scale)x \(mark) : centré en y sur des pixels entiers")
                    #expect(r.height == g.markHeight && r.height >= g.body.height)
                    let exact = Double(body.height) * Double(scale) * Double(BatteryGlyphGeometry.markScale)
                    #expect(abs(Double(r.height) - exact) <= 1.5, "\(name) \(scale)x : hauteur du repère \(r.height) px pour \(exact) attendus (même markScale que la barre)")
                    #expect(g.verticalOverflow == -r.y && g.verticalOverflow >= 1)
                    #expect(g.haloWidth >= 1)
                    #expect(r.x - g.haloWidth >= g.body.x + g.lineWidth, "\(name) \(scale)x \(mark) : le halo reste dans le corps")
                }
            }
        }
    }

    @Test func thePlugIsMadeOfSymmetricWholePixelRectanglesInsideItsBox() {
        for (name, body, nub) in Self.bodies {
            for scale in 1...3 {
                let g = geometry(body, nub, scale)
                let rects = g.plugRects, box = g.plugRect
                #expect(rects.count == 4)
                for r in rects { #expect(r.width >= 1 && r.height >= 1 && r.x >= box.x && r.maxX <= box.maxX && r.y >= box.y && r.maxY <= box.maxY, "\(name) \(scale)x") }
                #expect(rects[0].x - box.x == box.maxX - rects[1].maxX && rects[0].width == rects[1].width, "\(name) \(scale)x : dents symétriques")
                #expect(rects[3].x - box.x == box.maxX - rects[3].maxX, "\(name) \(scale)x : cordon centré")
            }
        }
    }

    @Test func theBoltVerticesStayInsideItsBoxAtEverySize() {
        for (name, body, nub) in Self.bodies {
            for scale in 1...3 {
                let g = geometry(body, nub, scale), r = g.boltRect.cgRect
                for p in g.boltPoints { #expect(r.insetBy(dx: -0.001, dy: -0.001).contains(p), "\(name) \(scale)x") }
            }
        }
    }

    // MARK: la grille

    @Test func parityPixelsAreTheNearestNumberOfTheGivenParity() {
        #expect(PixelGrid.px(4.2, scale: 1, parity: 0) == PixelGrid.evenPx(4.2, scale: 1))
        #expect(PixelGrid.px(6.6, scale: 2, parity: 0) == PixelGrid.evenPx(6.6, scale: 2))
        #expect(PixelGrid.px(5.0, scale: 1, parity: 1) == 5)
        #expect(PixelGrid.px(5.4, scale: 1, parity: 1) == 5)
        #expect(PixelGrid.px(6.2, scale: 1, parity: 1) == 7 || PixelGrid.px(6.2, scale: 1, parity: 1) == 5)
        #expect(PixelGrid.px(0.1, scale: 1, parity: 1) == 1 && PixelGrid.px(0.1, scale: 1, parity: 0) == 2, "jamais zéro")
        for scale in 1...3 { for tenth in 0...400 {
            let points = CGFloat(tenth) / 10
            #expect(PixelGrid.px(points, scale: scale, parity: 0) % 2 == 0 && PixelGrid.px(points, scale: scale, parity: 1) % 2 == 1)
        } }
    }
}
