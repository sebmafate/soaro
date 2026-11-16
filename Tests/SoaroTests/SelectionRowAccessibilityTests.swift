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
}
