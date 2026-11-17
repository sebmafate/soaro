import Foundation
import Testing
@testable import Soaro

/// `AppState.cleanup` et `AppState.quitApp` en mode démo : aucun nettoyage réel, aucune vraie app quittée.
/// Les actions réelles sont remplacées par des fermetures qui comptent leurs appels.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var kinds: [CleanupKind] = []
    var cleaned: [CleanupKind] { lock.withLock { kinds } }
    var clean: @Sendable (CleanupKind) -> CleanupResult {
        { [self] kind in lock.withLock { kinds.append(kind) }; return CleanupResult(freed: 1, failures: 0, error: nil) }
    }
}

@MainActor
@Suite struct AppStateDemoTests {
    private func waitForToast(_ state: AppState) async -> String? {
        for _ in 0..<200 {
            if let toast = state.toast { return toast }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    @Test func demoCleanupConfirmedNeverCleansAndShowsAToast() async {
        let counter = Counter()
        var asked = 0
        let state = AppState(history: nil, demo: true, confirm: { _, _, _, _ in asked += 1; return true },
                             clean: counter.clean, terminateApp: { _ in false })

        state.cleanup([.nugetCache])

        #expect(asked == 1)
        #expect(await waitForToast(state) == "\(Format.fileBytes(0)) freed")
        #expect(counter.cleaned.isEmpty)
        #expect(state.busyKinds.isEmpty)
    }

    @Test func cancelledCleanupCleansNothingAndShowsNothing() async {
        let counter = Counter()
        let state = AppState(history: nil, demo: false, confirm: { _, _, _, _ in false },
                             clean: counter.clean, terminateApp: { _ in false })

        state.cleanup([.nugetCache])
        try? await Task.sleep(for: .milliseconds(100))

        #expect(counter.cleaned.isEmpty)
        #expect(state.toast == nil)
        #expect(state.busyKinds.isEmpty)
    }

    @Test func demoQuitNeverTerminatesARealAppButAnswersLikeTheRealOne() {
        var terminated: [String] = []
        let state = AppState(history: nil, demo: true, confirm: { _, _, _, _ in false },
                             clean: Counter().clean, terminateApp: { terminated.append($0); return true })

        state.quitApp(path: "/Applications/Safari.app", name: "Safari")

        #expect(terminated.isEmpty)
        #expect(state.toast == "Quit request sent to Safari")
    }

    @Test func outsideDemoQuitAsksTheSystemForThatPath() {
        var terminated: [String] = []
        let state = AppState(history: nil, demo: false, confirm: { _, _, _, _ in false },
                             clean: Counter().clean, terminateApp: { terminated.append($0); return false })

        state.quitApp(path: "/Applications/Example.app", name: "Example")

        #expect(terminated == ["/Applications/Example.app"])
        #expect(state.toast == "Could not quit Example")
    }
}
