import AppKit
import SwiftUI

// MARK: - Double-clic sur la barre de titre

/// Ce que fait un double-clic sur la barre de titre, selon la préférence du système
/// (Réglages Système > Bureau et Dock > « Double-cliquer sur la barre de titre d'une fenêtre pour »).
enum TitleBarDoubleClick {
    enum Action: Equatable { case zoom, miniaturize, nothing }

    /// `actionPreference` : `AppleActionOnDoubleClick` (« Maximize », « Minimize » ou « None »). `legacyMiniaturize` :
    /// l'ancien `AppleMiniaturizeOnDoubleClick`, lu seulement si la nouvelle clé n'existe pas. Absent partout : zoom (défaut du système).
    static func action(actionPreference: String?, legacyMiniaturize: Bool?) -> Action {
        switch actionPreference {
        case "Minimize": return .miniaturize
        case "None": return .nothing
        case "Maximize": return .zoom
        case .some: return .zoom
        case nil: return legacyMiniaturize == true ? .miniaturize : .zoom
        }
    }

    static var current: Action {
        let defaults = UserDefaults.standard
        return action(actionPreference: defaults.string(forKey: "AppleActionOnDoubleClick"),
                      legacyMiniaturize: defaults.object(forKey: "AppleMiniaturizeOnDoubleClick") as? Bool)
    }
}

// MARK: - Zone de glissement

/// Vue qui déplace la fenêtre quand on la saisit, comme une barre de titre. Pas de `isMovableByWindowBackground` pour toute
/// la fenêtre : les gestes de l'app (curseur de seuil, lignes de sélection, graphiques) se feraient voler par le glissement.
final class WindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 {
            switch TitleBarDoubleClick.current {
            case .zoom: window.performZoom(nil)
            case .miniaturize: window.performMiniaturize(nil)
            case .nothing: break
            }
        } else {
            window.performDrag(with: event)
        }
    }
}

private struct WindowDragRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragView { WindowDragView() }
    func updateNSView(_ view: WindowDragView, context: Context) {}
}

/// Bande transparente de la hauteur de la barre de titre et de la barre d'outils (lue dans la zone de sécurité du haut).
/// Elle reste sous les boutons de la fenêtre et sous les éléments de la barre d'outils, qui gardent leurs clics.
private struct WindowDragStrip: View {
    var body: some View {
        GeometryReader { geometry in
            WindowDragRepresentable()
                .frame(height: geometry.safeAreaInsets.top)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(.container, edges: .top)       // bord haut seulement, comme `TitleBarBlur`
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Fait de la bande du haut de la colonne une zone de glissement de la fenêtre (double-clic : zoom ou réduction selon le système).
    func windowDragStrip() -> some View {
        overlay(alignment: .top) { WindowDragStrip() }
    }
}
