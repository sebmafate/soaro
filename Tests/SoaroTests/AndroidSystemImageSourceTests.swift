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
}
