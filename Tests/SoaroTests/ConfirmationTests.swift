import AppKit
import Foundation
import Testing
@testable import Soaro

/// R8 : un bouton destructeur n'est jamais le bouton par défaut. Appuyer sur Retour annule.
/// On ne montre jamais l'alerte (`runModal` n'est jamais appelé) : on vérifie sa construction.
@MainActor
@Suite struct ConfirmationAlertTests {
    private func alert(critical: Bool) -> NSAlert {
        AppState.makeConfirmationAlert(title: "Delete Example?", message: "Details.", button: "Delete", critical: critical)
    }

    @Test(arguments: [false, true])
    func alertHasCancelFirstThenTheDestructiveButton(critical: Bool) {
        let alert = alert(critical: critical)
        #expect(alert.buttons.count == 2)
        #expect(alert.buttons[0].title == String(localized: "Cancel"))
        #expect(alert.buttons[1].title == "Delete")
    }

    @Test(arguments: [false, true])
    func cancelIsTheReturnButtonAndTheDestructiveButtonHasNoKey(critical: Bool) {
        let alert = alert(critical: critical)
        #expect(alert.buttons[0].keyEquivalent == "\r")
        #expect(alert.buttons[1].keyEquivalent == "")
        // Aucun bouton ne porte Échap explicitement : AppKit le lie au bouton « Cancel ».
        #expect(!alert.buttons.contains { $0.keyEquivalent == "\u{1b}" })
    }

    @Test(arguments: [false, true])
    func criticalOnlyChangesTheStyle(critical: Bool) {
        let alert = alert(critical: critical)
        #expect(alert.alertStyle == (critical ? .warning : .informational))
        #expect(alert.messageText == "Delete Example?")
        #expect(alert.informativeText == "Details.")
        #expect(alert.buttons.count == 2)
        #expect(alert.buttons[0].keyEquivalent == "\r")
    }

    @Test func onlyTheSecondButtonConfirms() {
        #expect(AppState.confirmationResult(for: .alertSecondButtonReturn))
    }

    @Test func everyOtherResponseCancels() {
        let others: [NSApplication.ModalResponse] = [
            .alertFirstButtonReturn, .alertThirdButtonReturn, .cancel, .stop, .abort, .OK, .continue,
            NSApplication.ModalResponse(rawValue: 12_345), NSApplication.ModalResponse(rawValue: -7),
        ]
        for response in others {
            #expect(!AppState.confirmationResult(for: response), "response \(response.rawValue) must not confirm")
        }
    }
}
