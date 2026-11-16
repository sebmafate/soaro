import Foundation
import Testing
@testable import Soaro

/// `ActionBar` (SL3) : teinte du bouton, état « occupé », et jamais de raccourci Retour (R8).
@Suite struct ActionBarTests {
    @Test func destructiveBarUsesTheDangerFillNotSystemRed() {
        #expect(ActionBar.tintKind(destructive: true) == .danger)
    }

    @Test func nonDestructiveBarKeepsTheAccentTint() {
        #expect(ActionBar.tintKind(destructive: false) == .accent)
    }

    @Test func dangerTintResolvesToTheDangerFillValues() {
        #expect(ActionBarTint.danger.rgb(contrastIncreased: false) == DesignTokens.dangerFill)
        #expect(ActionBarTint.danger.rgb(contrastIncreased: true) == DesignTokens.dangerFillIncreasedContrast)
        // L'accent suit le système : pas de valeur fixe.
        #expect(ActionBarTint.accent.rgb(contrastIncreased: false) == nil)
        #expect(ActionBarTint.accent.rgb(contrastIncreased: true) == nil)
    }

    @Test(arguments: [(true, false, true), (true, true, false), (false, false, false), (false, true, false)])
    func buttonIsEnabledOnlyWhenAllowedAndNotBusy(enabled: Bool, busy: Bool, expected: Bool) {
        #expect(ActionBar.isButtonEnabled(enabled: enabled, busy: busy) == expected)
    }

    @Test func existingCallSitesStillCompileWithoutBusy() {
        let bar = ActionBar(summary: "s", button: "b", enabled: true, destructive: true, action: {})
        #expect(bar.busy == false)
    }

    /// Retour ne supprime jamais (R8) : aucun raccourci clavier ni action « par défaut » dans les vues.
    @Test func noViewBindsAKeyboardShortcut() throws {
        let views = RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Views")
        let enumerator = try #require(FileManager.default.enumerator(at: views, includingPropertiesForKeys: nil))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(files.count > 0, "aucun fichier trouvé : le test serait vide")
        #expect(files.contains { $0.lastPathComponent == "SelectionComponents.swift" })
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.isEmpty, "\(file.lastPathComponent) vide")
            for forbidden in ["keyboardShortcut", "defaultAction", "onKeyPress", "onSubmit"] {
                #expect(!text.contains(forbidden), "\(forbidden) ne doit pas apparaître dans \(file.lastPathComponent)")
            }
        }
    }
}
