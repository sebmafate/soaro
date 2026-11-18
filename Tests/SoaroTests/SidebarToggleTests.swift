import AppKit
import SwiftUI
import Testing
@testable import Soaro

/// SL20 : un bouton dans la barre d'outils replie et rouvre la barre latérale de la fenêtre indépendante.
///
/// Constat (voir PLAN.md, SL20) : la fenêtre n'avait AUCUN bouton de barre latérale (seul « Always on top » était dans la barre d'outils) ;
/// le bouton est donc explicite, il n'y en a pas deux. Ce qu'on ne peut pas tester : le vrai clic, l'animation, la disposition repliée,
/// VoiceOver lui-même (on vérifie l'étiquette et l'info-bulle que le système lui donne).
@MainActor @Suite(.serialized) struct SidebarToggleTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: Le calcul de la visibilité (fonction pure)

    @Test func theSidebarOpensAtEveryLaunch() {
        #expect(SidebarToggle.initialVisibility == .all)
        #expect(!SidebarToggle.isCollapsed(SidebarToggle.initialVisibility))
    }

    @Test func toggleCollapsesAnOpenSidebar() {
        #expect(SidebarToggle.toggled(.all) == .detailOnly)
        #expect(SidebarToggle.isCollapsed(.detailOnly))
    }

    @Test func toggleReopensACollapsedSidebar() {
        #expect(SidebarToggle.toggled(.detailOnly) == .all)
    }

    @Test func toggleTwiceComesBack() {
        #expect(SidebarToggle.toggled(SidebarToggle.toggled(.all)) == .all)
        #expect(SidebarToggle.toggled(SidebarToggle.toggled(.detailOnly)) == .detailOnly)
    }

    @Test func anyOtherVisibilityCountsAsOpenSoTheToggleCollapses() {
        // Le système peut remettre `.automatic` ou `.doubleColumn` : la barre est alors visible.
        for visible in [NavigationSplitViewVisibility.automatic, .doubleColumn] {
            #expect(!SidebarToggle.isCollapsed(visible))
            #expect(SidebarToggle.toggled(visible) == .detailOnly)
        }
    }

    // MARK: Mouvement réduit

    @Test func noAnimationWhenReduceMotionIsOn() {
        #expect(SidebarToggle.animation(reduceMotion: true) == nil)
    }

    @Test func theDefaultAnimationOtherwise() {
        #expect(SidebarToggle.animation(reduceMotion: false) != nil)
    }

    // MARK: Aucun raccourci clavier (R8)

    @Test func theToggleBindsNoKeyboardShortcut() throws {
        // Le garde-fou général est `ActionBarTests.noViewBindsAKeyboardShortcut` ; il n'est pas modifié. Ici, les deux fichiers du bouton.
        for path in ["Sources/Soaro/Views/SidebarToggle.swift", "Sources/Soaro/Views/MainWindow.swift"] {
            let text = try source(path)
            #expect(!text.isEmpty)
            for forbidden in ["keyboardShortcut", "defaultAction", "onKeyPress", "onSubmit"] {
                #expect(!text.contains(forbidden), "\(forbidden) ne doit pas apparaître dans \(path)")
            }
        }
    }

    // MARK: Le texte, en neuf langues

    @Test func theLabelIsInTheCatalogInNineLanguages() throws {
        let key = SidebarToggle.labelKey
        #expect(key == "Toggle Sidebar")
        let catalog = try TranslationCatalog.loadCatalog(TranslationCatalogTests.localizable)
        let strings = try #require(catalog["strings"] as? [String: Any])
        let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any]
        #expect(localizations != nil, "clé absente du catalogue")
        for language in TranslationCatalog.requiredTranslations {
            let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
            let value = unit?["value"] as? String ?? ""
            #expect(!value.isEmpty, "\(language)")
            #expect(unit?["state"] as? String == "translated", "\(language)")
        }
    }
}
