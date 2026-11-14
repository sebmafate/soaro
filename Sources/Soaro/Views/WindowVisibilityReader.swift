import AppKit
import SwiftUI

/// Signale quand la fenêtre qui contient la vue devient visible / cachée.
/// `onAppear` / `onDisappear` ne sont pas fiables pour le panneau d'un `MenuBarExtra`.
struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void
    /// Reçoit la fenêtre qui contient la vue (utile pour pouvoir la refermer plus tard).
    var onWindow: ((NSWindow?) -> Void)? = nil

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onChange = onChange
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: TrackerView, context: Context) {
        view.onChange = onChange
        view.onWindow = onWindow
    }

    final class TrackerView: NSView {
        var onChange: ((Bool) -> Void)?
        var onWindow: ((NSWindow?) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var lastReported: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            lastReported = nil

            onWindow?(window)
            guard let window else { report(false); return }
            let names: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.didMiniaturizeNotification,
            ]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self] _ in self?.report() })
            }
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in self?.report(false) })
            report()
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        private func report(_ forced: Bool? = nil) {
            let visible = forced ?? (window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false)
            guard visible != lastReported else { return }
            lastReported = visible
            // Hors du cycle de mise à jour de SwiftUI.
            DispatchQueue.main.async { [weak self] in self?.onChange?(visible) }
        }
    }
}
