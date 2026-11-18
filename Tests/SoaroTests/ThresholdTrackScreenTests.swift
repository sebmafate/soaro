import Foundation
import Testing
@testable import Soaro

/// SL17 : le source de l'écran respecte ce qui ne se voit pas dans un test de logique (plus de Stepper, éléments « réglables »,
/// clavier, zone de 24 pt, réglages d'accessibilité).
@Suite struct ThresholdTrackScreenTests {
    // MARK: Le source

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(relative), encoding: .utf8)
    }

    @Test func settingsNoLongerUsesSteppersAndPassesTheLiveValues() throws {
        let settings = try source("Sources/Soaro/Views/SettingsView.swift")
        #expect(!settings.contains("Stepper("))
        #expect(settings.contains("ThresholdLiveValues(snapshot: state.snapshot)"))
        #expect(settings.contains("current: live.load"))
        #expect(settings.contains("current: live.disk"))
        #expect(settings.contains("current: live.battery"))
        // Le bouton de réinitialisation, la note de la mémoire et l'en-tête restent.
        #expect(settings.contains("Button(\"Reset thresholds to defaults\")"))
        #expect(settings.contains("Memory has no threshold"))
        #expect(settings.contains("Section(\"Value colors\")"))
    }

    @Test func theTrackHandlesAreAdjustableFocusableAndKeyboardDriven() throws {
        let track = try source("Sources/Soaro/Views/ThresholdTrack.swift")
        #expect(track.contains(".accessibilityAdjustableAction"))
        #expect(track.contains(".accessibilityLabel("))
        #expect(track.contains(".accessibilityValue("))
        #expect(track.contains(".focusable("))
        #expect(track.contains(".onKeyPress("))
        #expect(track.contains("ThresholdTrackMetrics.hitSize"))
        #expect(track.contains("accessibilityReduceTransparency"))
        #expect(track.contains("colorSchemeContrast"))
        #expect(!track.contains("Stepper("))
        // Pas d'animation : rien à adapter à « Réduire les animations ».
        #expect(!track.contains("withAnimation") && !track.contains(".animation("))
        // Pas de taille de police fixe (DESIGN.md partie 2).
        #expect(!track.contains(".system(size:"))
    }

    @Test func oneGestureOnTheTrackPicksTheHandleByDistance() throws {
        // Les poignées se recouvrent (3 pt d'écart) : un seul geste sur la piste choisit la plus proche (`pickHandle`), pas celle du dessus.
        let track = try source("Sources/Soaro/Views/ThresholdTrack.swift")
        #expect(track.components(separatedBy: "DragGesture(").count == 2, "un seul DragGesture attendu")
        #expect(track.contains("pickHandle("))
        #expect(track.contains("resolve("))
    }

    @Test func stepAndGapAreEachOneNamedConstant() throws {
        let logic = try source("Sources/Soaro/Views/ThresholdTrackLogic.swift")
        #expect(logic.components(separatedBy: "static let step = ").count == 2)
        #expect(logic.components(separatedBy: "static let minimumGap = ").count == 2)
    }
}
