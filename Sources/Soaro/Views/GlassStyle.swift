import AppKit
import SwiftUI

// MARK: - Environnement

private struct GlassSurfaceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// `true` : les cartes sont en verre. Faux par défaut (panneau de la barre de menus, style à plat). La fenêtre indépendante
    /// le pose depuis `WindowSurface.cardsAreGlass` : depuis l'expérience 1.2.0 (zone principale opaque) il y est faux aussi.
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

// MARK: - Surfaces de la fenêtre (expérience 1.2.0)

/// EXPÉRIENCE 1.2.0, à confirmer par l'auteur : dans la fenêtre indépendante uniquement, le contenu de la zone principale (colonne de
/// détail, sous la barre de titre et la barre d'outils) est opaque ; la barre latérale et la bande de la barre de titre restent
/// translucides (le flou de `WindowGlassBackground`, posé derrière toute la fenêtre, ne se voit qu'à travers elles), et les cartes passent du verre à l'aplat doux du panneau
/// (le verre n'aurait rien à réfracter sur un fond opaque).
///
/// POUR REVENIR À L'ÉTAT 1.1.0 : mettre `opaqueMainArea` à `false`. Rien d'autre à toucher.
enum WindowSurface {
    static let opaqueMainArea = true

    /// Les cartes de la fenêtre sont en verre quand la zone principale est translucide, à plat quand elle est opaque.
    static func cardsAreGlass(opaqueMainArea: Bool) -> Bool { !opaqueMainArea }
    static var cardsAreGlass: Bool { cardsAreGlass(opaqueMainArea: opaqueMainArea) }

    /// Fond de la zone principale : `textBackgroundColor` (blanc en clair, #1E1E1E en sombre, opaque, s'adapte au thème et à
    /// « Augmenter le contraste »). C'est exactement le fond de référence sur lequel DESIGN.md calcule ses rapports de contraste ;
    /// `windowBackgroundColor` (gris #ECECEC / #323232) en donnerait de plus faibles (texte de soutien ≈ 4,7 : 1 en clair).
    static let mainAreaNSColor = NSColor.textBackgroundColor
    static var mainAreaColor: Color { Color(nsColor: mainAreaNSColor) }
}

extension View {
    /// Fond opaque de la colonne de détail, limité au contenu : il s'arrête sous la barre de titre et la barre d'outils, où l'on voit
    /// le fond translucide de la fenêtre (comme la barre latérale), flouté par `TitleBarBlur` pour garder le titre lisible quand le
    /// contenu défile dessous. Sans effet si l'expérience est coupée.
    @ViewBuilder func windowMainAreaBackground() -> some View {
        if WindowSurface.opaqueMainArea {
            background(WindowSurface.mainAreaColor)
        } else {
            self
        }
    }

    /// Le message passager recouvre le contenu qui défile : à plat et translucide il serait illisible, on lui donne un fond plein.
    @ViewBuilder func windowToastBase() -> some View {
        if WindowSurface.opaqueMainArea {
            background(WindowSurface.mainAreaColor, in: RoundedRectangle(cornerRadius: 10))
        } else {
            self
        }
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
