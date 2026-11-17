import Foundation
import Testing
@testable import Soaro

/// Mode démo : confirmer dans un outil ne supprime, ne met à la corbeille ni ne retire rien pour de vrai.
/// La confirmation est toujours demandée (mêmes textes, pour les captures d'écran) ; l'état en mémoire est mis à jour.
/// Aucun test ne répond « Oui » hors démo : ce serait la vraie corbeille ou le vrai Système.
@MainActor
private final class Answers {
    struct Ask: Equatable { let title: String; let message: String; let button: String; let critical: Bool }
    private(set) var asks: [Ask] = []
    private(set) var notifications: [String] = []
    private let answer: Bool
    init(_ answer: Bool) { self.answer = answer }

    var confirm: ConfirmHandler {
        { [self] title, message, button, critical in
            asks.append(Ask(title: title, message: message, button: button, critical: critical))
            return answer
        }
    }
    var notify: (String) -> Void { { [self] in notifications.append($0) } }
}

/// Compte les appels aux actions réelles de `StartupItemsService` (qui ne doivent pas avoir lieu en démo).
private final class StartupCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var removed = 0
    private var toggled = 0
    var removeCount: Int { lock.withLock { removed } }
    var toggleCount: Int { lock.withLock { toggled } }
    var remove: @Sendable (LoginItem) -> Bool { { [self] _ in lock.withLock { removed += 1 }; return true } }
    var toggle: @Sendable (LaunchAgentItem, Bool) -> Bool { { [self] _, _ in lock.withLock { toggled += 1 }; return true } }
}

@MainActor
@Suite struct DemoModeToolsTests {
    private func settle() async throws {
        for _ in 0..<20 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(100))
    }

    // MARK: Gros fichiers

    @Test func demoLargeFilesConfirmedTrashesNothingButUpdatesTheList() async throws {
        let box = try Sandbox(insideHome: true)
        let url = try box.file("movie.mov", bytes: 10)
        let file = LargeFile(url: url, size: 150_000_000, modified: nil)
        let answers = Answers(true)
        let model = LargeFilesModel(notify: answers.notify, confirm: answers.confirm, files: [file], demo: true)
        model.selected = [file.id]

        model.trashSelected()
        try await settle()

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(model.files.isEmpty)
        #expect(model.selected.isEmpty)
        #expect(answers.asks == [.init(
            title: "Move the selected files to the Trash? (1)",
            message: "\(Format.fileBytes(150_000_000)) will be freed once the Trash is emptied. You can still recover them from the Trash.",
            button: "Move to Trash", critical: false)])
        #expect(answers.notifications == ["\(Format.fileBytes(150_000_000)) moved to the Trash"])
    }

    @Test func demoLargeFilesCancelledChangesNothing() async throws {
        let box = try Sandbox(insideHome: true)
        let url = try box.file("movie.mov", bytes: 10)
        let file = LargeFile(url: url, size: 150_000_000, modified: nil)
        let answers = Answers(false)
        let model = LargeFilesModel(notify: answers.notify, confirm: answers.confirm, files: [file], demo: true)
        model.selected = [file.id]

        model.trashSelected()
        try await settle()

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(model.files == [file] && model.selected == [file.id])
        #expect(answers.notifications.isEmpty)
    }

    // MARK: Projets inactifs

    @Test func demoInactiveProjectsConfirmedDeletesNothingButUpdatesTheList() async throws {
        let box = try Sandbox(insideHome: true)
        try box.file("project/node_modules/dep/index.js", bytes: 10)
        let folder = box.root.appendingPathComponent("project/node_modules")
        let artifact = DevArtifact(url: folder, kind: .nodeModules, size: 20_000_000, lastActivity: nil)
        let answers = Answers(true)
        let model = DevArtifactsModel(notify: answers.notify, confirm: answers.confirm, artifacts: [artifact], demo: true)
        model.selected = [artifact.id]

        model.removeSelected()
        try await settle()

        #expect(box.exists("project/node_modules/dep/index.js"))
        #expect(model.artifacts.isEmpty)
        #expect(model.selected.isEmpty)
        #expect(answers.asks.map(\.button) == ["Delete"])
        #expect(answers.notifications == ["\(Format.fileBytes(20_000_000)) freed"])
    }

    @Test func demoInactiveProjectsCancelledChangesNothing() async throws {
        let box = try Sandbox(insideHome: true)
        try box.file("project/node_modules/dep/index.js", bytes: 10)
        let artifact = DevArtifact(url: box.root.appendingPathComponent("project/node_modules"), kind: .nodeModules, size: 20_000_000, lastActivity: nil)
        let answers = Answers(false)
        let model = DevArtifactsModel(notify: answers.notify, confirm: answers.confirm, artifacts: [artifact], demo: true)
        model.selected = [artifact.id]

        model.removeSelected()
        try await settle()

        #expect(box.exists("project/node_modules/dep/index.js"))
        #expect(model.artifacts == [artifact] && model.selected == [artifact.id])
        #expect(answers.notifications.isEmpty)
    }

    // MARK: Désinstalleur

    @Test func demoUninstallConfirmedTrashesNothingButUpdatesTheList() async throws {
        let box = try Sandbox(insideHome: true)
        try box.file("Fake.app/Contents/Info.plist", bytes: 10)
        let appURL = box.root.appendingPathComponent("Fake.app")
        let app = InstalledApp(url: appURL, name: "Fake", bundleID: "com.example.app", version: "1.0", size: 5_000_000, lastUsed: nil)
        let answers = Answers(true)
        let model = UninstallerModel(notify: answers.notify, confirm: answers.confirm, apps: [app], demo: true)
        model.select(app)                      // en démo : restes inventés (chemins du faux jeu de données), rien n'est lu
        let total = model.totalToFree
        #expect(!model.leftovers.isEmpty)

        model.uninstall()
        try await settle()

        #expect(FileManager.default.fileExists(atPath: appURL.path))
        #expect(model.apps.isEmpty)
        #expect(model.current == nil && model.leftovers.isEmpty)
        #expect(answers.asks.map(\.button) == ["Uninstall"])
        #expect(answers.asks.first?.critical == true)
        #expect(answers.notifications == ["“Fake” uninstalled · \(Format.fileBytes(total)) freed"])
    }

    @Test func demoUninstallCancelledChangesNothing() async throws {
        let box = try Sandbox(insideHome: true)
        try box.file("Fake.app/Contents/Info.plist", bytes: 10)
        let app = InstalledApp(url: box.root.appendingPathComponent("Fake.app"), name: "Fake", bundleID: "com.example.app", version: "1.0", size: 5_000_000, lastUsed: nil)
        let answers = Answers(false)
        let model = UninstallerModel(notify: answers.notify, confirm: answers.confirm, apps: [app], current: app, demo: true)

        model.uninstall()
        try await settle()

        #expect(box.exists("Fake.app/Contents/Info.plist"))
        #expect(model.apps == [app] && model.current == app)
        #expect(answers.notifications.isEmpty)
    }

    // MARK: Éléments de démarrage

    @Test func demoLoginItemRemovalNeverReachesTheSystemButUpdatesTheList() async throws {
        let item = LoginItem(name: "Example", path: "/nonexistent/Example.app")
        let calls = StartupCalls()
        let answers = Answers(true)
        let model = StartupModel(notify: answers.notify, confirm: answers.confirm, loginItems: [item], demo: true,
                                 removeLoginItem: calls.remove, setAgentEnabled: calls.toggle)

        model.remove(item)
        try await settle()

        #expect(calls.removeCount == 0)
        #expect(model.loginItems == [])
        #expect(answers.asks.map(\.button) == ["Remove"])
        #expect(answers.notifications.isEmpty)
    }

    @Test func demoLoginItemRemovalCancelledChangesNothing() async throws {
        let item = LoginItem(name: "Example", path: "/nonexistent/Example.app")
        let calls = StartupCalls()
        let answers = Answers(false)
        let model = StartupModel(notify: answers.notify, confirm: answers.confirm, loginItems: [item], demo: true,
                                 removeLoginItem: calls.remove, setAgentEnabled: calls.toggle)

        model.remove(item)
        try await settle()

        #expect(calls.removeCount == 0)
        #expect(model.loginItems == [item])
    }

    @Test func demoAgentToggleNeverReachesLaunchctlButFlipsTheSwitch() async throws {
        let calls = StartupCalls()
        let answers = Answers(true)
        let model = StartupModel(notify: answers.notify, confirm: answers.confirm, demo: true,
                                 removeLoginItem: calls.remove, setAgentEnabled: calls.toggle)
        model.load()
        let agent = try #require(model.agents.first { !$0.isDisabled })

        model.setEnabled(agent, enabled: false)
        try await settle()

        #expect(calls.toggleCount == 0)
        #expect(model.agents.first { $0.id == agent.id }?.isDisabled == true)
        #expect(answers.notifications.isEmpty)
    }

    // MARK: Hors démo : le comportement ne change pas (la suppression réelle passe par les mêmes appels)

    @Test func outsideDemoAnAgentToggleStillCallsTheService() async throws {
        let calls = StartupCalls()
        let agent = LaunchAgentItem(label: "com.example.helper", plist: URL(fileURLWithPath: "/nonexistent/com.example.helper.plist"),
                                    program: nil, runAtLoad: true, isUserOwned: true, isDisabled: false)
        let model = StartupModel(notify: { _ in }, confirm: Answers(false).confirm, demo: false,
                                 removeLoginItem: calls.remove, setAgentEnabled: calls.toggle)
        model.setEnabled(agent, enabled: false)
        try await settle()
        #expect(calls.toggleCount == 1)
    }

    @Test func outsideDemoAConfirmedLoginItemRemovalStillCallsTheService() async throws {
        let item = LoginItem(name: "Example", path: "/nonexistent/Example.app")
        let calls = StartupCalls()
        let model = StartupModel(notify: { _ in }, confirm: Answers(true).confirm, loginItems: [item], demo: false,
                                 removeLoginItem: calls.remove, setAgentEnabled: calls.toggle)
        model.remove(item)
        try await settle()
        #expect(calls.removeCount == 1)
        #expect(model.loginItems == [])
    }
}
