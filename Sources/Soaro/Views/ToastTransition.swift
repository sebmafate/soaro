import SwiftUI

/// Transition du toast, choisie en un seul endroit pour le panneau et la fenêtre (SL5).
/// Le style vient de `ToastPresentation` ; l'animation (0,2 s) reste posée par chaque vue sur `state.toast`.
extension ToastPresentation.MotionStyle {
    var transition: AnyTransition {
        switch self {
        case .slideAndFade: .move(edge: .bottom).combined(with: .opacity)
        case .fade: .opacity
        }
    }
}

extension View {
    /// Applique la transition du toast : fondu seul avec Réduire les animations, glissement et fondu sinon.
    func toastTransition(reduceMotion: Bool) -> some View {
        transition(ToastPresentation.motionStyle(reduceMotion: reduceMotion).transition)
    }
}
