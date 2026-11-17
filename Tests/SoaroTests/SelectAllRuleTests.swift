import Foundation
import Testing
@testable import Soaro

/// « Select all » : la règle pure de la case à trois états d'un en-tête de section, son texte VoiceOver, et le code source de la vue.
@Suite struct SelectAllRuleTests {
    // MARK: L'état

    @Test(arguments: [
        (0, 0, SelectAllState.none),      // aucune ligne sélectionnable : jamais « tout »
        (0, 3, .none),                    // des cochées sans ligne sélectionnable : ignorées
        (4, 0, .none),
        (4, 1, .some),
        (4, 3, .some),
        (4, 4, .all),
        (1, 1, .all),
        (4, 9, .all),                     // plus de cochées que de lignes sélectionnables : borné
        (4, -1, .none),
    ])
    func theStateIsNoneSomeOrAllOfTheSelectableRows(selectable: Int, selected: Int, expected: SelectAllState) {
        #expect(SelectAll.state(selectable: selectable, selected: selected) == expected)
    }

    @Test(arguments: [(SelectAllState.none, true), (.some, true), (.all, false)])
    func aClickChecksAllUnlessEverythingIsAlreadyChecked(state: SelectAllState, turnsOn: Bool) {
        #expect(SelectAll.turnsOn(from: state) == turnsOn)
    }

    @Test(arguments: [(0, false, false), (3, false, true), (3, true, false), (0, true, false)])
    func theCheckboxIsDisabledWithoutASelectableRowOrWhileLocked(selectable: Int, locked: Bool, enabled: Bool) {
        #expect(SelectAll.isEnabled(selectable: selectable, locked: locked) == enabled)
    }

    // MARK: Glyphe et VoiceOver

    @Test func eachStateHasItsOwnGlyphSoColourIsNeverTheOnlySignal() {
        let glyphs = [SelectAllState.none, .some, .all].map(SelectAll.symbol(for:))
        #expect(Set(glyphs).count == 3)
        #expect(SelectAll.symbol(for: .all) == "checkmark.circle.fill")
        #expect(SelectAll.symbol(for: .none) == "circle")
        #expect(SelectAll.symbol(for: .some) == "minus.circle.fill")
    }

    @Test func voiceOverReadsSelectAllWithTheSectionAndASelectedNotSelectedOrSomeSelectedValue() {
        let none = SelectAll.description(state: .none, sectionName: "iOS Simulators")
        #expect(none == SelectionAccessibility.Description(label: "Select all, iOS Simulators", value: "Not selected"))
        #expect(SelectAll.description(state: .some, sectionName: "iOS Simulators").value == "Some selected")
        #expect(SelectAll.description(state: .all, sectionName: "iOS Simulators").value == "Selected")
        // Sans nom de section (liste sans en-tête) : « Select all » seul.
        #expect(SelectAll.description(state: .all, sectionName: nil).label == "Select all")
        #expect(SelectAll.description(state: .all, sectionName: "  ").label == "Select all")
    }

    // MARK: Le code source de la vue

    private func source(_ path: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
    }

    @Test func theCheckboxUsesTheSharedTargetSizeAndANamedAccessibilityElementWithoutAnyShortcut() throws {
        let text = try source("Sources/Soaro/Views/SelectionComponents.swift")
        let start = try #require(text.range(of: "struct SelectAllCheckbox"))
        let body = String(text[start.lowerBound...])
        #expect(body.contains("SelectionMetrics.minimumTargetSize"), "au moins 24 x 24 pt, la même constante que les lignes")
        #expect(body.contains("accessibilityLabel") && body.contains("accessibilityValue"))
        #expect(body.contains("SelectAll.symbol(for:"))
        #expect(!body.contains("keyboardShortcut"))
    }

    @Test func theSelectAllStringsAreInTheCatalogInNineLanguages() throws {
        let catalog = try source("Sources/Soaro/Resources/Localizable.xcstrings")
        let data = try #require(catalog.data(using: .utf8))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: Any])
        for key in ["Select all", "Some selected"] {
            let entry = try #require(strings[key] as? [String: Any], "\(key) manque dans le catalogue")
            let localizations = try #require(entry["localizations"] as? [String: Any])
            #expect(Set(localizations.keys) == Set(TranslationCatalog.requiredTranslations), "\(key) : les huit langues")
        }
    }
}
