import Foundation
import Testing
@testable import Soaro

/// Calcul pur de la barre mémoire segmentée (SL26 T1) : des octets en plages de pixels entiers.
/// Aucune vue, aucun rendu : on vérifie les proportions, l'ordre, les bornes, le pixel minimal et la somme.
@Suite struct MemoryBarLayoutTests {
    private let GB: UInt64 = 1_073_741_824
    private func gb(_ x: Double) -> UInt64 { UInt64((x * Double(GB)).rounded()) }

    /// Les chiffres de la capture de l'auteur : 4,03 + 2,83 + 5,8 = 12,66 Go « utilisés », 2,45 Go en cache, 16 Go au total.
    private func screenshot(width: Double = 400, scale: Double = 1, gap: Int = 0) -> MemoryBarLayout {
        MemoryBarLayout.make(app: gb(4.03), wired: gb(2.83), compressed: gb(5.8), cached: gb(2.45),
                             used: gb(4.03) + gb(2.83) + gb(5.8), total: 16 * GB,
                             trackWidth: width, scale: scale, gapPixels: gap)
    }

    private func kinds(_ layout: MemoryBarLayout) -> [MemorySegmentKind] { layout.segments.map(\.kind) }

    // MARK: Ordre et proportions

    @Test func theSegmentsComeInTheOrderApplicationsSystemCompressedCache() {
        #expect(kinds(screenshot()) == [.app, .wired, .compressed, .cached])
    }

    @Test func widthsAreProportionalToTheBytesOverTheTotalRAM() {
        let layout = screenshot(width: 1600, scale: 1, gap: 0)
        let expected: [Double] = [4.03, 2.83, 5.8, 2.45].map { $0 / 16 * 1600 }
        for (segment, ideal) in zip(layout.segments, expected) {
            #expect(abs(Double(segment.width) - ideal) <= 1.01, "\(segment.kind): \(segment.width) px pour \(ideal)")
        }
    }

    @Test func theTrackIsTheWholeRAMNotTheUsedPart() {
        // 12,66 Go utilisés sur 16 : le dernier segment utilisé s'arrête à 79 % de la piste, pas à 100 %.
        let layout = screenshot(width: 1600, scale: 1, gap: 0)
        let compressed = layout.segments[2]
        #expect(abs(Double(compressed.endPixel) - 12.66 / 16 * 1600) <= 1.01)
        #expect(layout.trackPixels == 1600)
    }

    @Test func theCacheStartsWhereTheUsedPartEnds() {
        let layout = screenshot(width: 1600, scale: 1, gap: 0)
        #expect(layout.segments[3].startPixel == layout.segments[2].endPixel)
    }

    @Test func theRestOfTheTrackIsLeftFree() {
        let layout = screenshot(width: 1600, scale: 1, gap: 0)
        let last = layout.segments.last!.endPixel
        // (4,03 + 2,83 + 5,8 + 2,45) / 16 = 94,3 % : il reste 5,7 % de piste libre.
        #expect(last < layout.trackPixels)
        #expect(abs(Double(last) - 15.11 / 16 * 1600) <= 1.01)
    }

    @Test func theCacheIsNeverCountedAsUsed() {
        let layout = screenshot()
        let used = layout.segments.filter { $0.kind != .cached }.map(\.bytes).reduce(0, +)
        #expect(abs(used - Double(gb(12.66))) < Double(GB) * 0.01)
        let cache = layout.segments.first { $0.kind == .cached }
        #expect(cache?.bytes == Double(gb(2.45)))
    }

    // MARK: Pixels entiers, 1x et 2x

    @Test func boundariesAreWholePixelsAtScaleOneAndTwo() {
        for scale in [1.0, 2.0] {
            let layout = screenshot(width: 333.5, scale: scale, gap: 1)
            #expect(layout.trackPixels == Int((333.5 * scale).rounded(.down)))
            for s in layout.segments {
                // Les types sont des `Int` : un pixel entier par construction ; on vérifie la plage.
                #expect(s.startPixel >= 0 && s.endPixel <= layout.trackPixels && s.startPixel < s.endPixel)
            }
        }
    }

    @Test func theTrackWidthInPixelsFollowsTheScale() {
        #expect(screenshot(width: 300, scale: 1).trackPixels == 300)
        #expect(screenshot(width: 300, scale: 2).trackPixels == 600)
        // 300,75 pt à 1x ne tombe pas sur un pixel : on arrondit vers le bas, la piste ne dépasse jamais.
        #expect(screenshot(width: 300.75, scale: 1).trackPixels == 300)
        #expect(screenshot(width: 300.75, scale: 2).trackPixels == 601)
    }

    @Test func theSameBytesGiveTwiceThePixelsAtTwoX() {
        let one = screenshot(width: 300, scale: 1, gap: 0)
        let two = screenshot(width: 300, scale: 2, gap: 0)
        for (a, b) in zip(one.segments, two.segments) {
            #expect(abs(Double(b.endPixel) - 2 * Double(a.endPixel)) <= 2)
        }
    }

    // MARK: Séparateurs

    @Test func segmentsAreSeparatedByTheGapAndNeverOverlap() {
        for gap in [0, 1, 2] {
            let layout = screenshot(width: 400, scale: 2, gap: gap)
            for (a, b) in zip(layout.segments, layout.segments.dropFirst()) {
                #expect(b.startPixel - a.endPixel == gap, "écart \(gap) px entre \(a.kind) et \(b.kind)")
            }
        }
    }

    @Test func theLastSegmentKeepsItsFullWidthWithNoGapAfterIt() {
        let withGap = screenshot(width: 400, scale: 1, gap: 1)
        let without = screenshot(width: 400, scale: 1, gap: 0)
        #expect(withGap.segments.last!.endPixel == without.segments.last!.endPixel)
    }

    // MARK: Somme et bornes

    @Test func theSumOfTheSegmentsNeverExceedsTheTrack() {
        for width in stride(from: 1.0, through: 120.0, by: 7) {
            for scale in [1.0, 2.0] {
                for gap in [0, 1] {
                    let layout = MemoryBarLayout.make(app: gb(7), wired: gb(5), compressed: gb(4), cached: gb(3), used: gb(16),
                                                      total: 16 * GB, trackWidth: width, scale: scale, gapPixels: gap)
                    let covered = layout.segments.reduce(0) { $0 + $1.width }
                    #expect(covered <= layout.trackPixels, "largeur \(width) x\(scale) écart \(gap)")
                    for s in layout.segments { #expect(s.endPixel <= layout.trackPixels) }
                }
            }
        }
    }

    @Test func aFullMachineFillsTheTrackToItsLastPixel() {
        let layout = MemoryBarLayout.make(app: gb(8), wired: gb(4), compressed: gb(4), cached: 0, used: gb(16),
                                          total: 16 * GB, trackWidth: 301, scale: 2, gapPixels: 0)
        #expect(layout.segments.last?.endPixel == layout.trackPixels)
        #expect(layout.segments.first?.startPixel == 0)
    }

    @Test func aTinyNonZeroSegmentIsAtLeastOnePixelWide() {
        // 1 Mo de compressé sur 16 Go à 300 pt : 0,02 px, mais on veut le voir.
        let layout = MemoryBarLayout.make(app: gb(8), wired: gb(3), compressed: 1_048_576, cached: gb(2),
                                          used: gb(11) + 1_048_576, total: 16 * GB, trackWidth: 300, scale: 1, gapPixels: 1)
        let compressed = layout.segments.first { $0.kind == .compressed }
        #expect((compressed?.width ?? 0) >= 1)
    }

    @Test func theMinimumPixelNeverMakesTheSumExceedTheTrack() {
        let layout = MemoryBarLayout.make(app: gb(15.999), wired: 1_048_576, compressed: 1_048_576, cached: 0,
                                          used: 16 * GB, total: 16 * GB, trackWidth: 100, scale: 1, gapPixels: 1)
        #expect(layout.segments.reduce(0) { $0 + $1.width } <= layout.trackPixels)
        #expect(layout.segments.allSatisfy { $0.width >= 1 })
        #expect(kinds(layout) == [.app, .wired, .compressed], "les trois segments restent visibles, le pixel est repris sur le plus large")
        #expect(layout.segments[0].width >= 96)
        #expect(layout.segments.last!.endPixel <= layout.trackPixels)
    }

    @Test func aZeroByteCategoryDrawsNothing() {
        let layout = MemoryBarLayout.make(app: gb(4), wired: gb(2), compressed: 0, cached: 0, used: gb(6),
                                          total: 16 * GB, trackWidth: 300, scale: 2, gapPixels: 1)
        #expect(kinds(layout) == [.app, .wired])
    }

    // MARK: Écart entre les catégories et « utilisé »

    @Test func categoriesSlightlyAboveTheUsedFigureAreScaledDownToIt() {
        // 12,66 Go de catégories pour 12,5 Go utilisés (1 % du total) : on met à l'échelle, sans trou ni dépassement.
        let layout = MemoryBarLayout.make(app: gb(4.03), wired: gb(2.83), compressed: gb(5.8), cached: 0, used: gb(12.5),
                                          total: 16 * GB, trackWidth: 1600, scale: 1, gapPixels: 0)
        let used = layout.segments.map(\.bytes).reduce(0, +)
        #expect(abs(used - Double(gb(12.5))) < 2)
        #expect(layout.segments.last!.endPixel <= Int((12.5 / 16 * 1600).rounded()))
    }

    @Test func categoriesSlightlyBelowTheUsedFigureAreScaledUpToItSoNoHoleRemains() {
        let layout = MemoryBarLayout.make(app: gb(4), wired: gb(2.8), compressed: gb(5.5), cached: 0, used: gb(12.5),
                                          total: 16 * GB, trackWidth: 1600, scale: 1, gapPixels: 0)
        #expect(kinds(layout) == [.app, .wired, .compressed])
        #expect(abs(Double(layout.segments.last!.endPixel) - 12.5 / 16 * 1600) <= 1.01)
    }

    @Test func aBigShortfallIsDrawnAsAnUnattributedNeutralSegment() {
        // 6 Go de catégories connues, 12 Go utilisés : 6 Go (37 %) ne s'expliquent pas, on ne les invente pas.
        let layout = MemoryBarLayout.make(app: gb(4), wired: gb(2), compressed: 0, cached: gb(1), used: gb(12),
                                          total: 16 * GB, trackWidth: 1600, scale: 1, gapPixels: 0)
        #expect(kinds(layout) == [.app, .wired, .unattributed, .cached])
        let neutral = layout.segments[2]
        #expect(abs(neutral.bytes - Double(gb(6))) < 2)
        #expect(layout.segments[0].bytes == Double(gb(4)))      // les catégories connues ne sont pas déformées
    }

    @Test func aBigExcessIsDrawnAsIsWithoutScalingAndStaysInsideTheTrack() {
        let layout = MemoryBarLayout.make(app: gb(6), wired: gb(4), compressed: gb(4), cached: 0, used: gb(8),
                                          total: 16 * GB, trackWidth: 1600, scale: 1, gapPixels: 0)
        #expect(kinds(layout) == [.app, .wired, .compressed])
        #expect(layout.segments[0].bytes == Double(gb(6)))
        #expect(layout.segments.last!.endPixel <= layout.trackPixels)
    }

    @Test func categoriesAboveTheTotalAreScaledToFitTheTrack() {
        let layout = MemoryBarLayout.make(app: gb(10), wired: gb(8), compressed: gb(6), cached: gb(4), used: gb(24),
                                          total: 16 * GB, trackWidth: 500, scale: 1, gapPixels: 0)
        #expect(layout.segments.reduce(0) { $0 + $1.width } <= 500)
        #expect(layout.segments.last!.endPixel <= 500)
        #expect(!kinds(layout).contains(.cached))     // plus de place : le cache n'est pas dessiné
        // Mises à l'échelle ensemble : la somme des octets représentés ne dépasse pas le total, les parts restent 10 : 8 : 6.
        #expect(layout.segments.map(\.bytes).reduce(0, +) <= Double(16 * GB) * (1 + 1e-9))
        #expect(abs(layout.segments[0].bytes / layout.segments[2].bytes - 10.0 / 6.0) < 1e-6)
        #expect(abs(Double(layout.segments[0].width) - 10.0 / 24.0 * 500) <= 1.01)
    }

    @Test func theCacheIsCutToTheFreeSpace() {
        let layout = MemoryBarLayout.make(app: gb(8), wired: gb(3), compressed: gb(3), cached: gb(10), used: gb(14),
                                          total: 16 * GB, trackWidth: 1600, scale: 1, gapPixels: 0)
        let cache = layout.segments.last!
        #expect(cache.kind == .cached)
        #expect(cache.endPixel <= layout.trackPixels)
        #expect(abs(cache.bytes - Double(2 * GB)) < 2)
    }

    @Test func theUsedFigureCanBeOmittedAndDefaultsToTheSumOfTheCategories() {
        let layout = MemoryBarLayout.make(app: gb(4), wired: gb(2), compressed: gb(1), cached: gb(1), used: nil,
                                          total: 16 * GB, trackWidth: 1600, scale: 1, gapPixels: 0)
        #expect(kinds(layout) == [.app, .wired, .compressed, .cached])
    }

    // MARK: Valeurs absentes ou nulles

    @Test func aTotalOfZeroDrawsAnEmptyTrack() {
        let layout = MemoryBarLayout.make(app: gb(1), wired: gb(1), compressed: gb(1), cached: gb(1), used: gb(3),
                                          total: 0, trackWidth: 300, scale: 2)
        #expect(layout.segments.isEmpty)
    }

    @Test func aMissingTotalDrawsAnEmptyTrack() {
        #expect(MemoryBarLayout.make(memory: nil, trackWidth: 300, scale: 2).segments.isEmpty)
        #expect(MemoryBarLayout.make(app: 1, wired: 1, compressed: 1, cached: 1, used: 3, total: nil,
                                     trackWidth: 300, scale: 2).segments.isEmpty)
    }

    @Test func missingCategoriesAreSkipped() {
        let layout = MemoryBarLayout.make(app: gb(4), wired: nil, compressed: nil, cached: nil, used: gb(4),
                                          total: 16 * GB, trackWidth: 300, scale: 1, gapPixels: 0)
        #expect(kinds(layout) == [.app])
    }

    @Test func allCategoriesMissingButAUsedFigureDrawsOneNeutralSegment() {
        let layout = MemoryBarLayout.make(app: nil, wired: nil, compressed: nil, cached: nil, used: gb(8),
                                          total: 16 * GB, trackWidth: 320, scale: 1, gapPixels: 0)
        #expect(kinds(layout) == [.unattributed])
        #expect(layout.segments[0].endPixel == 160)
    }

    @Test func nothingUsedAndNothingCachedDrawsNoSegment() {
        let layout = MemoryBarLayout.make(app: 0, wired: 0, compressed: 0, cached: 0, used: 0,
                                          total: 16 * GB, trackWidth: 300, scale: 1)
        #expect(layout.segments.isEmpty)
        #expect(layout.trackPixels == 300)
    }

    @Test func aZeroWidthTrackDrawsNothing() {
        let layout = screenshot(width: 0)
        #expect(layout.segments.isEmpty)
        #expect(layout.trackPixels == 0)
    }

    @Test func aNegativeOrNonFiniteWidthDrawsNothing() {
        #expect(screenshot(width: -10).segments.isEmpty)
        #expect(screenshot(width: .nan).segments.isEmpty)
        #expect(screenshot(width: .infinity).segments.isEmpty)
        #expect(screenshot(width: 100, scale: 0).segments.isEmpty)
    }

    @Test func absurdByteCountsDoNotTrap() {
        let layout = MemoryBarLayout.make(app: .max, wired: .max, compressed: .max, cached: .max, used: .max,
                                          total: .max, trackWidth: 300, scale: 2)
        #expect(layout.segments.reduce(0) { $0 + $1.width } <= layout.trackPixels)
        #expect(layout.segments.map(\.bytes).reduce(0, +) <= Double(UInt64.max) * (1 + 1e-9))
    }

    // MARK: Depuis le modèle

    @Test func fromTheModelUsesItsFieldsAndItsUsedFigure() {
        let m = MemoryStats(total: 16 * GB, app: gb(4.03), wired: gb(2.83), compressed: gb(5.8), cached: gb(2.45),
                            swapUsed: gb(6.41), pressure: .warning)
        let a = MemoryBarLayout.make(memory: m, trackWidth: 400, scale: 2)
        let b = MemoryBarLayout.make(app: m.app, wired: m.wired, compressed: m.compressed, cached: m.cached,
                                     used: m.used, total: m.total, trackWidth: 400, scale: 2)
        #expect(a == b)
    }

    @Test func swapIsNeverDrawn() {
        // Le swap est sur le disque, pas dans la RAM : il ne change pas la barre.
        func layout(swap: UInt64) -> MemoryBarLayout {
            MemoryBarLayout.make(memory: MemoryStats(total: 16 * GB, app: gb(4), wired: gb(2), compressed: gb(1), cached: gb(1),
                                                     swapUsed: swap, pressure: .normal), trackWidth: 400, scale: 2)
        }
        #expect(layout(swap: 0) == layout(swap: 40 * GB))
    }
}
