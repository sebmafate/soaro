import Foundation
import Testing
@testable import Soaro

/// Règles pures du toast (SL5) : style de mouvement selon Réduire les animations, texte annoncé à VoiceOver, durée.
@Suite struct ToastPresentationTests {
    @Test func motionStyleFollowsReduceMotion() {
        #expect(ToastPresentation.motionStyle(reduceMotion: false) == .slideAndFade)
        #expect(ToastPresentation.motionStyle(reduceMotion: true) == .fade)
    }

    @Test func announcementIsTheMessageVerbatim() {
        #expect(ToastPresentation.announcement(for: "History cleared") == "History cleared")
        let message = "5 GB freed · “iPhone 15” is running: quit it first."
        #expect(ToastPresentation.announcement(for: message) == message)
    }

    @Test func emptyOrBlankMessageIsNotAnnounced() {
        #expect(ToastPresentation.announcement(for: "") == nil)
        #expect(ToastPresentation.announcement(for: "   ") == nil)
        #expect(ToastPresentation.announcement(for: " \n\t ") == nil)
    }

    @Test func visibleDurationIsFourSeconds() {
        #expect(ToastPresentation.visibleDuration == .seconds(4))
    }

    // MARK: Câblage dans les vues (gardes au niveau du source ; l'animation elle-même se vérifie à la main)

    private func viewSource(_ name: String) throws -> String {
        let url = RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Views/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func panelAndWindowReadReduceMotionAndNoLongerHardCodeTheSlide() throws {
        for file in ["PopoverView.swift", "MainWindow.swift"] {
            let text = try viewSource(file)
            #expect(text.contains("accessibilityReduceMotion"), "\(file) doit lire Réduire les animations")
            #expect(!text.contains(".move(edge:"), "\(file) ne doit plus fixer le glissement lui-même")
            #expect(text.contains(".easeInOut(duration: 0.2)"), "\(file) garde l'animation de 0,2 s")
        }
    }

    @Test func theSlideIsDefinedInOnePlaceOnly() throws {
        let text = try viewSource("ToastTransition.swift")
        #expect(text.components(separatedBy: ".move(edge: .bottom)").count - 1 == 1)
    }
}
