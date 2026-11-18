import AppKit
import CoreText
import Foundation
import Testing
@testable import Soaro

/// SL23 : la mesure de netteté se vérifie d'abord sur des dessins synthétiques dont on connaît la réponse.
@MainActor @Suite struct SharpnessMetricTests {
    private func bitmap(width: Int, height: Int, draw: (CGContext) -> Void) throws -> GlyphInk {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        draw(context)
        return try GlyphInk(cg: try #require(context.makeImage()), scale: 1)
    }

    @Test func aBarOnWholePixelsHasNoIntermediatePixel() throws {
        let ink = try bitmap(width: 20, height: 10) { $0.fill(CGRect(x: 2, y: 3, width: 12, height: 2)) }
        let result = SharpnessMetric.edgeSoftness(ink, xs: 0..<20, ys: 0..<10)
        #expect(result.soft == 0 && result.inked == 24 && result.share == 0)
    }

    @Test func aBarBetweenPixelsIsSoft() throws {
        let ink = try bitmap(width: 20, height: 10) { $0.fill(CGRect(x: 2, y: 3.5, width: 12, height: 2)) }
        let result = SharpnessMetric.edgeSoftness(ink, xs: 0..<20, ys: 0..<10)
        #expect(result.soft == 24 && result.inked == 36, "deux lignes à moitié, une pleine : \(result)")
        #expect(abs(result.share - 2.0 / 3.0) < 1e-9)
    }

    @Test func aRegionWithoutInkIsNotSoft() throws {
        let ink = try bitmap(width: 8, height: 8) { _ in }
        #expect(SharpnessMetric.edgeSoftness(ink, xs: 0..<8, ys: 0..<8) == EdgeSoftness(soft: 0, inked: 0))
        #expect(SharpnessMetric.textEdgeHardness(ink, xs: 0..<8, ys: 0..<8) == nil)
    }

    @Test func aPointRegionIsConvertedToTheSmallestPixelRegionThatContainsIt() throws {
        let ink = try bitmap(width: 40, height: 20) { _ in }
        let two = try GlyphInk(cg: try #require(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()), scale: 2)
        let p = SharpnessMetric.pixels(of: CGRect(x: 1, y: 1.25, width: 3, height: 2), scale: 2, in: two)
        #expect(p.xs == 2..<8 && p.ys == 2..<7)
        #expect(SharpnessMetric.pixels(of: CGRect(x: 1, y: 1, width: 3, height: 2), scale: 1, in: ink).xs == 1..<4)
    }

    @Test func textOnAWholeBaselineIsHardAndOnAHalfPixelBaselineIsSoft() throws {
        // Corps choisi pour que la hauteur des capitales soit de 10 pixels exactement.
        let probe = CTFontCreateWithName("Helvetica" as CFString, 100, nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 10 / CTFontGetCapHeight(probe) * 100, nil)
        func word(baseline: CGFloat) throws -> SharpnessMetric.TextEdges {
            let ink = try bitmap(width: 60, height: 24) { context in
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: "HEH", attributes: [.font: font, .foregroundColor: NSColor.black]))
                context.setShouldAntialias(true)
                context.setShouldSubpixelPositionFonts(true)
                context.setShouldSubpixelQuantizeFonts(false)
                context.textPosition = CGPoint(x: 2, y: baseline)
                CTLineDraw(line, context)
            }
            return try #require(SharpnessMetric.textEdgeHardness(ink, xs: 0..<60, ys: 0..<24))
        }
        let whole = try word(baseline: 6), half = try word(baseline: 6.5)
        #expect(whole.hardness > 0.7, "ligne de base entière : \(whole)")
        #expect(half.hardness < whole.hardness - 0.2, "ligne de base à cheval : \(half) contre \(whole)")
    }

    @Test func theBoundsOfAColourAreTheBoundsOfItsPixelsInPoints() throws {
        let ink = try bitmap(width: 30, height: 20) { $0.fill(CGRect(x: 4, y: 5, width: 10, height: 6)) }
        let rect = try #require(SharpnessMetric.bounds(of: ink) { $0.a > 0.5 })
        #expect(rect == CGRect(x: 4, y: 20 - 11, width: 10, height: 6))
    }

    @Test func anImageIsReadAtTheExplicitScaleAsked() throws {
        let image = NSImage(size: NSSize(width: 10, height: 4), flipped: true) { rect in
            NSColor.black.set(); NSRect(x: 0, y: 0, width: 5, height: 4).fill(); return true
        }
        for scale in [1.0, 2.0, 3.0] as [CGFloat] {
            let ink = try GlyphInk(image: image, scale: scale)
            #expect(ink.width == Int(10 * scale) && ink.height == Int(4 * scale) && ink.scale == scale)
            #expect(ink.alpha(0, 0) > 0.99 && ink.alpha(ink.width - 1, 0) < 0.01)
        }
    }
}
