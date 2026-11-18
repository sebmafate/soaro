import Foundation
import SwiftUI
import Testing
@testable import Soaro

/// Jetons de couleur de la barre mémoire (SL26 T2) : quatre couleurs sémantiques (applications, système, compressée,
/// cache) plus un ton neutre pour « non attribué », en clair, en sombre et avec « Augmenter le contraste ».
/// Les segments sont des éléments graphiques sans texte : au moins 3 : 1 contre la piste (WCAG 1.4.11).
@Suite struct MemoryBarContrastTests {
    private typealias Tokens = DesignTokens
    private static let kinds: [MemorySegmentKind] = [.app, .wired, .compressed, .cached, .unattributed]
    private static let modes: [(dark: Bool, increased: Bool)] = [(false, false), (false, true), (true, false), (true, true)]

    private func reference(dark: Bool) -> Tokens.RGB { dark ? Tokens.darkReferenceBackground : Tokens.lightReferenceBackground }

    // MARK: Piste

    @Test func theTrackIsTheForegroundColourAtALowAbsoluteOpacity() {
        #expect(Tokens.memoryTrackBase(dark: false) == .black)
        #expect(Tokens.memoryTrackBase(dark: true) == .white)
        #expect(abs(Tokens.memoryTrackAlpha(dark: false) - 0.10) < 0.0001)
        #expect(abs(Tokens.memoryTrackAlpha(dark: true) - 0.14) < 0.0001)
    }

    @Test func compositedMatchesTheAlphaContrastFunction() {
        let c = Tokens.composited(.black, alpha: 0.5, on: .white)
        #expect(abs(c.red - 0.5) < 1e-9 && abs(c.green - 0.5) < 1e-9 && abs(c.blue - 0.5) < 1e-9)
    }

    // MARK: Contraste des segments

    @Test(arguments: [false, true])
    func everySegmentIsAtLeast3To1AgainstTheTrackInLightAndDark(increased: Bool) {
        for dark in [false, true] {
            let track = Tokens.memoryTrackOnReference(dark: dark)
            for kind in Self.kinds {
                let ratio = Tokens.contrastRatio(Tokens.memorySegment(kind, dark: dark, contrastIncreased: increased), on: track)
                #expect(ratio >= 3, "\(kind) dark=\(dark) increased=\(increased) : \(ratio)")
            }
        }
    }

    @Test func increasedContrastNeverLowersTheContrastAgainstTheTrack() {
        for dark in [false, true] {
            let track = Tokens.memoryTrackOnReference(dark: dark)
            for kind in Self.kinds {
                let normal = Tokens.contrastRatio(Tokens.memorySegment(kind, dark: dark, contrastIncreased: false), on: track)
                let strong = Tokens.contrastRatio(Tokens.memorySegment(kind, dark: dark, contrastIncreased: true), on: track)
                #expect(strong > normal, "\(kind) dark=\(dark) : \(normal) -> \(strong)")
            }
        }
    }

    @Test func segmentsAlsoStandOutFromTheReferenceBackgroundForTheGapAndTheTrackEnds() {
        for (dark, increased) in Self.modes {
            for kind in Self.kinds {
                let ratio = Tokens.contrastRatio(Tokens.memorySegment(kind, dark: dark, contrastIncreased: increased), on: reference(dark: dark))
                #expect(ratio >= 3, "\(kind) dark=\(dark) increased=\(increased) : \(ratio)")
            }
        }
    }

    // MARK: Distinction entre les segments

    @Test func theFourKindsAreFourDifferentColoursInEveryMode() {
        for (dark, increased) in Self.modes {
            let colours = Self.kinds.map { Tokens.memorySegment($0, dark: dark, contrastIncreased: increased) }
            for i in colours.indices { for j in colours.indices where j > i {
                #expect(colours[i] != colours[j], "\(Self.kinds[i]) et \(Self.kinds[j]) ont la même couleur (dark=\(dark) increased=\(increased))")
            } }
        }
    }

    @Test func theThreeUsedHuesStayAwayFromThePressureColours() {
        // Teintes : l'ordre des teintes (bleu, violet, sarcelle) ne recoupe pas le vert, l'orange et le rouge de la pression.
        for (dark, increased) in Self.modes {
            for kind in [MemorySegmentKind.app, .wired, .compressed] {
                let c = Tokens.memorySegment(kind, dark: dark, contrastIncreased: increased)
                let hue = Self.hue(c)
                // Interdit : 0...70° (rouge, orange, jaune) et 80...150° (vert) ; permis : sarcelle 170...200°, bleu 200...260°, violet 250...290°.
                #expect(hue >= 165 && hue <= 295, "\(kind) dark=\(dark) increased=\(increased) teinte \(hue)°")
            }
        }
    }

    private static func hue(_ c: Tokens.RGB) -> Double {
        let mx = max(c.red, c.green, c.blue), mn = min(c.red, c.green, c.blue)
        let d = mx - mn
        guard d > 0 else { return 0 }
        var h: Double
        if mx == c.red { h = (c.green - c.blue) / d } else if mx == c.green { h = 2 + (c.blue - c.red) / d } else { h = 4 + (c.red - c.green) / d }
        h *= 60
        return h < 0 ? h + 360 : h
    }

    @Test func theNeutralTonesHaveNoHue() {
        for (dark, increased) in Self.modes {
            for kind in [MemorySegmentKind.cached, .unattributed] {
                let c = Tokens.memorySegment(kind, dark: dark, contrastIncreased: increased)
                #expect(abs(c.red - c.green) < 0.03 && abs(c.green - c.blue) < 0.04, "\(kind) doit être neutre")
            }
        }
    }

    // MARK: Cache : le contour porte le contraste

    @Test func theCacheFillIsLighterThanItsOutline() {
        #expect(Tokens.memoryCacheFillAlpha > 0 && Tokens.memoryCacheFillAlpha <= 0.35)
        for dark in [false, true] {
            let outline = Tokens.memorySegment(.cached, dark: dark, contrastIncreased: false)
            let fill = Tokens.composited(outline, alpha: Tokens.memoryCacheFillAlpha, on: Tokens.memoryTrackOnReference(dark: dark))
            let track = Tokens.memoryTrackOnReference(dark: dark)
            // Le remplissage est plus près de la piste que le contour : c'est l'« allégé » du cache.
            #expect(Tokens.contrastRatio(fill, on: track) < Tokens.contrastRatio(outline, on: track))
        }
    }

    // MARK: Valeurs documentées

    @Test func theHexValuesAreWrittenInDesignMD() throws {
        let design = try String(contentsOf: RepositoryRoot.url().appendingPathComponent("DESIGN.md"), encoding: .utf8).uppercased()
        for (dark, increased) in Self.modes {
            for kind in Self.kinds {
                let c = Tokens.memorySegment(kind, dark: dark, contrastIncreased: increased)
                let hex = String(format: "#%02X%02X%02X", Int((c.red * 255).rounded()), Int((c.green * 255).rounded()), Int((c.blue * 255).rounded()))
                #expect(design.contains(hex), "\(hex) (\(kind), dark=\(dark), increased=\(increased)) absent de DESIGN.md")
            }
        }
    }

    // MARK: Résolution depuis l'environnement

    @Test func theSegmentColourResolvesFromTheEnvironment() {
        for (dark, increased) in Self.modes {
            var environment = EnvironmentValues()
            environment.colorScheme = dark ? .dark : .light
            environment.colorSchemeContrast = increased ? .increased : .standard
            for kind in Self.kinds {
                let a = MemorySegmentStyle.color(kind, in: environment).resolve(in: environment)
                let t = Tokens.memorySegment(kind, dark: dark, contrastIncreased: increased)
                #expect(abs(Double(a.red) - t.red) < 0.003 && abs(Double(a.green) - t.green) < 0.003 && abs(Double(a.blue) - t.blue) < 0.003)
                #expect(a.opacity == 1)
            }
        }
    }
}
