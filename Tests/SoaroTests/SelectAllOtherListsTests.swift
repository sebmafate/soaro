import Foundation
import Testing
@testable import Soaro

/// « Select all » dans les trois autres listes : une seule section chacune, aucune ligne indisponible.
@MainActor
@Suite struct OtherListsSelectAllTests {
    func file(_ n: Int, size: UInt64 = 150_000_000) -> LargeFile {
        LargeFile(url: URL(fileURLWithPath: "/Users/test/Movies/big-\(n).mov"), size: size, modified: nil)
    }

    func artifact(_ n: Int) -> DevArtifact {
        DevArtifact(url: URL(fileURLWithPath: "/Users/test/code/project-\(n)/node_modules"), kind: .nodeModules, size: 20_000_000, lastActivity: nil)
    }

    @Test func largeFilesSelectAllChecksEveryFileAndDeselectAllClears() {
        let model = LargeFilesModel(notify: { _ in }, confirm: { _, _, _, _ in false }, files: [file(1), file(2), file(3)], demo: true)
        #expect(model.selectAllState == .none)
        model.toggle(file(1))
        #expect(model.selectAllState == .some)
        model.toggleAll()
        #expect(model.selected == Set([file(1), file(2), file(3)].map(\.id)) && model.selectAllState == .all)
        #expect(model.selectedSize == 450_000_000)
        model.toggleAll()
        #expect(model.selected.isEmpty && model.selectAllState == .none)
        model.setAllSelected(true)
        #expect(model.selectedFiles.count == 3)
    }

    @Test func largeFilesWithoutFilesHasADisabledCheckbox() {
        let model = LargeFilesModel(notify: { _ in }, confirm: { _, _, _, _ in false }, files: [], demo: true)
        #expect(!model.canSelectAll)
        model.setAllSelected(true)
        #expect(model.selected.isEmpty)
    }

    @Test func inactiveProjectsSelectAllChecksEveryFolderAndKeepsTheTotals() {
        let items = [artifact(1), artifact(2)]
        let model = DevArtifactsModel(notify: { _ in }, confirm: { _, _, _, _ in false }, artifacts: items, demo: true)
        model.setAllSelected(true)
        #expect(model.selected == Set(items.map(\.id)) && model.selectAllState == .all)
        #expect(model.selectedSize == 40_000_000)
        model.toggle(items[0])
        #expect(model.selectAllState == .some)
        model.toggleAll()
        #expect(model.selectAllState == .all, "mixte : tout cocher")
        model.setAllSelected(false)
        #expect(model.selected.isEmpty)
        #expect(!DevArtifactsModel(notify: { _ in }, confirm: { _, _, _, _ in false }, artifacts: [], demo: true).canSelectAll)
    }

    func uninstaller() -> UninstallerModel {
        let app = InstalledApp(url: URL(fileURLWithPath: "/Applications/Fake.app"), name: "Fake", bundleID: "com.example.fake", version: "1.0",
                               size: 5_000_000, lastUsed: nil)
        let model = UninstallerModel(notify: { _ in }, confirm: { _, _, _, _ in false }, apps: [app], demo: true)
        model.select(app)      // démo : les restes inventés, en mémoire, aucune lecture du disque
        return model
    }

    @Test func uninstallerRelatedFilesAreAllCheckedByDefaultAndSelectAllFollowsTheExcludedSet() throws {
        let model = uninstaller()
        try #require(!model.leftovers.isEmpty)
        #expect(model.selectAllState == .all, "tout est coché au départ (exclus : aucun)")
        model.toggleAll()
        #expect(model.selectAllState == .none && model.selectedLeftovers.isEmpty)
        #expect(model.totalToFree == 5_000_000, "seule l'application reste")
        model.toggleAll()
        #expect(model.selectAllState == .all && model.selectedLeftovers.count == model.leftovers.count)
        let first = try #require(model.leftovers.first)
        model.excluded.insert(first.id)
        #expect(model.selectAllState == .some)
        model.toggleAll()
        #expect(model.excluded.isEmpty && model.selectAllState == .all, "mixte : tout cocher")
        model.setAllSelected(false)
        #expect(model.excluded == Set(model.leftovers.map(\.id)))
    }

    @Test func uninstallerWithoutRelatedFilesHasADisabledCheckbox() {
        let app = InstalledApp(url: URL(fileURLWithPath: "/Applications/Fake.app"), name: "Fake", bundleID: "com.example.fake", version: "1.0",
                               size: 5_000_000, lastUsed: nil)
        let model = UninstallerModel(notify: { _ in }, confirm: { _, _, _, _ in false }, apps: [app], current: app, demo: true)
        #expect(!model.canSelectAll)
        model.setAllSelected(false)
        #expect(model.excluded.isEmpty)
    }
}
