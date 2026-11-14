import Combine
import Foundation
import Sparkle

/// Mises à jour automatiques via Sparkle (principe et mise en place : docs/updates.md).
///
/// Sparkle ne démarre que si l'app porte une adresse de flux (`SUFeedURL`) et une clé publique (`SUPublicEDKey`) :
/// c'est le cas d'une app construite par `scripts/build-app.sh`, pas d'un `swift run` ni des tests.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    /// `false` quand Sparkle est inactif (build de développement) : l'interface masque alors la section.
    let isAvailable: Bool
    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecks = false {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    private let controller: SPUStandardUpdaterController?
    private var observation: AnyCancellable?

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        isAvailable = info["SUFeedURL"] is String && info["SUPublicEDKey"] is String
        guard isAvailable, Snapshot.outputDirectory == nil, !Diagnostics.isRequested else {
            controller = nil
            return
        }
        // `startingUpdater: true` lance la vérification planifiée (au plus une fois par jour par défaut).
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
    }

    /// Lance une vérification à la demande (affiche toujours un résultat, même « à jour »).
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Démarre Sparkle au lancement : sans cet appel, rien n'est instancié avant d'ouvrir les réglages.
    func start() {}
}
