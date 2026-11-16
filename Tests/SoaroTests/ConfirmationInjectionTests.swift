import Foundation
import Testing
@testable import Soaro

/// Enregistre les confirmations demandées et répond toujours « Annuler ».
@MainActor
final class CancelRecorder {
    struct Call: Equatable {
        let title: String
        let message: String
        let button: String
        let critical: Bool
    }

    private(set) var calls: [Call] = []
    private(set) var notifications: [String] = []

    /// Confirmation injectée : refuse toujours. Aucun test ne confirme pour de vrai.
    var confirmation: ConfirmHandler {
        { [self] title, message, button, critical in
            calls.append(Call(title: title, message: message, button: button, critical: critical))
            return false
        }
    }

    var notify: (String) -> Void {
        { [self] message in notifications.append(message) }
    }
}

/// R8 : annuler la confirmation ne touche à rien, et ne notifie rien.
@MainActor
@Suite struct CancelledConfirmationTests {
    @Test func cancellingLargeFilesTrashingKeepsFilesAndState() throws {
        let box = try Sandbox(insideHome: true)
        let url = try box.file("movie.mov", bytes: 10)
        let file = LargeFile(url: url, size: 150_000_000, modified: nil)
        let recorder = CancelRecorder()
        let model = LargeFilesModel(notify: recorder.notify, confirm: recorder.confirmation, files: [file])
        model.selected = [file.id]

        model.trashSelected()

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(model.files == [file])
        #expect(model.selected == [file.id])
        #expect(recorder.notifications.isEmpty)
        #expect(recorder.calls == [CancelRecorder.Call(
            title: String(localized: "Move the selected files to the Trash? (\(1))"),
            message: String(localized: "\(Format.fileBytes(150_000_000)) will be freed once the Trash is emptied. You can still recover them from the Trash."),
            button: String(localized: "Move to Trash"),
            critical: false
        )])
    }

    @Test func largeFilesWithoutSelectionDoesNotAsk() {
        let recorder = CancelRecorder()
        let model = LargeFilesModel(notify: recorder.notify, confirm: recorder.confirmation,
                                    files: [LargeFile(url: URL(fileURLWithPath: "/nonexistent/Example.bin"), size: 1, modified: nil)])
        model.trashSelected()
        #expect(recorder.calls.isEmpty)
        #expect(recorder.notifications.isEmpty)
    }

    @Test func cancellingInactiveProjectsRemovalKeepsFolderAndState() async throws {
        let box = try Sandbox(insideHome: true)
        try box.file("project/node_modules/dep/index.js", bytes: 10)
        let folder = box.root.appendingPathComponent("project/node_modules")
        let artifact = DevArtifact(url: folder, kind: .nodeModules, size: 20_000_000, lastActivity: nil)
        let recorder = CancelRecorder()
        let model = DevArtifactsModel(notify: recorder.notify, confirm: recorder.confirmation, artifacts: [artifact])
        model.selected = [artifact.id]

        model.removeSelected()
        // La suppression passe par une tâche asynchrone : on lui laisse le temps de s'exécuter si elle existait.
        for _ in 0..<20 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(100))

        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(box.exists("project/node_modules/dep/index.js"))
        #expect(model.artifacts == [artifact])
        #expect(model.selected == [artifact.id])
        #expect(recorder.notifications.isEmpty)
        #expect(recorder.calls == [CancelRecorder.Call(
            title: String(localized: "Delete the selected rebuildable folders? (\(1))"),
            message: String(localized: "\(Format.fileBytes(20_000_000)) will be freed. Your sources are not touched: just run “npm install”, “swift build”… to rebuild them."),
            button: String(localized: "Delete"),
            critical: false
        )])
    }
}
