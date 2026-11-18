import Foundation
import Testing
@testable import Soaro

/// SL17 : les textes de la piste de seuils sont dans le catalogue (neuf langues, mêmes marqueurs).
/// Les nouvelles traductions sont écrites avec l'aide d'une IA : à relire par l'auteur.
@Suite struct ThresholdTrackStringsTests {
    /// Les clés NOUVELLES de SL17 (« Orange », « Red », « Scarlet », « %@ from %lld %% » et « %@ below %lld %% » existent déjà).
    static let newKeys = [
        "now",
        "from %lld %%",
        "below %lld %%",
        "%lld %%",
        "Now: %lld %%",
    ]

    @Test func everyNewKeyIsInTheCatalogInEveryLanguageWithMatchingMarkers() throws {
        let catalog = try TranslationCatalog.loadCatalog(TranslationCatalogTests.localizable)
        let strings = try #require(catalog["strings"] as? [String: Any])
        #expect(Set(Self.newKeys).count == Self.newKeys.count)
        for key in Self.newKeys + ["Orange", "Red", "Scarlet", "%@ from %lld %%", "%@ below %lld %%"] {
            let entry = strings[key] as? [String: Any]
            #expect(entry != nil, "clé absente du catalogue : \(key.debugDescription)")
            let localizations = entry?["localizations"] as? [String: Any] ?? [:]
            for language in TranslationCatalog.requiredTranslations {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String ?? ""
                #expect(!value.isEmpty, "\(key.debugDescription) / \(language)")
                #expect(TranslationCatalog.placeholderProblems(source: key, translation: value).isEmpty,
                        "\(key.debugDescription) / \(language) : \(TranslationCatalog.placeholderProblems(source: key, translation: value))")
                #expect(unit?["state"] as? String == "translated", "\(key.debugDescription) / \(language)")
                #expect((localizations[language] as? [String: Any])?["variations"] == nil)
            }
        }
    }

    @Test func theCaptionNowIsShortInEveryLanguage() throws {
        // Elle se pose sous le repère, sur une piste étroite : pas plus de 12 caractères.
        let catalog = try TranslationCatalog.loadCatalog(TranslationCatalogTests.localizable)
        let strings = try #require(catalog["strings"] as? [String: Any])
        let localizations = try #require((strings["now"] as? [String: Any])?["localizations"] as? [String: Any])
        for language in TranslationCatalog.requiredTranslations {
            let value = ((localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String ?? ""
            #expect(value.count <= 12, "\(language) : \(value)")
        }
    }
}
