import AppKit
import SwiftUI
import Testing
@testable import Soaro

/// SL17 : rendu hors écran de la piste (sans fenêtre, sans fichier écrit) : les poignées sont à la position de leur valeur,
/// les bandes suivent les poignées, le repère « now » est caché quand la valeur est inconnue, et tout tient dans la largeur la plus
/// étroite des réglages (panneau de 430 pt) comme dans la fenêtre, en clair et en sombre. Ce que le rendu ne dit pas (le geste réel,
/// VoiceOver, le clavier) reste à vérifier à la main.
@MainActor @Suite struct ThresholdTrackRenderTests {
    typealias Metrics = ThresholdTrackMetrics

    struct Host: View {
        @State var thresholds: LevelThresholds
        let ascending: Bool
        let current: Double?
        var body: some View { ThresholdTrack(thresholds: $thresholds, ascending: ascending, current: current) }
    }

    /// Rend la vue à la largeur donnée ; `color(x, y)` lit un pixel en points (origine en haut à gauche).
    struct Render {
        let rep: NSBitmapImageRep
        let scale: Double
        func color(_ x: Double, _ y: Double) -> (r: Double, g: Double, b: Double)? {
            guard let c = rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB) else { return nil }
            return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
        }
    }

    func render(_ thresholds: LevelThresholds, ascending: Bool, current: Double?, width: Double, dark: Bool) throws -> Render {
        let size = CGSize(width: width, height: Double(Metrics.totalHeight))
        let view = Host(thresholds: thresholds, ascending: ascending, current: current)
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return Render(rep: rep, scale: Double(rep.pixelsWide) / size.width)
    }

    func xOf(_ value: Int, width: Double) -> Double {
        Double(Metrics.inset) + Double(value) * Metrics.pointsPerUnit(forWidth: width)
    }

    static let widths = [Metrics.narrowestContentWidth, 700.0]
    let cy = Double(Metrics.centreY)

    @Test func eachHandleIsDrawnAtItsValueWithAWhiteCentre() throws {
        let states: [(LevelThresholds, Bool)] = [
            (LevelThresholds(medium: 60, high: 80, critical: 95), true),
            (LevelThresholds(medium: 60, high: 65, critical: 70), true),
            (LevelThresholds(medium: 20, high: 10, critical: 5), false),
            (LevelThresholds(medium: 95, high: 90, critical: 85), false),
        ]
        for width in Self.widths { for dark in [false, true] { for (t, ascending) in states {
            let image = try render(t, ascending: ascending, current: nil, width: width, dark: dark)
            for handle in ThresholdHandle.allCases {
                let value = ThresholdTrackLogic.value(of: handle, in: t)
                let pixel = try #require(image.color(xOf(value, width: width), cy))
                #expect(pixel.r > 0.95 && pixel.g > 0.95 && pixel.b > 0.95, "\(handle) à \(value) : le centre n'est pas blanc (\(pixel)), largeur \(width), sombre \(dark)")
            }
        } } }
    }

    @Test func theBandsFollowTheHandles() throws {
        // Croissant 60 / 80 / 95 : vert, orange, rouge, écarlate (la piste est vue à 4 pt du bord haut du trait, loin des poignées).
        let t = LevelThresholds(medium: 60, high: 80, critical: 95)
        let width = Metrics.narrowestContentWidth
        let image = try render(t, ascending: true, current: nil, width: width, dark: false)
        let y = cy + 3
        let normal = try #require(image.color(xOf(30, width: width), y))
        let orange = try #require(image.color(xOf(70, width: width), y))
        let red = try #require(image.color(xOf(87, width: width), y))
        #expect(normal.g > normal.r && normal.g > normal.b)                 // vert
        #expect(orange.r > 0.9 && orange.g > 0.45 && orange.g < 0.7 && orange.b < 0.3)
        #expect(red.r > 0.9 && red.g < 0.35 && red.b < 0.35)
        // Batterie 20 / 10 / 5 : l'écarlate commence à gauche, le vert à droite.
        let battery = try render(LevelThresholds(medium: 20, high: 10, critical: 5), ascending: false, current: nil, width: width, dark: false)
        let right = try #require(battery.color(xOf(60, width: width), y))
        let orangeLeft = try #require(battery.color(xOf(15, width: width), y))
        #expect(right.g > right.r && right.g > right.b)
        #expect(orangeLeft.r > 0.9 && orangeLeft.g > 0.45 && orangeLeft.g < 0.7)
    }

    @Test func theNowMarkerShowsWhereTheValueIsAndIsHiddenWhenUnknown() throws {
        let t = LevelThresholds(medium: 60, high: 80, critical: 95)
        let width = Metrics.narrowestContentWidth
        let x = xOf(36, width: width)
        let with = try render(t, ascending: true, current: 36, width: width, dark: false)
        let without = try render(t, ascending: true, current: nil, width: width, dark: false)
        // Au-dessus de la bande (la bande a 10 pt de haut, le repère 18 pt) : sombre avec repère, fond de fenêtre sans.
        let marker = try #require(with.color(x, cy - 7))
        let absent = try #require(without.color(x, cy - 7))
        #expect(marker.r < 0.4 && marker.g < 0.4 && marker.b < 0.4, "repère absent : \(marker)")
        #expect(absent.r > 0.8 && absent.g > 0.8 && absent.b > 0.8, "repère présent sans valeur : \(absent)")
    }

    @Test func nothingIsDrawnBeyondTheTrackMargins() throws {
        // Aux valeurs extrêmes, la poignée et l'étiquette ne sortent pas de la vue (rien n'est rogné à droite).
        let width = Metrics.narrowestContentWidth
        let t = LevelThresholds(medium: 85, high: 90, critical: 100)
        let image = try render(t, ascending: true, current: nil, width: width, dark: false)
        let pixel = try #require(image.color(xOf(100, width: width), cy))
        #expect(pixel.r > 0.95 && pixel.g > 0.95 && pixel.b > 0.95)
        #expect(xOf(100, width: width) + Double(Metrics.hitSize) / 2 <= width)
        // L'étiquette décalée par la tige tient aussi, pour tous les états possibles, des deux côtés.
        for ascending in [true, false] {
            for state in ThresholdTrackLogicTests.gridStates(ascending: ascending) {
                let placements = ThresholdTrackLogic.labelPlacements(for: state, pointsPerUnit: Metrics.pointsPerUnit(forWidth: width))
                for handle in ThresholdHandle.allCases {
                    let centre = xOf(ThresholdTrackLogic.value(of: handle, in: state), width: width) + (placements[handle]?.shift ?? 0)
                    #expect(centre + Metrics.labelWidth / 2 <= width && centre - Metrics.labelWidth / 2 >= 0, "\(state) \(handle)")
                }
            }
        }
    }
}
