import Foundation
import Testing
@testable import Soaro

/// SL13 T8 (R12) : les textes de l'outil Docker sont dans le catalogue, dans les neuf langues (l'anglais est la clé), avec les mêmes marqueurs
/// de format. Les nouvelles traductions sont écrites avec l'aide d'une IA : à relire par l'auteur.
@Suite struct DockerStringsTests {
    /// Les clés NOUVELLES de SL13 et SL16 (« Clean », « Scan again », « Nothing selected », « Selected: %lld · %@ » et « Measuring… » existent déjà).
    static let newKeys = [
        "Docker",
        "Build cache and untagged images",
        "Can be cleaned",
        "Not touched",
        "Build cache",
        "Untagged images",
        "Containers",
        "Volumes",
        "Other unused images",
        "Rebuilt by your next build",
        "Images no container uses: %lld",
        "In use: %lld of %lld",
        "unknown size",
        "Docker did not say how big it is",
        "Containers, volumes and images with a tag are never removed here. Removing a tagged image means downloading it again.",
        "Measured as the change in free space about a minute after the cleanup. Other activity on this Mac can change it.",
        "Nothing to clean in Docker.",
        "Docker was not found on this Mac.",
        "Docker is not running. Start it, then scan again.",
        "Docker did not answer. Try again in a moment.",
        "Could not read Docker’s disk usage.",
        "Looking at Docker…",
        "Cleaning…",
        "Clean the selected Docker items? (%lld)",
        "About %@ will be removed:",
        "These will be removed:",
        "The next build will be slower, because the cache is rebuilt.",
        "Containers, volumes and images with a tag are not touched.",
        "%@ returned to this Mac, but Docker reported %@: Docker’s disk image did not give the space back.",
        "%@ returned to this Mac (Docker reported %@).",
        "%@ returned to this Mac.",
        "Docker reported %@. The space returned to this Mac could not be measured.",
        "The space returned to this Mac could not be measured.",
        "Cleanups that failed: %lld",
        // SL16
        "Soaro only cleans Docker on this Mac. The selected Docker engine or builder is not local.",
        "Docker engine: %@ (%@)",
    ]

    static func catalogStrings() throws -> [String: Any] {
        let catalog = try TranslationCatalog.loadCatalog(TranslationCatalogTests.localizable)
        return try #require(catalog["strings"] as? [String: Any])
    }

    @Test func everyNewKeyIsInTheCatalogInEveryLanguageWithMatchingMarkers() throws {
        let strings = try Self.catalogStrings()
        #expect(Set(Self.newKeys).count == Self.newKeys.count)
        for key in Self.newKeys {
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
                // Jamais de forme plurielle : le catalogue les refuse.
                #expect((localizations[language] as? [String: Any])?["variations"] == nil)
            }
        }
    }

    @Test func theProductNameStaysDockerInEveryTranslation() throws {
        let strings = try Self.catalogStrings()
        for key in Self.newKeys where key.contains("Docker") {
            let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            for language in TranslationCatalog.requiredTranslations {
                let value = ((localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String ?? ""
                #expect(value.contains("Docker"), "le nom du produit reste « Docker » : \(key.debugDescription) / \(language)")
            }
        }
    }

    // MARK: Chaque texte écrit dans le code Docker est dans le catalogue

    /// Le texte d'un littéral Swift, chaque `\(…)` remplacé par « § » (les parenthèses imbriquées sont suivies).
    static func normalised(_ literal: String) -> String {
        var out = "", depth = 0
        var iterator = literal.makeIterator()
        var previous: Character?
        while let c = iterator.next() {
            if depth > 0 {
                if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
                previous = c
                continue
            }
            if previous == "\\", c == "(" {
                out.removeLast()
                out.append("§")
                depth = 1
            } else {
                out.append(c)
            }
            previous = c
        }
        return out
    }

    static func dockerSourceFiles() throws -> [(name: String, text: String)] {
        let root = RepositoryRoot.url().appendingPathComponent("Sources/Soaro")
        var files: [(String, String)] = []
        for folder in ["Cleanup", "Views"] {
            let dir = root.appendingPathComponent(folder)
            for name in try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() where name.hasPrefix("Docker") && name.hasSuffix(".swift") {
                files.append((name, try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)))
            }
        }
        return files
    }

    @Test func everyLocalizedLiteralOfTheDockerFilesIsACatalogKey() throws {
        let strings = try Self.catalogStrings()
        let keys = Set(strings.keys.map { $0.replacingOccurrences(of: "%lld", with: "§").replacingOccurrences(of: "%@", with: "§") })
        let files = try Self.dockerSourceFiles()
        #expect(files.count >= 8, "les fichiers Docker sont introuvables")
        let pattern = try Regex(#"(?:String\(localized: |SectionHeader\(title: )"((?:[^"\\]|\\.)*)""#)
        var seen = 0
        for file in files {
            for match in file.text.matches(of: pattern) {
                let literal = Self.normalised(String(file.text[match.output[1].range!]))
                seen += 1
                #expect(keys.contains(literal), "\(file.name) : « \(literal) » n'est pas dans le catalogue")
            }
        }
        #expect(seen >= 30, "le contrôle ne doit pas être vide : \(seen) littéraux lus")
    }

    @Test func theNormaliserFollowsNestedParentheses() {
        #expect(Self.normalised(#"About \(Format.fileBytes(known, locale: locale)) will be removed:"#) == "About § will be removed:")
        #expect(Self.normalised(#"In use: \(active) of \(total)"#) == "In use: § of §")
        #expect(Self.normalised("Plain") == "Plain")
    }
}
