import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Soaro

/// SL21 : l'icône de batterie « comme celle de macOS » (contour, bout, remplissage continu, éclair en charge).
/// Ici : la géométrie de RÉFÉRENCE en points (celle que lisent les tests de la barre de menus) et la lecture de pixels `GlyphInk`. Le dessin lui-même (SL24)
/// est en pixels entiers : voir `BatteryPixelGeometryGenericTests` et `BatteryGlyphImageTests`. La vraie barre de menus (teinte réelle, Mac à encoche) se vérifie à la main.

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

    @Test func theSameGlyphScalesToTheCardAndTheTab() {
        let card = BatteryGlyphGeometry(body: BatteryGlyphGeometry.cardBody)
        #expect(abs(card.innerRect.width - 24) < 1e-9)
        #expect(abs(card.fillWidth(percent: 100) - 24) < 1e-9)
        #expect(card.totalSize.height == 13)
        let tab = BatteryGlyphGeometry(body: BatteryGlyphGeometry.tabBody)
        #expect(tab.totalSize.height == 15 && tab.totalSize.width > 32)
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

    /// Image d'une image AppKit (le libellé de la barre de menus), à l'échelle 2 (SL23 : explicite, plus celle de l'écran de la machine qui lance le test).
    init(image: NSImage) throws {
        try self.init(image: image, scale: 2)
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
