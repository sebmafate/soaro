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

    /// Seule une raison `nil` donne un bouton de bascule ; une ligne indisponible n'en expose aucun
    /// (la vue choisit entre bouton et icône inerte avec cette même fonction).
    @Test(arguments: ["In use", "", " "])
    func unavailableRowExposesNoToggleButton(reason: String) {
        #expect(!SelectionAccessibility.isSelectable(unavailableReason: reason))
    }

    @Test func rowWithoutReasonExposesTheToggleButton() {
        #expect(SelectionAccessibility.isSelectable(unavailableReason: nil))
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

    // MARK: Un seul élément par ligne : nom + détails (SL8 T9)

    @Test func detailsFollowTheNameInOrderJoinedByCommas() {
        let d = SelectionAccessibility.description(name: "Phone", details: ["iOS 26.2", "1,2 GB", "inactive for 66 d"], isOn: true)
        #expect(d.label == "Phone, iOS 26.2, 1,2 GB, inactive for 66 d")
        #expect(d.value == selected)
    }

    @Test func emptyAndBlankDetailsAreSkipped() {
        let d = SelectionAccessibility.description(name: "Phone", details: ["", "iOS 26.2", "  ", "\n", "old"], isOn: false)
        #expect(d.label == "Phone, iOS 26.2, old")
        #expect(d.value == notSelected)
    }

    @Test func noDetailsGivesTheSameDescriptionAsBefore() {
        #expect(SelectionAccessibility.description(name: "a", details: [], isOn: true)
                == SelectionAccessibility.description(name: "a", isOn: true))
        #expect(SelectionAccessibility.description(name: "a", details: ["", " "], isOn: false)
                == SelectionAccessibility.description(name: "a", isOn: false))
    }

    @Test func blankNameWithDetailsReadsTheDetailsAndTheState() {
        let d = SelectionAccessibility.description(name: " ", details: ["1,2 GB"], isOn: true)
        #expect(d.label == "1,2 GB")
        #expect(d.value == selected)
    }

    @Test func blankNameWithoutDetailsStillFallsBackToTheStateAlone() {
        let d = SelectionAccessibility.description(name: "", details: ["", " "], isOn: true)
        #expect(d.label == selected)
        #expect(d.value.isEmpty)
    }

    @Test func unavailableRowKeepsDetailsInTheLabelAndTheReasonInTheValue() {
        let d = SelectionAccessibility.description(name: "Phone", details: ["iOS 26.2", "1,2 GB"], isOn: false, unavailableReason: "Busy")
        #expect(d.label == "Phone, iOS 26.2, 1,2 GB")
        #expect(d.value == String(localized: "\("Busy"), not selectable"))
    }

    @Test func detailsAreKeptVerbatim() {
        let d = SelectionAccessibility.description(name: "n", details: ["100 % %@ “x”"], isOn: true)
        #expect(d.label == "n, 100 % %@ “x”")
    }

    // MARK: Action « Show in Finder » (SL8 T9)

    @Test func showInFinderKeyIsTheExistingCatalogKey() throws {
        let catalog = try TranslationCatalog.loadCatalog(TranslationCatalogTests.localizable)
        let strings = try #require(catalog["strings"] as? [String: Any])
        #expect(strings["Show in Finder"] != nil, "l'action VoiceOver réutilise la clé existante")
    }
}
