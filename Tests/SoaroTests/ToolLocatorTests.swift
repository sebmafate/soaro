import Foundation
import Testing
@testable import Soaro

@Suite struct ToolLocatorTests {
    private func executable(_ box: Sandbox, _ name: String) throws -> String {
        let url = try box.file(name)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    @Test func returnsTheSecondCandidateWhenTheFirstIsMissing() throws {
        let box = try Sandbox()
        let second = try executable(box, "second-tool")
        let missing = box.root.appendingPathComponent("first-tool").path

        #expect(ToolLocator.firstExecutable(in: [missing, second]) == second)
    }

    @Test func returnsTheFirstOfTwoExistingCandidates() throws {
        let box = try Sandbox()
        let first = try executable(box, "first-tool")
        let second = try executable(box, "second-tool")
        #expect(ToolLocator.firstExecutable(in: [first, second]) == first)
    }

    @Test func returnsNothingWhenNoCandidateExists() throws {
        let box = try Sandbox()
        #expect(ToolLocator.firstExecutable(in: [box.root.appendingPathComponent("nope").path]) == nil)
        #expect(ToolLocator.firstExecutable(in: []) == nil)
    }

    @Test func rejectsADirectoryANonExecutableFileAndRelativePaths() throws {
        let box = try Sandbox()
        try box.dir("folder-tool")
        let plain = try box.file("plain-tool")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plain.path)

        #expect(ToolLocator.firstExecutable(in: [box.root.appendingPathComponent("folder-tool").path]) == nil)
        #expect(ToolLocator.firstExecutable(in: [plain.path]) == nil)
        #expect(ToolLocator.firstExecutable(in: ["ls", "./ls", "../bin/ls", ""]) == nil)
    }

    @Test func aRejectedCandidateDoesNotStopTheSearch() throws {
        let box = try Sandbox()
        try box.dir("folder-tool")
        let good = try executable(box, "good-tool")
        #expect(ToolLocator.firstExecutable(in: [box.root.appendingPathComponent("folder-tool").path, good]) == good)
    }

    @Test func simulatorCandidatesAreExactlyXcrunByAbsolutePath() {
        #expect(ToolLocator.simulatorCandidates == ["/usr/bin/xcrun"])
    }

    /// Faux gestionnaire de fichiers pour lequel TOUT existe et est exécutable : seul le refus d'un chemin relatif peut l'arrêter.
    private final class EverythingExistsFileManager: FileManager {
        override func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
            isDirectory?.pointee = false
            return true
        }
        override func isExecutableFile(atPath path: String) -> Bool { true }
    }

    @Test func aRelativeCandidateIsRefusedEvenIfItExistsRelativeToTheCurrentFolder() {
        let everything = EverythingExistsFileManager()
        // Sanity du faux : un chemin absolu est accepté.
        #expect(ToolLocator.firstExecutable(in: ["/usr/bin/xcrun"], fileManager: everything) == "/usr/bin/xcrun")
        // Un chemin relatif « existe » pour le faux, mais n'est jamais accepté, ni seul ni avant un chemin absolu valide.
        #expect(ToolLocator.firstExecutable(in: ["xcrun", "./xcrun", "../xcrun", "bin/xcrun", ""], fileManager: everything) == nil)
        #expect(ToolLocator.firstExecutable(in: ["./xcrun", "/usr/bin/xcrun"], fileManager: everything) == "/usr/bin/xcrun")
    }
}
