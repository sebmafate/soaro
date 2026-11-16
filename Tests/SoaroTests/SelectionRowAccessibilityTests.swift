import Foundation
import Testing
@testable import Soaro

/// `SelectionRow` (SL3) : le bouton de sélection porte le nom de l'élément pour VoiceOver.
/// On compare avec les mêmes morceaux localisés que le code (jamais de texte anglais en dur) ;
/// la lecture réelle par VoiceOver et la taille de la cible se vérifient à la main.
@Suite struct SelectionRowAccessibilityTests {
    private let selected = String(localized: "Selected")
    private let notSelected = String(localized: "Not selected")

    @Test func selectedRowNamesTheItemAndSaysSelected() {
        let d = SelectionAccessibility.description(name: "web-shop", isOn: true)
        #expect(d.label == "web-shop")
        #expect(d.value == selected)
    }

    @Test func unselectedRowNamesTheItemAndSaysNotSelected() {
        let d = SelectionAccessibility.description(name: "web-shop", isOn: false)
        #expect(d.label == "web-shop")
        #expect(d.value == notSelected)
    }

    @Test func stateWordsComeFromTheCatalogKeysAndDiffer() {
        let on = SelectionAccessibility.description(name: "x", isOn: true)
        let off = SelectionAccessibility.description(name: "x", isOn: false)
        #expect(on.value != off.value)
        #expect(!on.value.isEmpty && !off.value.isEmpty)
    }

    @Test(arguments: ["", "   ", "\n"])
    func blankNameFallsBackToTheStateAlone(name: String) {
        // Pas de libellé vide (VoiceOver lirait le symbole) ni de doublon « Selected, Selected ».
        let on = SelectionAccessibility.description(name: name, isOn: true)
        #expect(on.label == selected)
        #expect(on.value.isEmpty)
        let off = SelectionAccessibility.description(name: name, isOn: false)
        #expect(off.label == notSelected)
        #expect(off.value.isEmpty)
    }

    @Test(arguments: [
        "Application Support/com.example.App",
        "~/Library/Caches/“quoted” & <tagged>",
        "100 % sûr %@ %lld",
        "日本語のフォルダ",
        "emoji 🚀 folder",
        "tab\tand\nnewline",
    ])
    func specialCharactersAreKeptVerbatim(name: String) {
        let d = SelectionAccessibility.description(name: name, isOn: true)
        #expect(d.label == name)
        #expect(d.value == selected)
    }

    @Test func checkTargetIsAtLeast24Points() {
        // Contrôle faible : la valeur de la constante. La vraie vérification est manuelle (Accessibility Inspector).
        #expect(SelectionMetrics.minimumTargetSize >= 24)
    }

    // MARK: Variante « indisponible » (T5)

    @Test(arguments: [true, false])
    func unavailableRowNamesTheItemAndReadsTheReasonNotTheState(isOn: Bool) {
        let d = SelectionAccessibility.description(name: "iPhone 15", isOn: isOn, unavailableReason: "In use")
        #expect(d.label == "iPhone 15")
        #expect(d.value == String(localized: "\("In use"), not selectable"))
        #expect(d.value.contains("In use"))
        #expect(d.value != selected && d.value != notSelected)
    }

    @Test func unavailableValueKeepsTheReasonVerbatimWhateverItContains() {
        let reason = "100 % sûr %@ “x” & <y>"
        let d = SelectionAccessibility.description(name: "n", isOn: false, unavailableReason: reason)
        #expect(d.label == "n")
        #expect(d.value.contains(reason))
    }

    @Test func unavailableRowWithBlankNameStillSaysWhyAndKeepsAnAnnouncement() {
        let d = SelectionAccessibility.description(name: "", isOn: false, unavailableReason: "In use")
        #expect(!d.label.isEmpty)
        #expect(d.value.contains("In use") || d.label.contains("In use"))
    }

    @Test func availableRowIgnoresNilReason() {
        #expect(SelectionAccessibility.description(name: "a", isOn: true, unavailableReason: nil)
                == SelectionAccessibility.description(name: "a", isOn: true))
    }

    @Test func togglingAnUnavailableRowDoesNothing() {
        var calls = 0
        SelectionAccessibility.activate(unavailableReason: "In use") { calls += 1 }
        SelectionAccessibility.activate(unavailableReason: "") { calls += 1 }
        #expect(calls == 0)
    }

    @Test func togglingAnAvailableRowCallsToggleOnce() {
        var calls = 0
        SelectionAccessibility.activate(unavailableReason: nil) { calls += 1 }
        #expect(calls == 1)
    }

    /// La clé du catalogue existe, dans les 9 langues, avec `%@` conservé (R12).
    @Test func notSelectableKeyIsInTheCatalogInEveryLanguageKeepingThePlaceholder() throws {
        let catalog = try TranslationCatalog.loadCatalog(TranslationCatalogTests.localizable)
        let strings = try #require(catalog["strings"] as? [String: Any])
        let entry = try #require(strings["%@, not selectable"] as? [String: Any], "clé absente du catalogue")
        let localizations = try #require(entry["localizations"] as? [String: Any])
        for language in TranslationCatalog.requiredTranslations {
            let unit = try #require((localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any], "\(language) absent")
            let value = try #require(unit["value"] as? String)
            #expect(value.contains("%@"), "\(language) : %@ perdu")
            // Mise en forme avec une locale explicite : la raison apparaît, sans marqueur résiduel.
            let formatted = String(format: value, locale: Locale(identifier: language), "In use")
            #expect(formatted.contains("In use") && !formatted.contains("%@"), "\(language)")
        }
    }
}
