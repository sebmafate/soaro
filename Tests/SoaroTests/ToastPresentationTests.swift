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
}
