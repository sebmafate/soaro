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
        // Aux valeurs extrêmes, la poignée ne sort pas de la vue, et les étiquettes tiennent dedans, pour tous les états de la grille de test.
        let width = Metrics.narrowestContentWidth
        let t = LevelThresholds(medium: 85, high: 90, critical: 100)
        let image = try render(t, ascending: true, current: nil, width: width, dark: false)
        let pixel = try #require(image.color(xOf(100, width: width), cy))
        #expect(pixel.r > 0.95 && pixel.g > 0.95 && pixel.b > 0.95)
        #expect(xOf(100, width: width) + Double(Metrics.hitSize) / 2 <= width)
        #expect(xOf(Logic.lowestValue, width: width) - Double(Metrics.hitSize) / 2 >= 0)
    }

    typealias Logic = ThresholdTrackLogic

    /// Un pixel et ses voisins à 1 pt : y a-t-il de l'encre (une couleur loin du fond) ?
    func inked(_ image: Render, _ x: Double, _ y: Double, background: (r: Double, g: Double, b: Double)) -> Bool {
        for dx in [-1.0, 0, 1] {
            for dy in [-1.0, 0, 1] {
                guard let c = image.color(x + dx, y + dy) else { continue }
                if abs(c.r - background.r) > 0.2 || abs(c.g - background.g) > 0.2 || abs(c.b - background.b) > 0.2 { return true }
            }
        }
        return false
    }

    /// Le pire cas : trois seuils à 1 point d'écart, dans les deux sens, aux deux largeurs, en clair et en sombre.
    /// Chaque étiquette est dessinée (sa bordure colorée), chaque trait de rappel est dessiné à mi-hauteur, chaque poignée a son centre blanc.
    @Test func theWorstCaseThreeThresholdsOnePointApartDrawsEveryLabelLeaderAndHandle() throws {
        let cases: [(LevelThresholds, Bool)] = [
            (LevelThresholds(medium: 50, high: 51, critical: 52), true),
            (LevelThresholds(medium: 1, high: 2, critical: 3), true),
            (LevelThresholds(medium: 98, high: 99, critical: 100), true),
            (LevelThresholds(medium: 52, high: 51, critical: 50), false),
            (LevelThresholds(medium: 99, high: 98, critical: 97), false),
            (LevelThresholds(medium: 3, high: 2, critical: 1), false),
        ]
        for width in Self.widths { for dark in [false, true] { for (t, ascending) in cases {
            let image = try render(t, ascending: ascending, current: nil, width: width, dark: dark)
            let background = try #require(image.color(2, 2))
            let unit = Metrics.pointsPerUnit(forWidth: width)
            let placements = Logic.labelPlacements(for: t, pointsPerUnit: unit, width: width)
            for handle in ThresholdHandle.allCases {
                let p = try #require(placements[handle])
                let label = "\(handle) \(t) largeur \(width) sombre \(dark)"
                // Bordure haute de l'étiquette (1,5 pt de la couleur du seuil) : de l'encre au milieu de son bord supérieur.
                #expect(inked(image, p.labelCentre, Double(Metrics.labelTop) + 0.75, background: background), "étiquette absente : \(label)")
                // Trait de rappel à mi-hauteur entre le bas de l'étiquette et le centre de la poignée.
                let top = Double(Metrics.labelTop + Metrics.labelHeight), bottom = Double(Metrics.centreY)
                let mid = (p.labelCentre + p.handleX) / 2
                #expect(inked(image, mid, (top + bottom) / 2, background: background), "trait absent : \(label)")
                // Le centre de la poignée est blanc quand aucune autre ne la recouvre de près ; la dernière dessinée (l'écarlate, ou la
                // poignée saisie) est toujours entière. Les autres se recouvrent à 3 pt d'écart : leur centre peut toucher l'anneau d'une voisine.
                let neighbours = ThresholdHandle.allCases.filter { $0 != handle }.compactMap { placements[$0]?.handleX }
                if handle == .scarlet || neighbours.allSatisfy({ abs($0 - p.handleX) > 8 }) {
                    let centre = try #require(image.color(p.handleX, cy))
                    #expect(centre.r > 0.95 && centre.g > 0.95 && centre.b > 0.95, "centre de la poignée : \(label)")
                }
            }
        } } }
    }

    @Test func theLabelsOfTheWorstCaseAreSideBySideAndEachInItsOwnColour() throws {
        // Les trois bordures d'étiquette sont de couleurs de seuil différentes de gauche à droite (orange, rouge, écarlate ; l'inverse pour la batterie).
        let width = Metrics.narrowestContentWidth
        let t = LevelThresholds(medium: 50, high: 51, critical: 52)
        let image = try render(t, ascending: true, current: nil, width: width, dark: false)
        let placements = Logic.labelPlacements(for: t, pointsPerUnit: Metrics.pointsPerUnit(forWidth: width), width: width)
        let y = Double(Metrics.labelTop) + 0.75
        let orangePlacement = try #require(placements[.orange])
        let redPlacement = try #require(placements[.red])
        let scarletPlacement = try #require(placements[.scarlet])
        let orange = try #require(image.color(orangePlacement.labelCentre, y))
        let scarlet = try #require(image.color(scarletPlacement.labelCentre, y))
        #expect(orange.g > 0.4 && orange.g < 0.75 && orange.r > 0.85, "orange : \(orange)")
        #expect(scarlet.g < 0.4 && scarlet.r > 0.85, "écarlate : \(scarlet)")
        #expect(orangePlacement.labelCentre < redPlacement.labelCentre && redPlacement.labelCentre < scarletPlacement.labelCentre)
    }
}
