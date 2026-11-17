import Foundation
import Testing
@testable import Soaro

/// Garde « lecture seule » de SL12a : aucun code de suppression, de lancement ou de réseau dans les fichiers des images système.
/// (La suppression des images est SL12b ; ici rien ne peut être coché, sélectionné ni supprimé.)
@Suite(.serialized) struct AndroidSystemImageSourceTests {
    private func imageSources() throws -> [(name: String, text: String)] {
        let cleanup = RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Cleanup")
        let files = try FileManager.default.contentsOfDirectory(atPath: cleanup.path)
            .filter { $0.hasPrefix("AndroidSystemImage") && $0.hasSuffix(".swift") }.sorted()
        return try files.map { ($0, try String(contentsOf: cleanup.appendingPathComponent($0), encoding: .utf8)) }
    }

    /// LISTE DE MOTS, pas une preuve : un garde-fou qui échoue si l'un de ces motifs apparaît dans un fichier des images système. Il ne voit
    /// pas un appel écrit autrement (par exemple une référence de fonction sans parenthèse, ou un nom construit à l'exécution) ni le code
    /// des autres fichiers qui touchent aux images (`SimulatorsModel`, `Diagnostics`) : les deux sont revus à la main (voir TESTING.md).
    static let forbiddenWords = ["\"/bin/rm\"", "\"rm\"", "CommandRunner", "runner", "sdkmanager", "avdmanager", "URLSession", "posix_spawn", "NSTask"]
    /// Les mêmes familles d'appels, avec des espaces permis avant la parenthèse (`removeItem (at:`).
    static let forbiddenPatterns = [
        #"\bremoveItem\s*\("#, #"\btrashItem\s*\("#, #"\bmoveItem\s*\("#, #"\bcopyItem\s*\("#, #"\bcreateFile\s*\("#,
        #"\bunlink\s*\("#, #"\brename\s*\("#, #"\brmdir\s*\("#, #"\bsystem\s*\("#, #"\bProcess\s*\("#,
        #"\bwrite\s*\(\s*to\s*:"#, #"\bwrite\s*\(\s*toFile\s*:"#, #"FileHandle\s*\(\s*forWriting"#, #"FileHandle\s*\(\s*forUpdating"#,
    ]

    /// Les motifs interdits trouvés dans un texte de source.
    static func violations(in text: String) -> [String] {
        forbiddenWords.filter { text.contains($0) } + forbiddenPatterns.filter { text.range(of: $0, options: .regularExpression) != nil }
    }

    @Test func noImageSourceFileRemovesWritesLaunchesOrUsesTheNetwork() throws {
        let sources = try imageSources()
        #expect(!sources.isEmpty)
        for name in ["AndroidSystemImageScanner.swift", "AndroidSystemImagePresentation.swift", "AndroidSystemImageReport.swift"] {
            #expect(sources.contains { $0.name == name }, "\(name) est couvert par le garde-fou")
        }
        for source in sources {
            #expect(Self.violations(in: source.text).isEmpty, "\(source.name) contient \(Self.violations(in: source.text))")
        }
    }

    @Test(arguments: [
        "try FileManager.default.removeItem(at: url)", "try FileManager.default.removeItem (at: url)", "try fm.trashItem (at: u, resultingItemURL: nil)",
        "try fm.moveItem(at: a, to: b)", "try fm.copyItem(at: a, to: b)", "fm.createFile(atPath: p, contents: nil)", "unlink(path)", "unlink (path)",
        "rename(a, b)", "rmdir(path)", "system(\"ls\")", "let p = Process()", "Process ()", "try data.write(to: url)", "try data.write (to : url)",
        "try data.write(toFile: path, atomically: true, encoding: .utf8)", "FileHandle(forWriting: url)", "try FileHandle (forUpdating: url)",
        "posix_spawn(&pid, path, nil, nil, args, nil)", "let t = NSTask()", "let r: CommandRunner", "runner.run(", "\"/bin/rm\"", "\"rm\"",
        "sdkmanager --uninstall", "avdmanager delete avd", "URLSession.shared",
    ])
    func theWordListBitesOnEveryFamilyAndSpacingVariant(sample: String) {
        #expect(!Self.violations(in: sample).isEmpty, "\(sample) devrait être interdit")
    }

    @Test(arguments: [
        "AndroidEmulatorScanner.systemVersion(imageSysdir: value)", "let unlinkedCount = 0", "let renamed = true", "// lecture seule : le système d'images",
        "let operatingSystem = 1", "try? FileManager.default.contentsOfDirectory(atPath: p)", "FileHandle(forReadingFrom: url)",
    ])
    func theWordListLeavesReadingCodeAlone(sample: String) {
        #expect(Self.violations(in: sample).isEmpty, "\(sample) ne devrait pas être interdit : \(Self.violations(in: sample))")
    }

    // MARK: La vue (T7) : ni case à cocher, ni « Select all », ni ligne de sélection

    private func viewSource() throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Views/SimulatorsView.swift"), encoding: .utf8)
    }

    @Test func theImagesHeaderHasNoSelectAll() throws {
        let lines = try viewSource().split(separator: "\n", omittingEmptySubsequences: false).filter { $0.contains("Android system images") }
        #expect(lines.count >= 1, "l'en-tête de la section existe")
        for line in lines { #expect(!line.contains("selectAll"), "\(line)") }
        #expect(lines.contains { $0.contains("SectionHeader(title: \"Android system images\")") })
    }

    @Test func theImageRowIsNotASelectionRowAndHasNoControl() throws {
        let text = try viewSource()
        let start = try #require(text.range(of: "private func imageRow"), "la ligne d'image existe, en dernier dans le fichier")
        let row = String(text[start.lowerBound...])
        for forbidden in ["SelectionRow", "Button(", "isButton", "minus.circle", "checkmark", "circle\"", "keyboardShortcut", "onTapGesture",
                          "toggle", "selectAll"] {
            #expect(!row.contains(forbidden), "la ligne d'image contient \(forbidden)")
        }
        #expect(row.contains("SelectionMetrics.minimumTargetSize"), "le retrait à gauche est la largeur de la case")
        #expect(row.contains("AndroidSystemImagePresentation.accessibilityLabel"))
        #expect(!row.contains(".font(.system(size"), "styles de texte seulement")
    }

    @Test func onlyTheTwoDeviceRowsAreSelectionRows() throws {
        let text = try viewSource()
        #expect(text.components(separatedBy: "SelectionRow(").count - 1 == 2)
        #expect(text.components(separatedBy: "selectAll:").count - 1 == 2, "iOS et Android seulement")
    }

    @Test func theViewKeepsTheSectionOrderAndPassesTheImagesPhaseToTheLayout() throws {
        let text = try viewSource()
        let android = try #require(text.range(of: "SectionHeader(title: \"Android emulators\", selectAll"))
        let images = try #require(text.range(of: "SectionHeader(title: \"Android system images\")"))
        #expect(android.lowerBound < images.lowerBound)
        #expect(text.contains("images: model.imagesPhase"))
        #expect(text.contains("AndroidSystemImagePresentation.incompleteFooter"))
        #expect(text.contains("model.imagesUsageIncomplete"))
    }
}
