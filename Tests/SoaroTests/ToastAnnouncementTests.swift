import Foundation
import Testing
@testable import Soaro

/// Annonce VoiceOver des toasts (SL5) : `AppState.showToast` appelle l'annonceur injecté, une fois par toast.
/// L'annonceur est un enregistreur : aucun test ne poste de vraie notification d'accessibilité, aucun n'attend les 4 s.
@MainActor
private final class Recorder {
    private(set) var messages: [String] = []
    var announce: @MainActor (String) -> Void { { [self] in messages.append($0) } }
}

@MainActor
@Suite struct ToastAnnouncementTests {
    private func makeState(_ recorder: Recorder) -> AppState {
        AppState(history: nil, demo: true, confirm: { _, _, _, _ in false },
                 clean: { _ in CleanupResult(freed: 0, failures: 0, error: nil) },
                 terminateApp: { _ in false }, announce: recorder.announce)
    }

    @Test func showToastSetsTheToastAndAnnouncesItOnce() {
        let recorder = Recorder()
        let state = makeState(recorder)

        state.showToast("Tips shown again")

        #expect(state.toast == "Tips shown again")
        #expect(recorder.messages == ["Tips shown again"])
    }

    @Test func twoToastsAreAnnouncedInOrder() {
        let recorder = Recorder()
        let state = makeState(recorder)

        state.showToast("History cleared")
        state.showToast("Tips shown again")

        #expect(recorder.messages == ["History cleared", "Tips shown again"])
        #expect(state.toast == "Tips shown again")
    }

    @Test func theSameMessageTwiceInARowIsAnnouncedTwice() {
        let recorder = Recorder()
        let state = makeState(recorder)

        state.showToast("History cleared")
        state.showToast("History cleared")

        #expect(recorder.messages == ["History cleared", "History cleared"])
    }

    @Test func anEmptyMessageIsNotAnnounced() {
        let recorder = Recorder()
        let state = makeState(recorder)

        state.showToast("")
        #expect(recorder.messages.isEmpty)
        #expect(state.toast == "")

        state.showToast("   ")
        #expect(recorder.messages.isEmpty)
    }

    @Test func quitRequestInDemoModeAnnouncesTheToastText() {
        let recorder = Recorder()
        let state = makeState(recorder)

        state.quitApp(path: "/Applications/Safari.app", name: "Safari")

        #expect(recorder.messages == ["Quit request sent to Safari"])
        #expect(state.toast == "Quit request sent to Safari")
    }

    @Test func theAnnouncedTextIsExactlyTheToastText() {
        let recorder = Recorder()
        let state = makeState(recorder)
        let message = "5 GB freed · “iPhone 15” is running: quit it first."

        state.showToast(message)

        #expect(recorder.messages == [state.toast])
    }
}
