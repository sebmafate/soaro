import AppKit
import SwiftUI

// MARK: - Environnement

private struct GlassSurfaceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// `true` dans la fenêtre indépendante : les cartes y sont en verre. Le panneau de la barre de menus garde son style sobre.
    var glassSurface: Bool {
        get { self[GlassSurfaceKey.self] }
        set { self[GlassSurfaceKey.self] = newValue }
    }
}

// MARK: - Fond des cartes

/// Fond commun à toutes les cartes : verre dans la fenêtre, aplat discret dans le panneau.
struct CardBackground: ViewModifier {
    @Environment(\.glassSurface) private var glass
    var tint: Color? = nil
    var flatOpacity: Double = 0.5

    func body(content: Content) -> some View {
        if glass {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            // Liquid Glass n'existe que dans le SDK de macOS 26 (Swift 6.2 et plus) : sans ce garde,
            // un Xcode plus ancien (par exemple sur un runner CI) ne compile pas le projet.
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                // Liquid Glass : le verre réfracte ce qu'il y a derrière ; une teinte légère garde le sens des couleurs d'alerte.
                content.glassEffect(tint.map { Glass.regular.tint($0.opacity(0.22)) } ?? .regular, in: shape)
            } else {
                materialCard(content, shape: shape)
            }
            #else
            materialCard(content, shape: shape)
            #endif
        } else {
            let shape = RoundedRectangle(cornerRadius: 10)
            if let tint {
                content.background(tint.opacity(0.10), in: shape)
            } else {
                content.background(.quaternary.opacity(flatOpacity), in: shape)
            }
        }
    }

    /// Repli pour macOS 14 et 15 : matériau translucide, fine bordure claire.
    private func materialCard(_ content: Content, shape: RoundedRectangle) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .background((tint ?? .clear).opacity(0.12), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
    }
}

extension View {
    func cardBackground(tint: Color? = nil, flatOpacity: Double = 0.5) -> some View {
        modifier(CardBackground(tint: tint, flatOpacity: flatOpacity))
    }
}

// MARK: - Fond de fenêtre translucide

/// Flou de ce qui se trouve derrière la fenêtre (bureau, autres fenêtres).
struct WindowGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active          // reste translucide même quand la fenêtre n'est pas au premier plan (épinglée)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
