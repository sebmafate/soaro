import Foundation
import Testing
@testable import Soaro

/// « Select all » dans les vues : chaque liste de sélection a sa case dans l'en-tête de sa section (contrôles de source : aucun écran
/// n'est lancé par les tests), et un en-tête sans sélection ne change pas.
@Suite struct SelectAllViewsTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
    }

    @Test func theSimulatorsViewHasOneCheckboxPerListedSectionAndBindsItToItsGroup() throws {
        let text = try source("Sources/Soaro/Views/SimulatorsView.swift")
        #expect(text.components(separatedBy: "selectAll: selectAll(").count - 1 == 2, "iOS et Android")
        #expect(text.contains("selectAll(.ios"))
        #expect(text.contains("selectAll(.android"))
        #expect(text.contains("model.toggleAll(group)"))
        #expect(text.contains("model.canSelectAll(group)"))
    }

    @Test func eachToolViewHasItsCheckboxInTheHeaderOfItsList() throws {
        let text = try source("Sources/Soaro/Views/CleanupToolViews.swift")
        #expect(text.components(separatedBy: "SelectAllControl(").count - 1 == 3, "gros fichiers, projets inactifs, fichiers liés")
        #expect(text.components(separatedBy: "model.toggleAll()").count - 1 == 3)
        #expect(text.components(separatedBy: "model.canSelectAll").count - 1 == 3)
    }

    @Test func startupItemsHaveNoSelectionAndNoCheckbox() throws {
        let text = try source("Sources/Soaro/Views/CleanupToolViews.swift")
        let start = try #require(text.range(of: "struct StartupItemsView"))
        #expect(!text[start.lowerBound...].contains("SelectAll"))
    }

    @Test func aSectionHeaderWithoutSelectionKeepsItsLayoutAndUsesTheSupportingToken() throws {
        let text = try source("Sources/Soaro/Views/Components.swift")
        let start = try #require(text.range(of: "struct SectionHeader"))
        let body = String(text[start.lowerBound...].prefix(900))
        #expect(body.contains("var selectAll: SelectAllControl? = nil"), "le paramètre est optionnel : les appels existants ne changent pas")
        #expect(body.contains("titleText.padding(.top, 4)"), "sans case : le même titre, le même remplissage")
        for modifier in [".textCase(.uppercase)", ".font(.caption.weight(.semibold))", "supportingText"] {
            #expect(body.contains(modifier))
        }
        // Le titre est d'un cran plus grand (`.caption`) et passe par le jeton : plus de `.caption2` ni de `.secondary`.
        let titleText = try #require(body.range(of: "private var titleText"))
        let titleBody = String(body[titleText.lowerBound...])
        #expect(!titleBody.contains(".caption2"))
        #expect(!titleBody.contains(".secondary"))
    }
}
