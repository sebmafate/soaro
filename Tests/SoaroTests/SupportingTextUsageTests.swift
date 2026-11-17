import Foundation
import Testing

/// Garde au niveau du source (SL4 T2) : le texte d'information n'utilise ni `.secondary` ni `.tertiary`
/// (DESIGN.md partie 2), il passe par le jeton « texte de soutien ». Un cliquet par fichier :
/// - `allowed` : l'état final, seules les icônes, glyphes et chevrons gardent `.secondary` / `.tertiary` ;
/// - `pending` : bornes provisoires des fichiers pas encore migrés (chaque tâche en retire).
@Suite struct SupportingTextUsageTests {
    /// Occurrences autorisées dans l'état final : des icônes seulement (chaque occurrence a un `Image(` à proximité).
    static let allowed: [String: Int] = [
        "Views/Components.swift": 2,
        "Views/SelectionComponents.swift": 3,
        "Views/BatteryTab.swift": 1,
        "Views/MainWindow.swift": 1,
        "Views/CleanupToolViews.swift": 2,
        "Views/CleanupTab.swift": 1,
    ]

    /// Nombres exacts des fichiers pas encore migrés (commentaires exclus).
    static let pending: [String: Int] = [
        "Views/MainWindow.swift": 5,
        "Views/SettingsView.swift": 9,
        "Views/PopoverView.swift": 2,
    ]

    static let hint = "use `supportingText()` (DesignTokens) for text; icons may stay `.secondary` with an allowlist entry"

    // MARK: Lecture du source

    private static var sourcesRoot: URL { RepositoryRoot.url().appendingPathComponent("Sources/Soaro") }

    /// Tous les `.swift` sous `Sources/Soaro`, chemin relatif → lignes.
    private static func swiftFiles() throws -> [String: [String]] {
        let root = sourcesRoot
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys))
        var files: [String: [String]] = [:]
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let relative = String(url.path.dropFirst(root.path.count + 1))
            let text = try String(contentsOf: url, encoding: .utf8)
            files[relative] = text.components(separatedBy: "\n")
        }
        return files
    }

    private static let pattern = try! Regex(#"\.(secondary|tertiary)\b|secondaryLabelColor|tertiaryLabelColor"#)

    /// Numéros de ligne (à partir de 0) qui portent une occurrence, commentaires exclus.
    private static func hits(in lines: [String]) -> [Int] {
        var result: [Int] = []
        for (index, line) in lines.enumerated() where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
            result.append(contentsOf: Array(repeating: index, count: line.matches(of: pattern).count))
        }
        return result
    }

    /// Règle des icônes : un `Image(` sur la ligne ou dans les 3 lignes précédentes.
    private static func isNearAnImage(_ index: Int, in lines: [String]) -> Bool {
        lines[max(0, index - 3)...index].contains { $0.contains("Image(") }
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
    }

    /// Le corps d'un type de premier niveau : de sa déclaration jusqu'à l'accolade fermante en colonne 0.
    private func typeBody(_ declaration: String, in path: String) throws -> String {
        let text = try source(path)
        let start = try #require(text.range(of: declaration), "\(declaration) introuvable dans \(path)")
        let end = text.range(of: "\n}\n", range: start.upperBound..<text.endIndex)?.upperBound ?? text.endIndex
        return String(text[start.lowerBound..<end])
    }

    // MARK: Cliquet

    @Test func theScanReallyReadsTheSources() throws {
        let files = try Self.swiftFiles()
        #expect(files.count > 15, "le scan doit lire plus de 15 fichiers, il en a lu \(files.count)")
        #expect(files["Views/Components.swift"] != nil)
    }

    @Test func noFileUsesSecondaryOrTertiaryForTextBeyondItsRatchet() throws {
        let files = try Self.swiftFiles()
        for (file, lines) in files.sorted(by: { $0.key < $1.key }) {
            let found = Self.hits(in: lines)
            if let bound = Self.pending[file] {
                #expect(found.count == bound,
                        "\(file) : \(found.count) occurrence(s) de .secondary/.tertiary, \(bound) attendue(s) (cliquet provisoire) : \(Self.hint)")
                continue
            }
            let expected = Self.allowed[file] ?? 0
            #expect(found.count == expected,
                    "\(file) : \(found.count) occurrence(s) de .secondary/.tertiary, \(expected) autorisée(s) : \(Self.hint)")
            for index in found where !Self.isNearAnImage(index, in: lines) {
                Issue.record("\(file):\(index + 1) : .secondary/.tertiary sans `Image(` à proximité (3 lignes) : \(Self.hint)")
            }
        }
    }

    @Test func everyRatchetEntryNamesAFileThatExists() throws {
        let files = try Self.swiftFiles()
        for file in Set(Self.allowed.keys).union(Self.pending.keys) {
            #expect(files[file] != nil, "\(file) n'existe pas sous Sources/Soaro")
        }
    }

    // MARK: Une seule source de la couleur

    @Test func theTokenFunctionsAreUsedOnlyInsideDesignTokens() throws {
        let files = try Self.swiftFiles()
        for (file, lines) in files where file != "Views/DesignTokens.swift" {
            for (index, line) in lines.enumerated() {
                #expect(!line.contains("supportingTextColor(") && !line.contains("supportingTextAlpha("),
                        "\(file):\(index + 1) : la couleur du jeton ne se calcule que dans DesignTokens.swift (utiliser `.supportingText` ou `supportingText()`)")
            }
        }
    }

    // MARK: Pièces partagées nommées (T3)

    @Test func theActionBarSummaryUsesTheSupportingToken() throws {
        let body = try typeBody("struct ActionBar", in: "Sources/Soaro/Views/SelectionComponents.swift")
        #expect(body.contains("supportingText"))
        #expect(!body.contains(".secondary"))
        #expect(!body.contains(".tertiary"))
    }

    @Test func theEmptyHintAlwaysUsesTheSupportingTokenWithoutASupportingParameter() throws {
        let body = try typeBody("struct EmptyHint", in: "Sources/Soaro/Views/Components.swift")
        #expect(body.contains("supportingText"))
        #expect(!body.contains("supporting:"))
        #expect(!body.contains("let supporting"))
        #expect(!body.contains(".secondary"))
    }

    @Test func theSimulatorsScreenNoLongerPassesTheSupportingFlag() throws {
        let text = try source("Sources/Soaro/Views/SimulatorsView.swift")
        #expect(!text.contains("supporting: true"))
        #expect(!text.contains("supporting:"))
    }

    // MARK: Les autres lignes partagées (T4)

    @Test func theProcessColumnsUseTheTokenExceptTheHighlightedOne() throws {
        let body = try typeBody("struct ProcessRow", in: "Sources/Soaro/Views/Components.swift")
        #expect(!body.contains(".tertiary"))
        #expect(!body.contains(".secondary"))
        #expect(body.contains("supportingText"))
        #expect(body.contains("highlighted ? AnyShapeStyle(.primary)"), "la colonne triée reste en .primary")
    }

    @Test func theSharedRowsUseTheTokenForTheirSecondaryText() throws {
        for type in ["struct StatCard", "struct KeyValueRow", "struct CoreBars", "struct RecommendationRow", "struct AdviceRow"] {
            let body = try typeBody(type, in: "Sources/Soaro/Views/Components.swift")
            #expect(body.contains("supportingText"), "\(type) doit utiliser le jeton")
            #expect(!body.contains(".secondary"), "\(type) ne doit plus utiliser .secondary")
        }
        let cleanupRow = try typeBody("struct CleanupRow", in: "Sources/Soaro/Views/Components.swift")
        #expect(cleanupRow.contains("supportingText"))
        #expect(cleanupRow.contains("Image(systemName: kind.systemImage).frame(width: 20).foregroundStyle(.secondary)"), "l'icône du type reste .secondary")
    }
}
