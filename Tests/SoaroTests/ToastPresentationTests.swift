import Foundation
import Testing
@testable import Soaro

/// Règles pures du toast (SL5) : style de mouvement selon Réduire les animations, texte annoncé à VoiceOver, durée.
@Suite struct ToastPresentationTests {
    @Test func motionStyleFollowsReduceMotion() {
        #expect(ToastPresentation.motionStyle(reduceMotion: false) == .slideAndFade)
        #expect(ToastPresentation.motionStyle(reduceMotion: true) == .fade)
    }

    @Test func announcementIsTheMessageVerbatim() {
        #expect(ToastPresentation.announcement(for: "History cleared") == "History cleared")
        let message = "5 GB freed · “iPhone 15” is running: quit it first."
        #expect(ToastPresentation.announcement(for: message) == message)
    }

    @Test func emptyOrBlankMessageIsNotAnnounced() {
        #expect(ToastPresentation.announcement(for: "") == nil)
        #expect(ToastPresentation.announcement(for: "   ") == nil)
        #expect(ToastPresentation.announcement(for: " \n\t ") == nil)
    }

    @Test func visibleDurationIsFourSeconds() {
        #expect(ToastPresentation.visibleDuration == .seconds(4))
    }

    // MARK: Câblage dans les vues (gardes au niveau du source ; l'animation elle-même se vérifie à la main)

    private func viewSource(_ name: String) throws -> String {
        let url = RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Views/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func panelAndWindowReadReduceMotionAndNoLongerHardCodeTheSlide() throws {
        for file in ["PopoverView.swift", "MainWindow.swift"] {
            let text = try viewSource(file)
            #expect(text.contains("accessibilityReduceMotion"), "\(file) doit lire Réduire les animations")
            #expect(!text.contains(".move(edge:"), "\(file) ne doit plus fixer le glissement lui-même")
            #expect(normalized(text).contains(".animation(.easeInOut(duration: 0.2), value: state.toast)"),
                    "\(file) doit garder `.animation(.easeInOut(duration: 0.2), value: state.toast)` (0,2 s, sur le toast)")
        }
    }

    /// Source avec les blancs réduits à une espace : les gardes ne dépendent pas de la mise en forme.
    private func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func appStateSource() throws -> String {
        let url = RepositoryRoot.url().appendingPathComponent("Sources/Soaro/AppState.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func eachMotionStyleMapsToItsTransition() throws {
        let text = normalized(try viewSource("ToastTransition.swift"))
        #expect(text.contains("case .fade: .opacity"), "`.fade` doit donner `.opacity` (sans déplacement)")
        #expect(text.contains("case .slideAndFade: .move(edge: .bottom).combined(with: .opacity)"),
                "`.slideAndFade` doit donner le glissement vers le bas avec fondu")
    }

    @Test func panelAndWindowPassTheEnvironmentValueNotALiteral() throws {
        for file in ["PopoverView.swift", "MainWindow.swift"] {
            let text = normalized(try viewSource(file))
            #expect(text.contains(".toastTransition(reduceMotion: reduceMotion)"),
                    "\(file) doit passer la valeur de l'environnement à `toastTransition`")
            #expect(!text.contains("toastTransition(reduceMotion: true") && !text.contains("toastTransition(reduceMotion: false"),
                    "\(file) ne doit pas passer un littéral à `toastTransition`")
        }
    }

    @Test func showToastUsesTheSharedDurationAndCancelsThePreviousTimer() throws {
        let text = normalized(try appStateSource())
        let start = try #require(text.range(of: "func showToast(_ message: String) {"), "showToast introuvable")
        let end = try #require(text.range(of: "// MARK: Notifications", range: start.upperBound..<text.endIndex),
                               "fin de showToast introuvable")
        let body = String(text[start.upperBound..<end.lowerBound])
        #expect(body.contains("Task.sleep(for: ToastPresentation.visibleDuration)"),
                "le minuteur du toast doit dormir `ToastPresentation.visibleDuration`")
        #expect(!body.contains(".seconds(") && !body.contains(".milliseconds("), "aucune durée littérale dans le minuteur du toast")
        let cancel = try #require(body.range(of: "toastTask?.cancel()"), "le toast précédent doit être annulé")
        let create = try #require(body.range(of: "toastTask = Task"), "le minuteur n'est plus créé dans `toastTask`")
        #expect(cancel.lowerBound < create.lowerBound, "annuler le minuteur précédent avant d'en créer un nouveau")
    }

    @Test func theDefaultAnnouncerIsTheRealOne() throws {
        let text = normalized(try appStateSource())
        #expect(text.contains("announce: @escaping @MainActor (String) -> Void = ToastAnnouncer.announce)"),
                "la valeur par défaut de `announce` doit être `ToastAnnouncer.announce` (pas une fermeture vide)")
    }

    @Test func theSlideIsDefinedInOnePlaceOnly() throws {
        let text = try viewSource("ToastTransition.swift")
        #expect(text.components(separatedBy: ".move(edge: .bottom)").count - 1 == 1)
    }
}
