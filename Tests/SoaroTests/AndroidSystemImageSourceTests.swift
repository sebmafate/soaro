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

    @Test func noImageSourceFileRemovesWritesLaunchesOrUsesTheNetwork() throws {
        let sources = try imageSources()
        #expect(!sources.isEmpty)
        #expect(sources.contains { $0.name == "AndroidSystemImageScanner.swift" })
        let forbidden = ["removeItem(", "trashItem(", "moveItem(", "\"/bin/rm\"", "\"rm\"", "createFile(", "write(to:", "Process(",
                         "CommandRunner", "runner", "sdkmanager", "avdmanager", "URLSession"]
        for source in sources {
            for word in forbidden {
                #expect(!source.text.contains(word), "\(source.name) contient \(word)")
            }
        }
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
