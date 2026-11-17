import Foundation
import Testing

/// Garde au niveau du source (SL4 T2) : le texte d'information n'utilise ni `.secondary` ni `.tertiary`
/// (DESIGN.md partie 2), il passe par le jeton « texte de soutien » (`.foregroundStyle(.supportingText)`).
///
/// Un cliquet par fichier, strict par défaut (tout autre fichier : zéro) :
/// - `allowed` : le nombre EXACT d'occurrences d'icônes, de glyphes et de chevrons qui gardent `.secondary` / `.tertiary`.
///   Une entrée ne suffit pas : chaque occurrence doit aussi avoir un `Image(` sur sa ligne ou dans les 3 lignes
///   précédentes (règle de proximité). L'entrée ne désactive jamais cette règle.
/// - `marked` : une exception explicite et relue, pour une décoration ou une icône dont le `Image(` est à plus de
///   3 lignes. Elle se déclare par un commentaire sur la ligne, ou seul sur la ligne juste au-dessus :
///   `// supporting-text: décoration` ou `// supporting-text: icône`. Ces occurrences sont comptées à part et plafonnées
///   par fichier (plafond 0 par défaut) : ajouter un marqueur impose donc de modifier ce fichier de test, donc une relecture.
///
/// Portée et limites (voir aussi TESTING.md) : l'expression est volontairement large. Elle compte toute occurrence du
/// membre `.secondary` ou `.tertiary` (dans `.foregroundStyle(`, `.fill(`, `Color.secondary`, un ternaire, sur plusieurs
/// lignes) et `secondaryLabelColor` / `tertiaryLabelColor`, au lieu de ne reconnaître que `.foregroundStyle(`, ce qui
/// manquerait les chaînes sur plusieurs lignes. Elle ne voit pas : un gris obtenu autrement (`Color.gray`, `.opacity(`
/// sur `.primary`), `.quaternary` sur du texte, ni l'échange d'une icône et d'un texte dans un fichier autorisé
/// (le compte reste juste et un `Image(` est proche).
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

    /// Plafond par fichier des occurrences portant un marqueur (aucune aujourd'hui).
    static let marked: [String: Int] = [:]

    static let markers = ["// supporting-text: décoration", "// supporting-text: icône"]

    static let hint = "use `.foregroundStyle(.supportingText)` (DesignTokens) for text; an icon may keep `.secondary` only if it has an `Image(` within the 3 preceding lines and the file's `allowed` count says so; otherwise mark the line `// supporting-text: décoration` or `// supporting-text: icône` and raise the file's `marked` cap in SupportingTextUsageTests (reviewed exception)"

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

    private static func isComment(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
    }

    private static func isMarker(_ line: String) -> Bool {
        markers.contains { line.contains($0) }
    }

    /// Occurrences (numéros de ligne à partir de 0, commentaires exclus), séparées en ordinaires et marquées.
    /// Une occurrence est marquée si sa ligne porte un marqueur, ou si la ligne juste au-dessus est un commentaire marqueur.
    static func scan(_ lines: [String]) -> (plain: [Int], marked: [Int]) {
        var plain: [Int] = [], marked: [Int] = []
        for (index, line) in lines.enumerated() where !isComment(line) {
            let count = line.matches(of: pattern).count
            guard count > 0 else { continue }
            let covered = isMarker(line) || (index > 0 && isComment(lines[index - 1]) && isMarker(lines[index - 1]))
            let repeated = Array(repeating: index, count: count)
            if covered { marked += repeated } else { plain += repeated }
        }
        return (plain, marked)
    }

    /// Copies littérales de la couleur du jeton (noir ou blanc à 0,56 ou 0,70) hors de `DesignTokens.swift`.
    private static let alphaLiteral = try! Regex(#"(opacity\(\s*|opacity:\s*|alphaComponent\(\s*|withAlphaComponent\(\s*)0?\.(56|7|70)\b"#)
    private static let colourWord = try! Regex(#"(?i)black|white|primary|labelColor|sRGB|NSColor|Color\("#)

    static func isLiteralCopyOfTheToken(_ line: String) -> Bool {
        !isComment(line) && line.contains(alphaLiteral) && line.contains(colourWord)
    }

    /// Les fonctions du jeton ne s'appellent que dans `DesignTokens.swift` (commentaires compris).
    static let tokenFunctions = ["supportingTextColor(", "supportingTextAlpha(", "supportingTextBase("]

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
            let found = Self.scan(lines)
            let expected = Self.allowed[file] ?? 0
            #expect(found.plain.count == expected,
                    "\(file) : \(found.plain.count) occurrence(s) de .secondary/.tertiary, \(expected) autorisée(s) (`allowed`) : \(Self.hint)")
            for index in found.plain where !Self.isNearAnImage(index, in: lines) {
                Issue.record("\(file):\(index + 1) : .secondary/.tertiary sans `Image(` dans les 3 lignes précédentes (une entrée `allowed` ne désactive pas cette règle) : \(Self.hint)")
            }
            let cap = Self.marked[file] ?? 0
            #expect(found.marked.count <= cap,
                    "\(file) : \(found.marked.count) occurrence(s) marquée(s) `supporting-text:`, plafond \(cap) (`marked`) : \(Self.hint)")
        }
    }

    @Test func everyRatchetEntryNamesAFileThatExists() throws {
        let files = try Self.swiftFiles()
        for file in Set(Self.allowed.keys).union(Self.marked.keys) {
            #expect(files[file] != nil, "\(file) n'existe pas sous Sources/Soaro")
        }
    }

    // MARK: Une seule source de la couleur

    @Test func theTokenFunctionsAndLiteralCopiesAreUsedOnlyInsideDesignTokens() throws {
        let files = try Self.swiftFiles()
        for (file, lines) in files where file != "Views/DesignTokens.swift" {
            for (index, line) in lines.enumerated() {
                for name in Self.tokenFunctions {
                    #expect(!line.contains(name),
                            "\(file):\(index + 1) : `\(name)` ne s'appelle que dans DesignTokens.swift (utiliser `.foregroundStyle(.supportingText)`)")
                }
                #expect(!Self.isLiteralCopyOfTheToken(line),
                        "\(file):\(index + 1) : copie littérale de la couleur du jeton (noir ou blanc à 0,56 / 0,70) : utiliser `.foregroundStyle(.supportingText)`")
            }
        }
    }

    // MARK: Le détecteur lui-même, sur des lignes d'exemple

    @Test func theScanCountsEveryFormOfSecondaryAndTertiaryButNotComments() {
        let lines = [
            "Text(a).foregroundStyle(.secondary)",
            "Circle().fill(.tertiary)",
            ".foregroundStyle(on ? Color.accentColor : Color.secondary)",
            "Color(nsColor: .secondaryLabelColor)",
            "// .secondary dans un commentaire",
            "/// .tertiary dans un commentaire de documentation",
            "Text(b).foregroundStyle(.supportingText)",
            "Text(c).foregroundStyle(.secondaryText)",
        ]
        let found = Self.scan(lines)
        #expect(found.plain == [0, 1, 2, 3], "trouvé : \(found.plain)")
        #expect(found.marked.isEmpty)
    }

    @Test func aMarkerOnTheLineOrJustAboveMakesTheOccurrenceMarkedNotPlain() {
        let lines = [
            "Divider().foregroundStyle(.secondary) // supporting-text: décoration",
            "// supporting-text: icône",
            "Image(systemName: \"x\")",
            "    .foregroundStyle(.secondary)",
            "// supporting-text: décoration",
            "Text(a).foregroundStyle(.secondary)",
            "",
            "Text(b).foregroundStyle(.secondary)",
        ]
        let found = Self.scan(lines)
        #expect(found.marked == [0, 5], "marquées : \(found.marked)")
        #expect(found.plain == [3, 7], "ordinaires : \(found.plain)")
        #expect(Self.marked.values.allSatisfy { $0 >= 0 })
    }

    @Test func anAllowedEntryDoesNotSilenceTheProximityRule() {
        let near = ["Image(systemName: \"a\")", ".font(.caption)", ".foregroundStyle(.secondary)"]
        let far = ["Image(systemName: \"a\")", ".font(.caption)", ".padding()", ".frame(width: 1)", ".foregroundStyle(.secondary)"]
        #expect(Self.isNearAnImage(2, in: near))
        #expect(!Self.isNearAnImage(4, in: far), "plus de 3 lignes après l'image : il faut un marqueur")
    }

    @Test func literalCopiesOfTheTokenColourAreRecognised() {
        let copies = [
            "Color.black.opacity(0.56)", "Color.white.opacity(0.56)", ".foregroundStyle(Color.primary.opacity(0.7))",
            "Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.56)", "NSColor.black.withAlphaComponent(0.70)",
        ]
        for line in copies { #expect(Self.isLiteralCopyOfTheToken(line), "à reconnaître : \(line)") }
        let others = [
            "Color.black.opacity(0.4)", "view.opacity(0.7)", "// Color.black.opacity(0.56)",
            "RoundedRectangle(cornerRadius: 7).fill(Color.accentColor.opacity(0.16))",
        ]
        for line in others { #expect(!Self.isLiteralCopyOfTheToken(line), "à laisser passer : \(line)") }
    }

    // MARK: Pièces partagées nommées (T3)

    @Test func theActionBarSummaryUsesTheSupportingToken() throws {
        let body = try typeBody("struct ActionBar", in: "Sources/Soaro/Views/SelectionComponents.swift")
        #expect(body.contains(".foregroundStyle(.supportingText)"), "une seule écriture : la forme style, comme le reste de l'app")
        #expect(!body.contains("supportingText()"))
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

    // MARK: Étiquette d'onglet du panneau (SL4 T7)

    @Test func thePanelTabLabelIsAccentWhenSelectedAndTheTokenOtherwise() throws {
        let text = try source("Sources/Soaro/Views/PopoverView.swift")
        let start = try #require(text.range(of: "VStack(spacing: 2)"), "l'étiquette d'onglet (VStack(spacing: 2)) est introuvable")
        let end = try #require(text.range(of: ".contentShape(Rectangle())", range: start.upperBound..<text.endIndex))
        let label = String(text[start.lowerBound..<end.lowerBound])
        let line = try #require(label.components(separatedBy: "\n").first { $0.contains(".foregroundStyle(state.activeTab == tab ?") },
                                "la ligne `.foregroundStyle(state.activeTab == tab ? …)` est introuvable")
        let parts = line.components(separatedBy: " ? ")
        let branches = try #require(parts.count == 2 ? parts[1].components(separatedBy: " : ") : nil, "forme attendue : condition ? sélectionné : sinon")
        #expect(branches.count == 2)
        #expect(branches[0].contains("Color.accentColor"), "sélectionné : accent, trouvé `\(branches[0])`")
        #expect(branches[1].contains(".supportingText"), "non sélectionné : le jeton, trouvé `\(branches[1])`")
        #expect(!label.contains(".primary"), "ni .primary dans l'étiquette d'onglet")
        #expect(!label.contains(".secondary") && !label.contains(".tertiary"))
    }
}
