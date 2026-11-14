import Foundation
import Testing
@testable import Soaro

/// Arborescence temporaire supprimée à la fin du test.
private final class Sandbox {
    let root: URL

    /// `insideHome` : nécessaire pour tester les suppressions, que `isSafeToDelete` limite au dossier personnel.
    init(insideHome: Bool = false) throws {
        let base = insideHome ? URL(fileURLWithPath: NSHomeDirectory()) : FileManager.default.temporaryDirectory
        root = base.appendingPathComponent(insideHome ? ".soaro-test-\(UUID().uuidString)" : "soaro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func file(_ path: String, bytes: Int = 10, age days: Int? = nil) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
        if let days {
            let date = Date().addingTimeInterval(-Double(days) * 86_400)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        return url
    }

    func dir(_ path: String) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
    }

    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) }
}

@Suite struct LargeFileScannerTests {
    @Test func findsOnlyLargeFilesSortedBySize() throws {
        let box = try Sandbox()
        try box.file("movie.mov", bytes: 600_000)
        try box.file("docs/archive.zip", bytes: 300_000)
        try box.file("small.txt", bytes: 1_000)

        let found = LargeFileScanner.scan(roots: [box.root], minSize: 100_000)
        #expect(found.map(\.name) == ["movie.mov", "archive.zip"])
    }

    @Test func skipsLibraryNodeModulesAndPackages() throws {
        let box = try Sandbox()
        try box.file("Library/Caches/huge.bin", bytes: 500_000)
        try box.file("project/node_modules/dep/huge.bin", bytes: 500_000)
        try box.file("Thing.app/Contents/MacOS/binary", bytes: 500_000)
        try box.file("keep/real.bin", bytes: 500_000)

        let found = LargeFileScanner.scan(roots: [box.root], minSize: 100_000)
        #expect(found.map(\.id).count == 1)
        #expect(found.first?.name == "real.bin")
    }

    @Test func skipsDevArtifactsButNotLookalikes() throws {
        let box = try Sandbox()
        try box.file("rust/Cargo.toml")
        try box.file("rust/target/debug/huge.rlib", bytes: 500_000)          // vrai artefact : ignoré
        try box.file("media/target/footage.mov", bytes: 500_000)             // dossier « target » sans projet : gardé
        let found = LargeFileScanner.scan(roots: [box.root], minSize: 100_000)
        #expect(found.map(\.name) == ["footage.mov"])
    }

    @Test func skipsGeneratedBuildOutputOnlyInsideProjects() throws {
        let box = try Sandbox()
        try box.file("app/package.json")
        try box.file("app/build/bundle.js", bytes: 500_000)                  // sortie de build d'un projet : ignorée
        try box.file("photos/build/IMG_0001.raw", bytes: 500_000)            // « build » sans projet : gardé
        let found = LargeFileScanner.scan(roots: [box.root], minSize: 100_000)
        #expect(found.map(\.name) == ["IMG_0001.raw"])
    }

    @Test func honoursCancellationAndLimit() throws {
        let box = try Sandbox()
        for i in 0..<5 { try box.file("f\(i).bin", bytes: 200_000 + i * 1_000) }
        #expect(LargeFileScanner.scan(roots: [box.root], minSize: 100_000, limit: 3).count == 3)
        #expect(LargeFileScanner.scan(roots: [box.root], minSize: 100_000, isCancelled: { true }).isEmpty)
    }

    @Test func refusesToTrashOutsideHome() throws {
        let box = try Sandbox()
        let url = try box.file("outside.bin", bytes: 200_000)
        let file = LargeFile(url: url, size: 200_000, modified: nil)
        let result = LargeFileScanner.trash([file])
        #expect(result.failures == 1 && result.freed == 0)
        #expect(box.exists("outside.bin"))
    }
}

@Suite struct DevArtifactScannerTests {
    @Test func findsArtifactsOnlyWithTheirManifest() throws {
        let box = try Sandbox()
        try box.file("web/package.json")
        try box.file("web/node_modules/dep/index.js", bytes: 50_000)
        try box.file("lib/Package.swift")
        try box.file("lib/.build/debug/obj", bytes: 40_000)
        try box.file("orphan/target/classes/A.class", bytes: 30_000)          // pas de Cargo.toml/pom.xml : ignoré
        try box.file("random/node_modules/x.js", bytes: 30_000)               // pas de package.json : ignoré

        let found = DevArtifactScanner.scan(roots: [box.root], minSize: 0)
        #expect(Set(found.map(\.kind)) == [.nodeModules, .swiftBuild])
        #expect(found.first?.kind == .nodeModules)                            // trié par taille
        #expect(found.allSatisfy { $0.size > 0 })
    }

    @Test func doesNotDescendIntoArtifactsOrCountNestedOnes() throws {
        let box = try Sandbox()
        try box.file("app/package.json")
        try box.file("app/node_modules/pkg/package.json")                      // package.json imbriqué
        try box.file("app/node_modules/pkg/node_modules/deep/x.js", bytes: 20_000)
        #expect(DevArtifactScanner.scan(roots: [box.root], minSize: 0).count == 1)
    }

    @Test func measuresInactivityFromManifestDate() throws {
        let box = try Sandbox()
        try box.file("old/package.json", age: 200)
        try box.file("old/node_modules/x.js", bytes: 20_000)
        try box.file("fresh/package.json", age: 2)
        try box.file("fresh/node_modules/x.js", bytes: 20_000)

        let found = DevArtifactScanner.scan(roots: [box.root], minSize: 0)
        let old = try #require(found.first { $0.projectName == "old" })
        let fresh = try #require(found.first { $0.projectName == "fresh" })
        #expect((old.daysInactive() ?? 0) >= 199)
        #expect((fresh.daysInactive() ?? 99) <= 3)
    }

    @Test func gitActivityKeepsAProjectFresh() throws {
        let box = try Sandbox()
        try box.file("proj/package.json", age: 300)
        try box.file("proj/.git/index", age: 1)
        try box.file("proj/node_modules/x.js", bytes: 20_000)
        let artifact = try #require(DevArtifactScanner.scan(roots: [box.root], minSize: 0).first)
        #expect((artifact.daysInactive() ?? 99) <= 2)
    }

    @Test func ignoresTinyArtifactsByDefault() throws {
        let box = try Sandbox()
        try box.file("ws/package.json")
        try box.file("ws/node_modules/.bin/x", bytes: 100)                      // workspace quasi vide
        try box.file("big/package.json")
        try box.file("big/node_modules/dep/a.js", bytes: 1_500_000)
        let found = DevArtifactScanner.scan(roots: [box.root])
        #expect(found.map(\.projectName) == ["big"])
        #expect(DevArtifactScanner.scan(roots: [box.root], minSize: 0).count == 2)
    }

    @Test func skipsHiddenAndExcludedFolders() throws {
        let box = try Sandbox()
        try box.file(".cache/p/package.json")
        try box.file(".cache/p/node_modules/x.js", bytes: 20_000)
        try box.file("Library/p/package.json")
        try box.file("Library/p/node_modules/x.js", bytes: 20_000)
        try box.file(".t3/projects/p/package.json")
        try box.file(".t3/projects/p/node_modules/x.js", bytes: 20_000)
        let found = DevArtifactScanner.scan(roots: [box.root], minSize: 0)
        #expect(found.count == 1)
        #expect(found.first?.url.path.contains("/.t3/") == true)
    }

    @Test func removeDeletesOnlyInsideHomeAndWithManifest() throws {
        let outside = try Sandbox()
        try outside.file("p/package.json")
        try outside.file("p/node_modules/x.js", bytes: 20_000)
        let outsideArtifact = try #require(DevArtifactScanner.scan(roots: [outside.root], minSize: 0).first)
        #expect(!DevArtifactScanner.remove(outsideArtifact))                  // hors du dossier personnel
        #expect(outside.exists("p/node_modules"))

        let inside = try Sandbox(insideHome: true)
        try inside.file("p/package.json")
        try inside.file("p/node_modules/x.js", bytes: 20_000)
        let artifact = try #require(DevArtifactScanner.scan(roots: [inside.root], minSize: 0).first)
        #expect(DevArtifactScanner.remove(artifact))
        #expect(!inside.exists("p/node_modules"))
        #expect(inside.exists("p/package.json"))                              // le projet est intact
    }
}

@Suite struct AppUninstallerTests {
    private func app(_ name: String = "Foo", id: String? = "com.example.Foo") -> InstalledApp {
        InstalledApp(url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name, bundleID: id, version: "1.0")
    }

    @Test func matchingIsStrict() {
        func m(_ entry: String, name: String = "Foo", allowName: Bool = false, group: Bool = false) -> Bool {
            AppUninstaller.matches(entry: entry, bundleID: "com.example.Foo", appName: name, allowNameMatch: allowName, group: group)
        }
        #expect(m("com.example.Foo"))
        #expect(m("com.example.Foo.plist"))
        #expect(m("com.example.Foo.savedState"))
        #expect(!m("com.example.FooBar"))                  // autre app au nom voisin
        #expect(!m("com.example"))
        #expect(!m("ABCDE12345.com.example.Foo"))           // préfixe d'équipe : seulement dans Group Containers
        #expect(m("ABCDE12345.com.example.Foo", group: true))
        #expect(!m("Foo", allowName: true))                 // nom trop court (< 4)
        #expect(m("Notes App", name: "Notes App", allowName: true))
        #expect(!m("Notes App", name: "Notes App", allowName: false))
        #expect(!m("Notes App Pro", name: "Notes App", allowName: true))
    }

    @Test func shortOrGenericBundleIdsNeverMatchByPrefix() {
        #expect(!AppUninstaller.matches(entry: "com.apple.Safari", bundleID: "com.apple", appName: "X", allowNameMatch: false, group: false))
        #expect(!AppUninstaller.matches(entry: "anything", bundleID: nil, appName: "X", allowNameMatch: false, group: false))
    }

    @Test func findsLeftoversInLibrary() throws {
        let box = try Sandbox()
        try box.file("Application Support/com.example.Foo/data.db", bytes: 10_000)
        try box.file("Application Support/Another/data.db")
        try box.file("Caches/com.example.Foo/c", bytes: 5_000)
        try box.file("Caches/com.example.FooBar/c")                  // ne doit pas être pris
        try box.file("Preferences/com.example.Foo.plist")
        try box.file("Group Containers/ABCDE12345.com.example.Foo/x")
        try box.file("Containers/com.example.Foo/Data/x")
        try box.file("Preferences/com.example.Other.plist")

        let found = AppUninstaller.leftovers(for: app(), library: box.root)
        let names = Set(found.map { $0.url.lastPathComponent })
        #expect(names == ["com.example.Foo", "com.example.Foo.plist", "ABCDE12345.com.example.Foo"])
        #expect(found.count == 5)       // Application Support, Caches, Preferences, Group Containers, Containers
    }

    @Test func appleAndOwnAppsCannotBeUninstalled() {
        #expect(!AppUninstaller.canUninstall(app("Pages", id: "com.apple.iWork.Pages")))
        #expect(AppUninstaller.canUninstall(app()))
    }

    @Test func uninstallRefusesWhenAppIsNotUninstallable() {
        let result = AppUninstaller.uninstall(app("Pages", id: "com.apple.iWork.Pages"), leftovers: [])
        #expect(result.failures == ["Pages"] && result.freed == 0)
    }
}

@Suite struct StartupItemsTests {
    @Test func parsesDisabledServices() {
        let output = """
        disabled services = {
        \t"com.example.helper" => disabled
        \t"com.example.keep" => enabled
        \t"com.vendor.updater" => disabled
        }
        """
        #expect(StartupItemsService.parseDisabled(output) == ["com.example.helper", "com.vendor.updater"])
    }

    @Test func listsNonAppleLaunchAgents() throws {
        let box = try Sandbox()
        func write(_ name: String, _ plist: [String: Any]) throws {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: box.root.appendingPathComponent(name))
        }
        try write("com.vendor.updater.plist", ["Label": "com.vendor.updater", "ProgramArguments": ["/Applications/V.app/updater", "-d"], "RunAtLoad": true])
        try write("com.apple.thing.plist", ["Label": "com.apple.thing"])
        try write("broken.plist", ["NoLabel": true])
        try Data("garbage".utf8).write(to: box.root.appendingPathComponent("junk.plist"))

        let items = StartupItemsService.launchAgents(in: [box.root], disabled: ["com.vendor.updater"])
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.label == "com.vendor.updater")
        #expect(item.program == "/Applications/V.app/updater")
        #expect(item.runAtLoad && item.isDisabled)
        #expect(item.displayName == "updater")
    }

    @Test func appleAgentsCannotBeToggled() {
        let item = LaunchAgentItem(label: "com.apple.foo", plist: URL(fileURLWithPath: "/x"), program: nil, runAtLoad: true, isUserOwned: false, isDisabled: false)
        #expect(!StartupItemsService.setEnabled(item, enabled: false))
    }

    @Test func parsesLoginItems() {
        let output = "Dropbox|/Applications/Dropbox.app\nRaycast|/Applications/Raycast.app\n\nbad line\n"
        #expect(StartupItemsService.parseLoginItems(output).map(\.name) == ["Dropbox", "Raycast"])
    }
}

@Suite struct CleanupKindTests {
    @Test func quickCleanIsSafeSubset() {
        #expect(Set(CleanupKind.allCases.filter(\.includedInQuickClean)) == [.caches, .logs, .derivedData])
        #expect(!CleanupKind.trash.includedInQuickClean)
        #expect(CleanupKind.systemKinds.allSatisfy { !$0.isDeveloper })
    }

    @Test func everyKindStaysInsideHome() {
        for kind in CleanupKind.allCases {
            #expect(CleanupService.isSafeToDelete(CleanupService.directory(for: kind).appendingPathComponent("x")), "\(kind)")
        }
    }
}
