import Foundation
import ServiceManagement

/// État de l'interrupteur « Open at login » des réglages.
/// Mode démo : l'état est seulement en mémoire (il part éteint) ; le statut réel n'est pas lu
/// et l'élément de connexion réel n'est ni ajouté ni retiré. Hors démo, le comportement est celui d'avant.
/// Les actions réelles sont des paramètres **sans valeur par défaut** : elles ne sont construites que par `live`.
@MainActor
final class LaunchAtLoginModel: ObservableObject {
    @Published private(set) var isEnabled: Bool
    private let demo: Bool
    private let readStatus: () -> Bool
    private let apply: (Bool) throws -> Void

    init(demo: Bool, readStatus: @escaping () -> Bool, apply: @escaping (Bool) throws -> Void) {
        self.demo = demo
        self.readStatus = readStatus
        self.apply = apply
        isEnabled = demo ? false : readStatus()
    }

    /// Le seul endroit qui touche `SMAppService`.
    static func live(demo: Bool = DemoMode.isEnabled) -> LaunchAtLoginModel {
        LaunchAtLoginModel(
            demo: demo,
            readStatus: { SMAppService.mainApp.status == .enabled },
            apply: { enabled in
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            }
        )
    }

    /// Renvoie `false` quand le système refuse (l'appelant le dit à l'utilisateur) ; l'état affiché reste alors l'état réel.
    @discardableResult
    func set(_ enabled: Bool) -> Bool {
        if demo {
            // Démo : rien n'est lu ni écrit côté système ; l'interrupteur change seulement à l'écran.
            isEnabled = enabled
            return true
        }
        var succeeded = true
        do { try apply(enabled) } catch { succeeded = false }
        isEnabled = readStatus()
        return succeeded
    }
}
