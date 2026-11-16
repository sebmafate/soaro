import Foundation
import Testing
@testable import Soaro

/// R9 : les fonctions qui sortent du Mac (IP publique) ou qui lancent un ping
/// (latence) sont désactivées par défaut.
///
/// Limites :
/// - Seuls les défauts enregistrés (`SettingsKey.defaults`, passés à
///   `register(defaults:)` au lancement) sont couverts. Les valeurs par défaut
///   `@AppStorage(...) = false` écrites dans les vues (NetworkTab, SettingsView)
///   ne sont pas lisibles depuis un test.
/// - Ce test n'appelle PAS `register(defaults:)`, même sur une suite jetable :
///   le domaine d'enregistrement est partagé par tout le processus, et y
///   inscrire `SettingsKey.defaults` fausse les autres tests (LegacyMigrationTests
///   échoue alors : `menuBarCPU` vaut `true` dans une suite vierge). On lit donc
///   le dictionnaire tel que `SoaroApp` le passe à `register(defaults:)`.
@Suite struct OptInDefaultsTests {
    @Test func optInKeysAreRegisteredAsFalse() {
        for key in [SettingsKey.publicIP, SettingsKey.latency] {
            let value = SettingsKey.defaults[key] as? Bool
            #expect(value == false, "\(key) doit être enregistré à false (R9 : opt-in)")
        }
    }

    @Test func contrastKeyIsRegisteredAsTrue() {
        // Contraste : une clé qui n'est pas « opt-in » est bien active par défaut,
        // donc le test ci-dessus ne passe pas parce que tout vaudrait false.
        #expect(SettingsKey.defaults[SettingsKey.notifications] as? Bool == true)
    }
}
