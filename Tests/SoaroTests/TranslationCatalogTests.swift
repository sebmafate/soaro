import Foundation
import Testing
@testable import Soaro

/// Garde-fou des traductions (R12) : chaque clé du catalogue a une valeur non
/// vide dans les 8 langues, et les marqueurs de format (`%@`, `%lld`, `%d`,
/// `%%`, formes positionnelles `%1$@`) concordent avec le texte anglais.
///
/// Règles :
/// - Langues requises : la langue source du fichier (`en`) + `requiredTranslations`.
///   Dans `Localizable.xcstrings` l'anglais est la clé elle-même (pas d'entrée `en`) ;
///   dans `InfoPlist.xcstrings` la clé est un identifiant : l'entrée `en` est exigée.
/// - Chaque localisation doit être un `stringUnit` avec une `value` non vide ;
///   toute autre forme (`variations`, ...) est signalée « forme non prise en charge »,
///   jamais ignorée en silence.
/// - Exclusions : liste fermée de clés exactes (`excludedKeys`), chacune avec sa
///   raison. Une exclusion dont la clé n'existe plus est elle-même une erreur.
/// - Marqueurs : `%%` et les conversions Foundation avec `%n$` optionnel. Le drapeau
///   « espace » est volontairement reconnu : « 80 % de » se lit `% d`, un vrai défaut
///   (le `%` seul doit s'écrire `%%`). Chaque marqueur est ramené à sa position
///   (explicite ou séquentielle) ; on compare position → conversion exactement
///   (`%lld` ≠ `%d`). Un ordre différent passe ; manquant, en trop ou de type
///   différent échoue ; le nombre de `%%` doit être le même ; mélanger formes
///   positionnelles et simples dans une même chaîne est signalé.
/// - Cas particulier, vérifié à l'exécution : une clé anglaise SANS marqueur n'est
///   jamais passée à un formateur (`String(localized:)` renvoie la valeur telle
///   quelle). Dans ce cas « 100 % zu » est affiché correctement : un marqueur « en trop »
///   introduit seulement par le drapeau espace n'est pas signalé ; en revanche un
///   `%%` en trop s'afficherait tel quel (« 100 %% ») et reste signalé.
enum TranslationCatalog {
    static let requiredTranslations = ["de", "es", "fr", "it", "ja", "ko", "pt-BR", "zh-Hans"]

    /// Clés de `Localizable.xcstrings` sans traduction par construction (entrée `{}`).
    static let excludedKeys: [String: String] = [
        "": "chaîne vide, rien à traduire",
        "%@ %@": "deux valeurs séparées par une espace, sans mot",
        "%@ / %@": "deux valeurs séparées par une barre, sans mot",
        "%@ · %@": "deux valeurs séparées par un point médian, sans mot",
        "%lld °C": "nombre et symbole d'unité, identique dans toutes les langues",
    ]

    struct Gap: Equatable, CustomStringConvertible {
        let key: String
        let language: String
        let reason: String
        var description: String { "\(key.debugDescription) / \(language) / \(reason)" }
    }

    // MARK: Marqueurs de format

    struct Placeholders: Equatable {
        /// Position (1 = premier argument) → conversion (`@`, `d`, `lld`, ...).
        var byPosition: [Int: String] = [:]
        var percentCount = 0
        var mixesExplicitAndPlain = false
        /// Deux marqueurs sur la même position avec des conversions différentes.
        var conflictingPositions: [Int] = []
        /// Positions dont le marqueur n'existe que grâce au drapeau espace (« % d », « % zu »).
        var spaceFlagged: Set<Int> = []
    }

    private static let placeholderPattern = try! NSRegularExpression(
        pattern: #"%(?:(\d+)\$)?([-+ #0]*)(?:\d+|\*)?(?:\.\d+)?(hh|h|ll|l|q|L|z|t|j)?([@diuoxXfFeEgGcCsSpaA%])"#)

    static func placeholders(in text: String) -> Placeholders {
        var result = Placeholders()
        var sequential = 0
        var explicitSeen = false, plainSeen = false
        let ns = text as NSString
        for match in placeholderPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let conversion = ns.substring(with: match.range(at: 4))
            if conversion == "%" { result.percentCount += 1; continue }
            let kind = (match.range(at: 3).location != NSNotFound ? ns.substring(with: match.range(at: 3)) : "") + conversion
            let position: Int
            if match.range(at: 1).location != NSNotFound, let n = Int(ns.substring(with: match.range(at: 1))) {
                position = n; explicitSeen = true
            } else {
                sequential += 1; position = sequential; plainSeen = true
            }
            if ns.substring(with: match.range(at: 2)).contains(" ") { result.spaceFlagged.insert(position) }
            if let existing = result.byPosition[position], existing != kind { result.conflictingPositions.append(position) }
            result.byPosition[position] = kind
        }
        result.mixesExplicitAndPlain = explicitSeen && plainSeen
        return result
    }

    /// Raisons pour lesquelles `translation` ne reprend pas les marqueurs de `source`.
    static func placeholderProblems(source: String, translation: String) -> [String] {
        let s = placeholders(in: source), t = placeholders(in: translation)
        var problems: [String] = []
        if s.mixesExplicitAndPlain { problems.append("le texte anglais mélange marqueurs positionnels et simples") }
        if t.mixesExplicitAndPlain { problems.append("la traduction mélange marqueurs positionnels et simples") }
        if !t.conflictingPositions.isEmpty { problems.append("la traduction réutilise une position avec un type différent") }
        for position in s.byPosition.keys.sorted() {
            guard let expected = s.byPosition[position] else { continue }
            if let got = t.byPosition[position] {
                if got != expected { problems.append("marqueur \(position) : %\(got) au lieu de %\(expected)") }
            } else {
                problems.append("marqueur \(position) (%\(expected)) manquant")
            }
        }
        for position in t.byPosition.keys.sorted() where s.byPosition[position] == nil {
            if s.byPosition.isEmpty && t.spaceFlagged.contains(position) { continue }   // clé jamais formatée
            problems.append("marqueur \(position) (%\(t.byPosition[position] ?? "?")) en trop")
        }
        if s.percentCount != t.percentCount {
            problems.append("%% : \(t.percentCount) dans la traduction, \(s.percentCount) dans le texte anglais")
        }
        return problems
    }

    // MARK: Catalogue

    /// Fonction pure sur le JSON décodé d'un `.xcstrings`.
    static func gaps(
        in catalog: [String: Any],
        excluded: [String: String],
        required: [String] = requiredTranslations,
        sourceTextIsKey: Bool
    ) -> [Gap] {
        var gaps: [Gap] = []
        let source = catalog["sourceLanguage"] as? String ?? "en"
        guard let strings = catalog["strings"] as? [String: Any] else {
            return [Gap(key: "(catalogue)", language: "-", reason: "objet `strings` absent")]
        }
        for key in excluded.keys.sorted() where strings[key] == nil {
            gaps.append(Gap(key: key, language: "-", reason: "exclusion périmée : la clé n'existe plus dans le catalogue"))
        }
        for key in strings.keys.sorted() where excluded[key] == nil {
            let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any] ?? [:]

            // Valeur d'une langue : nil + lacune si absente, vide ou de forme inattendue.
            func value(for language: String) -> String? {
                guard let entry = localizations[language] as? [String: Any] else {
                    gaps.append(Gap(key: key, language: language, reason: "traduction absente"))
                    return nil
                }
                guard let unit = entry["stringUnit"] as? [String: Any] else {
                    gaps.append(Gap(key: key, language: language,
                                    reason: "forme non prise en charge (\(entry.keys.sorted().joined(separator: ", ")) sans stringUnit)"))
                    return nil
                }
                guard let text = unit["value"] as? String, !text.isEmpty else {
                    gaps.append(Gap(key: key, language: language, reason: "valeur vide"))
                    return nil
                }
                return text
            }

            var reference = key
            if !sourceTextIsKey || localizations[source] != nil {
                guard let text = value(for: source) else { continue }
                reference = text
            }
            for language in required where language != source {
                guard let text = value(for: language) else { continue }
                for problem in placeholderProblems(source: reference, translation: text) {
                    gaps.append(Gap(key: key, language: language, reason: problem))
                }
            }
        }
        return gaps
    }

    static func loadCatalog(_ relativePath: String) throws -> [String: Any] {
        let url = RepositoryRoot.url().appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CatalogError.notAnObject(relativePath)
        }
        return object
    }

    enum CatalogError: Error { case notAnObject(String) }
}

@Suite struct TranslationCatalogTests {
    static let localizable = "Sources/Soaro/Resources/Localizable.xcstrings"
    static let infoPlist = "Sources/Soaro/Resources/InfoPlist.xcstrings"

    // MARK: Catalogues réels

    private func report(_ gaps: [TranslationCatalog.Gap]) -> Comment {
        Comment(rawValue: "R12: \(gaps.count) lacune(s) (clé / langue / raison) :\n"
                + gaps.map { "  \($0)" }.joined(separator: "\n"))
    }

    @Test func realLocalizableCatalogIsCompleteInEveryLanguage() throws {
        let catalog = try TranslationCatalog.loadCatalog(Self.localizable)
        #expect((catalog["strings"] as? [String: Any])?.count ?? 0 > 100, "catalogue vide ou introuvable")
        let gaps = TranslationCatalog.gaps(in: catalog, excluded: TranslationCatalog.excludedKeys, sourceTextIsKey: true)
        #expect(gaps.isEmpty, report(gaps))
    }

    @Test func realInfoPlistCatalogIsCompleteInEveryLanguage() throws {
        let catalog = try TranslationCatalog.loadCatalog(Self.infoPlist)
        #expect((catalog["strings"] as? [String: Any])?["NSAppleEventsUsageDescription"] != nil)
        let gaps = TranslationCatalog.gaps(in: catalog, excluded: [:], sourceTextIsKey: false)
        #expect(gaps.isEmpty, report(gaps))
    }

    @Test func catalogSourceLanguageIsEnglish() throws {
        for path in [Self.localizable, Self.infoPlist] {
            #expect(try TranslationCatalog.loadCatalog(path)["sourceLanguage"] as? String == "en", "\(path)")
        }
    }

    // MARK: Fonctions pures, sur des dictionnaires en mémoire

    private func unit(_ value: String) -> [String: Any] { ["stringUnit": ["state": "translated", "value": value]] }

    /// Une clé traduite partout ; `override` remplace ou retire (nil) une langue.
    private func catalog(key: String = "Hello %@", translation: String = "Valeur",
                         overrides: [String: [String: Any]?] = [:]) -> [String: Any] {
        var localizations: [String: Any] = [:]
        for language in TranslationCatalog.requiredTranslations { localizations[language] = unit(translation) }
        for (language, entry) in overrides { localizations[language] = entry }
        return ["sourceLanguage": "en", "strings": [key: ["localizations": localizations]]]
    }

    private func gaps(_ catalog: [String: Any], excluded: [String: String] = [:]) -> [TranslationCatalog.Gap] {
        TranslationCatalog.gaps(in: catalog, excluded: excluded, sourceTextIsKey: true)
    }

    @Test func completeKeyPasses() {
        #expect(gaps(catalog(key: "Hello", translation: "Bonjour")).isEmpty)
        #expect(gaps(catalog(key: "Hello %@", translation: "Bonjour %@")).isEmpty)
    }

    @Test func missingLanguageFails() {
        let found = gaps(catalog(key: "Hello", translation: "Bonjour", overrides: ["ko": nil]))
        #expect(found == [.init(key: "Hello", language: "ko", reason: "traduction absente")])
    }

    @Test func emptyValueFails() {
        let found = gaps(catalog(key: "Hello", translation: "Bonjour", overrides: ["de": unit("")]))
        #expect(found == [.init(key: "Hello", language: "de", reason: "valeur vide")])
    }

    @Test func variationsAreReportedAsUnsupportedShape() {
        let variations: [String: Any] = ["variations": ["plural": ["one": unit("un"), "other": unit("des")]]]
        let found = gaps(catalog(key: "Hello", translation: "Bonjour", overrides: ["it": variations]))
        #expect(found.count == 1 && found[0].language == "it" && found[0].reason.contains("forme non prise en charge"))
    }

    @Test func keyWithoutLocalizationsFailsUnlessExcluded() {
        let bare: [String: Any] = ["sourceLanguage": "en", "strings": ["%@ %@": [String: Any]()]]
        #expect(gaps(bare).count == TranslationCatalog.requiredTranslations.count)
        #expect(gaps(bare, excluded: ["%@ %@": "séparateur"]).isEmpty)
    }

    @Test func staleExclusionFails() {
        let found = gaps(catalog(key: "Hello", translation: "Bonjour"), excluded: ["Gone": "plus utilisée"])
        #expect(found.count == 1 && found[0].key == "Gone" && found[0].reason.contains("exclusion périmée"))
    }

    @Test func realExclusionsAreExactlyTheFiveSeparatorKeys() {
        #expect(Set(TranslationCatalog.excludedKeys.keys) == ["", "%@ %@", "%@ / %@", "%@ · %@", "%lld °C"])
        #expect(TranslationCatalog.excludedKeys.values.allSatisfy { !$0.isEmpty })
    }

    @Test func infoPlistRequiresTheEnglishEntry() {
        var c = catalog(key: "NSAppleEventsUsageDescription", translation: "Texte")
        #expect(TranslationCatalog.gaps(in: c, excluded: [:], sourceTextIsKey: false)
                == [.init(key: "NSAppleEventsUsageDescription", language: "en", reason: "traduction absente")])
        var strings = c["strings"] as! [String: Any]
        var entry = strings["NSAppleEventsUsageDescription"] as! [String: Any]
        var localizations = entry["localizations"] as! [String: Any]
        localizations["en"] = unit("Text")
        entry["localizations"] = localizations
        strings["NSAppleEventsUsageDescription"] = entry
        c["strings"] = strings
        #expect(TranslationCatalog.gaps(in: c, excluded: [:], sourceTextIsKey: false).isEmpty)
    }

    // MARK: Marqueurs

    private func problems(_ source: String, _ translation: String) -> [String] {
        TranslationCatalog.placeholderProblems(source: source, translation: translation)
    }

    @Test func typeMismatchFails() {
        #expect(!problems("%lld files", "%@ fichiers").isEmpty)
        #expect(!problems("Process %d", "Processus %lld").isEmpty)
    }

    @Test func missingOrExtraPlaceholderFails() {
        #expect(!problems("%@ of %@", "%@ sur").isEmpty)
        #expect(!problems("%@", "%@ %@").isEmpty)
        #expect(!problems("Hello %@", "Bonjour").isEmpty)
    }

    @Test func positionalFormsMatchPlainForms() {
        #expect(problems("%@ of %@ used, %lld left", "%1$@ sur %2$@ utilisés, %3$lld restants").isEmpty)
    }

    @Test func reorderingPasses() {
        #expect(problems("%@ of %lld", "%2$lld de %1$@").isEmpty)
        #expect(problems("%1$@ then %2$lld", "%2$lld puis %1$@").isEmpty)
    }

    @Test func reorderingWithWrongTypeFails() {
        #expect(!problems("%@ of %lld", "%2$@ de %1$lld").isEmpty)
    }

    @Test func lostPercentEscapeFails() {
        #expect(!problems("100%% sure", "100 pour cent sûr").isEmpty)
        #expect(problems("100%% sure", "100 %% sûr").isEmpty)
    }

    @Test func bareSpacedPercentReadsAsAPlaceholder() {
        // « 80 % de » se lit `% d` : doit s'écrire « 80 %% de ».
        #expect(!problems("Above 80%% of the limit", "Plus de 80 % de la limite").isEmpty)
        #expect(problems("Above 80%% of the limit", "Plus de 80 %% de la limite").isEmpty)
    }

    @Test func spacedPercentIsAFalsePositiveOnlyWhenTheKeyIsNeverFormatted() {
        // Clé sans marqueur : valeur renvoyée telle quelle, « 100 % zu » s'affiche bien.
        #expect(problems("Back to 100 %, for example", "Auf 100 % zurück").isEmpty)
        // Clé avec marqueur : la valeur est formatée, « % d » consomme un argument.
        #expect(!problems("%@ at 80%% of the limit", "%@ à 80 % de la limite").isEmpty)
        // Un `%%` dans la traduction d'une clé sans marqueur s'afficherait tel quel.
        #expect(!problems("Back to 100 %, for example", "Revenir à 100 %%, par exemple").isEmpty)
        // Un vrai marqueur en trop (sans drapeau espace) reste signalé.
        #expect(!problems("Back to 100 %, for example", "Revenir à %@").isEmpty)
    }

    @Test func mixedPositionalAndPlainIsReported() {
        #expect(problems("%@ and %@", "%1$@ et %@").contains { $0.contains("mélange") })
    }

    @Test func lengthModifiersAndPrecisionAreRecognised() {
        #expect(placeholders("%.1f %lld %1$@") != placeholders("%.1f %lld"))
        #expect(placeholders("%.1f").byPosition == [1: "f"])
        #expect(placeholders("%lld").byPosition == [1: "lld"])
        #expect(placeholders("100%%").percentCount == 1)
    }

    private func placeholders(_ s: String) -> TranslationCatalog.Placeholders { TranslationCatalog.placeholders(in: s) }
}
