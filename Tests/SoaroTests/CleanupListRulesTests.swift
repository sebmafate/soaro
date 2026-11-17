import Foundation
import Testing
@testable import Soaro

/// Règles pures de la liste Nettoyage : rangées « Développeur » visibles et total du nettoyage rapide.
@Suite struct CleanupListRulesTests {
    private let gb: UInt64 = 1_000_000_000

    @Test func aKnownNonZeroSizeShowsTheRow() {
        let sizes: [CleanupKind: UInt64?] = [.nugetCache: 13 * gb]
        #expect(CleanupKind.visibleDeveloperKinds(sizes: sizes) == [.nugetCache])
    }

    @Test func unknownZeroAndMissingSizesHideTheRow() {
        #expect(CleanupKind.visibleDeveloperKinds(sizes: [.nugetCache: nil]).isEmpty)
        #expect(CleanupKind.visibleDeveloperKinds(sizes: [.nugetCache: 0]).isEmpty)
        #expect(CleanupKind.visibleDeveloperKinds(sizes: [:]).isEmpty)
    }

    @Test func visibleRowsKeepTheDeclarationOrder() {
        let sizes: [CleanupKind: UInt64?] = [.xcodeDeviceSupport: gb, .nugetCache: gb, .npmCache: gb, .cargoCache: 0]
        #expect(CleanupKind.visibleDeveloperKinds(sizes: sizes) == [.npmCache, .nugetCache, .xcodeDeviceSupport])
    }

    @Test func systemKindsAreNeverReturned() {
        let sizes: [CleanupKind: UInt64?] = [.caches: gb, .logs: gb, .trash: gb, .derivedData: gb]
        #expect(CleanupKind.visibleDeveloperKinds(sizes: sizes) == [.derivedData])
    }

    @Test func quickCleanTotalSumsOnlyTheQuickKinds() {
        let sizes: [CleanupKind: UInt64?] = [.caches: gb, .logs: gb / 10, .derivedData: 2 * gb, .nugetCache: 13 * gb]
        #expect(CleanupKind.quickCleanTotal(sizes: sizes) == 3 * gb + gb / 10)
    }

    @Test func nugetAloneGivesAQuickCleanTotalOfZero() {
        #expect(CleanupKind.quickCleanTotal(sizes: [.nugetCache: 13 * gb]) == 0)
        #expect(CleanupKind.quickCleanTotal(sizes: [.caches: nil, .logs: 0]) == 0)
        #expect(CleanupKind.quickCleanTotal(sizes: [:]) == 0)
    }

    // MARK: Mode démo (SL6 T7)

    @Test func demoDataShowsTheNugetRow() {
        let nuget = (DemoData.cleanupSizes[.nugetCache] ?? nil) ?? 0
        #expect(nuget > 0)
        #expect(CleanupKind.visibleDeveloperKinds(sizes: DemoData.cleanupSizes).contains(.nugetCache))
    }

    @Test func demoQuickCleanTotalStaysCachesLogsAndDerivedData() {
        let sizes = DemoData.cleanupSizes
        let expected = [CleanupKind.caches, .logs, .derivedData].reduce(UInt64(0)) { $0 + ((sizes[$1] ?? nil) ?? 0) }
        #expect(CleanupKind.quickCleanTotal(sizes: sizes) == expected)
        #expect(expected == (4_200 + 310 + 8_700) * 1_000_000)
    }
}
