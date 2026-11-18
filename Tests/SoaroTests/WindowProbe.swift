import AppKit
@testable import Soaro

/// Aides des tests de la vraie fenêtre (hors écran), partagées par `WindowDragRegionTests`, `SidebarToggleWindowTests`
/// et le diagnostic `ZZDiagnosticMacOS26HitChain`.
///
/// Pourquoi elles existent : la CI tourne sur macOS 26 (Xcode 26), les Mac de développement sur macOS 27, et AppKit n'y construit
/// pas les mêmes vues (la barre d'outils SwiftUI, le « scroll pocket » du Liquid Glass). Les tests décrivent donc la PROPRIÉTÉ
/// dont l'utilisateur a besoin (la fenêtre se déplace, le bouton a une info-bulle et un nom pour VoiceOver), pas la classe privée
/// qui la fournit sur une version donnée.
@MainActor enum WindowProbe {
    // MARK: Hiérarchie

    static func allViews(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(allViews) }

    /// La vue, puis ses parents, jusqu'à la vue racine de la fenêtre (le cadre, parent de `contentView`).
    static func chain(_ view: NSView) -> [NSView] {
        var result: [NSView] = []
        var current: NSView? = view
        while let item = current { result.append(item); current = item.superview }
        return result
    }

    static func className(_ view: NSView) -> String { String(describing: type(of: view)) }

    /// Nom complet de la classe de l'Objective-C runtime. Une classe Swift imbriquée (`NSScrollPocket.BackdropView`) s'affiche
    /// « BackdropView » avec `String(describing:)` mais son nom complet contient `NSScrollPocket` : c'est ce nom que montre le
    /// message d'échec de la CI (`_TtCC6AppKit14NSScrollPocketP33_...12BackdropView`).
    static func fullClassName(_ view: NSView) -> String { NSStringFromClass(type(of: view)) }

    /// Vue qui fait partie d'un « scroll pocket » (le nom de la vue ou le nom complet de sa classe le dit).
    static func isPocketRelated(_ view: NSView) -> Bool {
        className(view).contains("Pocket") || fullClassName(view).contains("Pocket")
    }

    /// Rectangle de la vue en coordonnées de la vue racine, et distance de son bord haut au haut de la fenêtre.
    static func rect(_ view: NSView, in root: NSView) -> NSRect { view.convert(view.bounds, to: root) }

    static func describe(_ view: NSView, in root: NSView) -> String {
        let r = rect(view, in: root)
        let top = root.bounds.height - r.maxY
        let full = fullClassName(view)
        let name = !full.contains("Pocket") || full == className(view) ? className(view) : "\(className(view)){\(full)}"
        return "\(name) mdcmw=\(view.mouseDownCanMoveWindow) opaque=\(view.isOpaque) alpha=\(view.alphaValue) hidden=\(view.isHidden)"
            + " frame(x=\(Int(r.minX)) fromTop=\(Int(top)) w=\(Int(r.width)) h=\(Int(r.height)))"
    }

    // MARK: Glissement de la fenêtre

    enum DragSource: Equatable {
        case ourDragView        // `WindowDragView`, la vue ou l'un de ses parents : `mouseDown` appelle `performDrag`
        case systemTitlebar     // une vue de la barre de titre ou de la barre d'outils du système : elle déplace la fenêtre
    }

    /// Qui déplacerait la fenêtre si on appuyait sur la souris sur `hit` ? Le `mouseDown` monte la chaîne des répondeurs
    /// (de la vue touchée vers ses parents) : le premier maillon qui est notre vue de glissement ou une vue de barre de titre
    /// du système gère le glissement. Rien d'autre ne le fait : la fenêtre n'est pas `isMovableByWindowBackground` (testé),
    /// donc `mouseDownCanMoveWindow == true` sur une vue quelconque (fond transparent par défaut) ne déplace rien.
    static func dragSource(of hit: NSView) -> DragSource? {
        for view in chain(hit) {
            if view is WindowDragView { return .ourDragView }
            if className(view).contains("Titlebar") { return .systemTitlebar }
        }
        return nil
    }

    /// Un point de sonde (x, distance au haut) doit-il déplacer la fenêtre ? `sidebar` : le rectangle de la vue de glissement de la
    /// barre latérale en coordonnées de la vue-cadre (origine en bas à gauche), `rootHeight` : la hauteur de cette vue-cadre.
    ///
    /// Disposition à ras (vue en x = 0 et à 0 pt du haut, macOS 27) : tout point l'exige. Disposition flottante (macOS 26, vue en x = 8 et
    /// à 8 pt du haut) : seulement les points dans notre vue (x de 6 pt après son bord gauche à 10 pt avant le droit, 2 pt de marge en haut
    /// et en bas) et dans la colonne de détail (au moins 8 pt à droite de la barre latérale). Le reste est une limite connue (bande du
    /// haut, marge gauche, coin de redimensionnement, jointure des colonnes), voir `WindowDragRegionTests.expectDragSources`.
    static func requiresDragSource(x: CGFloat, fromTop dy: CGFloat, sidebar: NSRect, rootHeight: CGFloat) -> Bool {
        let top = rootHeight - sidebar.maxY
        guard top > 0.5 || sidebar.minX > 0.5 else { return true }
        let inside = x >= sidebar.minX + 6 && x <= sidebar.maxX - 10 && dy >= top + 2 && dy <= top + sidebar.height - 2
        return inside || x >= sidebar.maxX + 8
    }

    /// Texte de diagnostic pour les messages d'échec : la vue touchée, sa chaîne de parents et les « poches » de défilement.
    static func hitReport(_ hit: NSView, in root: NSView) -> String {
        let parents = chain(hit).map { "\(className($0))[mdcmw=\($0.mouseDownCanMoveWindow)]" }.joined(separator: " < ")
        let pockets = allViews(root).filter { isPocketRelated($0) }.map { describe($0, in: root) }
        let drags = allViews(root).filter { $0 is WindowDragView }.map { describe($0, in: root) }
        return "touché : \(describe(hit, in: root)); chaîne : \(parents); poches : \(pockets); vues de glissement : \(drags)"
    }

    /// Au-dessus ou au-dessous ? Compare l'ordre d'empilement de deux vues au plus proche ancêtre commun.
    static func zOrder(_ a: NSView, versus b: NSView) -> String {
        let chainA = chain(a), chainB = chain(b)
        guard let common = chainA.first(where: { candidate in chainB.contains { $0 === candidate } }) else { return "aucun ancêtre commun" }
        if common === a { return "\(className(a)) est un ancêtre de \(className(b))" }
        if common === b { return "\(className(b)) est un ancêtre de \(className(a))" }
        func branchIndex(_ chain: [NSView]) -> Int? {
            guard let position = chain.firstIndex(where: { $0 === common }), position > 0 else { return nil }
            return common.subviews.firstIndex { $0 === chain[position - 1] }
        }
        guard let ia = branchIndex(chainA), let ib = branchIndex(chainB) else { return "ordre inconnu" }
        return ia > ib ? "\(className(a)) est AU-DESSUS de \(className(b)) (dans \(className(common)), rangs \(ia) > \(ib))"
                       : "\(className(a)) est AU-DESSOUS de \(className(b)) (dans \(className(common)), rangs \(ia) < \(ib))"
    }

    // MARK: Info-bulle et nom VoiceOver d'un élément de barre d'outils

    struct TextSource: CustomStringConvertible {
        let mechanism: String
        let text: String
        var description: String { "\(mechanism)=\"\(text)\"" }
    }

    /// Les vues par lesquelles SwiftUI peut exposer `.help` et `.accessibilityLabel` d'un élément de barre d'outils :
    /// la vue de l'élément, ses descendants et deux niveaux de parents (selon l'OS, le texte est porté par un conteneur).
    private static func viewsCarrying(_ item: NSToolbarItem) -> [(name: String, view: NSView)] {
        guard let root = item.view else { return [] }
        var result = allViews(root).map { (name: $0 === root ? "item.view" : "item.view descendant \(className($0))", view: $0) }
        var parent = root.superview
        for level in 1...2 {
            guard let current = parent else { break }
            result.append((name: "item.view ancestor \(level) \(className(current))", view: current))
            parent = current.superview
        }
        return result
    }

    /// Tous les endroits où l'info-bulle peut se trouver : `NSToolbarItem.toolTip`, `toolTip` des vues, aide d'accessibilité.
    static func tooltipSources(of item: NSToolbarItem) -> [TextSource] {
        var sources: [TextSource] = []
        if let text = item.toolTip, !text.isEmpty { sources.append(TextSource(mechanism: "NSToolbarItem.toolTip", text: text)) }
        for entry in viewsCarrying(item) {
            if let text = entry.view.toolTip, !text.isEmpty { sources.append(TextSource(mechanism: "\(entry.name) toolTip", text: text)) }
            if let text = entry.view.accessibilityHelp(), !text.isEmpty { sources.append(TextSource(mechanism: "\(entry.name) accessibilityHelp", text: text)) }
        }
        return sources
    }

    /// Tous les endroits où le nom lu par VoiceOver peut se trouver : `accessibilityLabel` des vues de l'élément, puis,
    /// pour un élément sans vue qui en porte un, `NSToolbarItem.label` (c'est ce que le système lit alors).
    static func accessibilityLabelSources(of item: NSToolbarItem) -> [TextSource] {
        var sources: [TextSource] = []
        for entry in viewsCarrying(item) {
            if let text = entry.view.accessibilityLabel(), !text.isEmpty { sources.append(TextSource(mechanism: "\(entry.name) accessibilityLabel", text: text)) }
            if let text = entry.view.accessibilityTitle(), !text.isEmpty { sources.append(TextSource(mechanism: "\(entry.name) accessibilityTitle", text: text)) }
        }
        if !item.label.isEmpty { sources.append(TextSource(mechanism: "NSToolbarItem.label", text: item.label)) }
        return sources
    }
}
