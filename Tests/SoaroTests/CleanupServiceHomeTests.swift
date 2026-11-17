import Foundation
import Testing
@testable import Soaro

/// Le dossier personnel est un paramètre de `CleanupService` (par défaut le vrai).
/// `isSafeToDelete` reste lié au vrai dossier personnel : un faux dossier ne peut rien élargir (ADR 0006).
@Suite struct CleanupServiceHomeTests {
    private let fakeHome = URL(fileURLWithPath: "/Users/test")

    @Test(arguments: [
        (CleanupKind.caches, "/Users/test/Library/Caches"),
        (.logs, "/Users/test/Library/Logs"),
        (.derivedData, "/Users/test/Library/Developer/Xcode/DerivedData"),
        (.trash, "/Users/test/.Trash"),
        (.npmCache, "/Users/test/.npm/_cacache"),
        (.gradleCache, "/Users/test/.gradle/caches"),
        (.cargoCache, "/Users/test/.cargo/registry/cache"),
        (.xcodeDeviceSupport, "/Users/test/Library/Developer/Xcode/iOS DeviceSupport"),
        (.simulatorCaches, "/Users/test/Library/Developer/CoreSimulator/Caches"),
    ])
    func directoryFollowsTheGivenHome(kind: CleanupKind, expected: String) {
        #expect(CleanupService.directory(for: kind, home: fakeHome).path == expected)
    }

    @Test func defaultHomeIsTheRealHome() {
        for kind in CleanupKind.allCases {
            #expect(CleanupService.directory(for: kind) == CleanupService.directory(for: kind, home: URL(fileURLWithPath: NSHomeDirectory())))
        }
    }

    @Test func itemsAndSizeReadTheGivenHome() throws {
        let box = try Sandbox(insideHome: true)
        try box.file(".npm/_cacache/content-v2/a", bytes: 20_000)
        try box.file(".npm/_cacache/index-v5/b", bytes: 30_000)

        let items = try #require(CleanupService.items(for: .npmCache, home: box.root))
        #expect(Set(items.map(\.lastPathComponent)) == ["content-v2", "index-v5"])
        let expected = items.reduce(UInt64(0)) { $0 + CleanupService.allocatedSize(of: $1) }
        #expect(expected > 0)
        #expect(CleanupService.size(of: .npmCache, home: box.root) == expected)
    }

    @Test func missingFolderGivesNoItemsAndNoSize() throws {
        let box = try Sandbox(insideHome: true)
        #expect(CleanupService.items(for: .npmCache, home: box.root) == nil)
        #expect(CleanupService.size(of: .npmCache, home: box.root) == nil)
    }

    @Test func cleaningInsideTheHomeFreesTheMeasuredSize() throws {
        let box = try Sandbox(insideHome: true)
        try box.file(".npm/_cacache/content-v2/a", bytes: 40_000)
        try box.file(".npm/_cacache/index-v5/b", bytes: 10_000)
        let before = try #require(CleanupService.size(of: .npmCache, home: box.root))

        let result = CleanupService.clean(.npmCache, home: box.root)

        #expect(result.freed == before)
        #expect(result.failures == 0 && result.error == nil)
        #expect(box.exists(".npm/_cacache"))
        #expect(CleanupService.size(of: .npmCache, home: box.root) == 0)
    }

    @Test func aHomeOutsideTheRealHomeIsListedButEveryDeletionIsRefused() throws {
        let box = try Sandbox()   // dans le dossier temporaire : hors du vrai dossier personnel
        try box.file(".npm/_cacache/content-v2/a", bytes: 20_000)
        try box.file(".npm/_cacache/index-v5/b", bytes: 20_000)

        let result = CleanupService.clean(.npmCache, home: box.root)

        #expect(result.failures == 2)
        #expect(result.freed == 0)
        #expect(box.exists(".npm/_cacache/content-v2/a"))
        #expect(box.exists(".npm/_cacache/index-v5/b"))
    }
}
