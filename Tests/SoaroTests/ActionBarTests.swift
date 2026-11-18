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
                // SL17 : une seule exception, la piste des seuils de couleur (Réglages), dont les poignées se règlent aux flèches,
                // à Début et à Fin. Elle ne supprime rien ; `theOnlyKeyPressExceptionHandlesNothingButArrowsHomeAndEnd` la borne.
                if forbidden == "onKeyPress", file.lastPathComponent == Self.keyPressException { continue }
                #expect(!text.contains(forbidden), "\(forbidden) ne doit pas apparaître dans \(file.lastPathComponent)")
            }
        }
    }

    static let keyPressException = "ThresholdTrack.swift"

    /// L'exception ne réagit qu'aux flèches, à Début et à Fin : jamais à Retour, Espace, Suppr., Échap ni Tab.
    @Test func theOnlyKeyPressExceptionHandlesNothingButArrowsHomeAndEnd() throws {
        let file = RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Views/\(Self.keyPressException)")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.components(separatedBy: "onKeyPress").count == 2, "un seul onKeyPress attendu")
        #expect(text.contains("onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end]"))
        for forbidden in [".return", ".space", ".delete", ".deleteForward", ".escape", ".tab", "keyboardShortcut", "defaultAction", "onSubmit"] {
            #expect(!text.contains(forbidden), "\(forbidden) ne doit pas apparaître dans \(Self.keyPressException)")
        }
    }
}
