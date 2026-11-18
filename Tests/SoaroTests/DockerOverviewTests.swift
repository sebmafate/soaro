import Foundation
import Testing
@testable import Soaro

/// SL13 T6 (R10, D2) : ce que l'écran montre d'un listage. Pur : aucun lanceur, aucun modèle.
@Suite struct DockerOverviewTests {
    func scan(usage: String = DockerReportTests.realUsage, untagged: [String] = []) throws -> DockerScan {
        let usageValue = try #require(DockerReport.parseUsage(Data(usage.utf8)))
        let list = try #require(DockerReport.parseUntaggedImages(Data(untagged.joined(separator: "\n").utf8)))
        return DockerScan(status: .ok, usage: usageValue, untagged: list)
    }

    static let removable = DockerReportTests.untagged(id: "aaaaaaaaaaaa", size: "397MB", containers: "0")
    static let inUse = DockerReportTests.untagged(id: "bbbbbbbbbbbb", size: "120MB", containers: "1")

    @Test func theBuildCacheAndTheUntaggedImagesAreTheOnlyThingsThatCanBeCleaned() throws {
        let overview = DockerOverview.make(try scan(untagged: [Self.removable]))
        #expect(overview.cleanables == [DockerCleanable(prune: .buildCache, size: 21_190_000_000, count: nil),
                                        DockerCleanable(prune: .untaggedImages, size: 397_000_000, count: 1)])
        #expect(overview.cleanableTotal == 21_587_000_000)
    }

    @Test func theBuildCacheRowShowsWhatDockerCallsReclaimable() throws {
        let overview = DockerOverview.make(try scan())
        #expect(overview.cleanables == [DockerCleanable(prune: .buildCache, size: 21_190_000_000, count: nil)])
    }

    @Test func anImageARunningContainerUsesIsNeverInTheRemovableList() throws {
        let overview = DockerOverview.make(try scan(untagged: [Self.inUse, Self.removable]))
        let images = try #require(overview.cleanables.first { $0.prune == .untaggedImages })
        #expect(images.count == 1 && images.size == 397_000_000, "seule l'image sans conteneur compte")
        let onlyInUse = DockerOverview.make(try scan(untagged: [Self.inUse]))
        #expect(onlyInUse.cleanables.map(\.prune) == [.buildCache], "pas de ligne d'images quand aucune n'est nettoyable")
    }

    @Test func sizesThatAreUnknownStayUnknownAndTheRowStaysRemovable() throws {
        let unknownSize = DockerReportTests.untagged(id: "cccccccccccc", size: "huge", containers: "0")
        let overview = DockerOverview.make(try scan(untagged: [Self.removable, unknownSize]))
        let images = try #require(overview.cleanables.first { $0.prune == .untaggedImages })
        #expect(images.count == 2)
        #expect(images.size == nil, "une somme avec un inconnu est inconnue, jamais fausse")
        #expect(overview.cleanableTotal == 21_190_000_000, "le total ne compte que les tailles connues")
    }

    @Test func aBuildCacheThatIsEmptyOrUnknownIsNotARowButUnknownIsSaid() throws {
        let empty = """
            {"Active":"0","Reclaimable":"0B","Size":"0B","TotalCount":"0","Type":"Build Cache"}
            {"Active":"4","Reclaimable":"580.7MB (28%)","Size":"2.042GB","TotalCount":"10","Type":"Images"}
            """
        let none = DockerOverview.make(try scan(usage: empty))
        #expect(none.cleanables.isEmpty && !none.buildCacheSizeUnknown)

        let unknown = """
            {"Active":"0","Reclaimable":"lots","Size":"22.46GB","TotalCount":"299","Type":"Build Cache"}
            """
        let overview = DockerOverview.make(try scan(usage: unknown))
        #expect(overview.cleanables.isEmpty, "une taille illisible n'est jamais cochée d'office")
        #expect(overview.buildCacheSizeUnknown)

        let missing = DockerOverview.make(try scan(usage: "{\"Active\":\"1\",\"Reclaimable\":\"0B\",\"Size\":\"1MB\",\"TotalCount\":\"1\",\"Type\":\"Images\"}"))
        #expect(missing.cleanables.isEmpty && missing.buildCacheSizeUnknown)
    }

    @Test func containersAndVolumesAreReadOnlyLinesWithDockersOwnFigures() throws {
        let overview = DockerOverview.make(try scan())
        #expect(overview.containers == DockerUsageLine(total: 11, active: 2, size: 114_700, reclaimable: 90_110))
        #expect(overview.volumes == DockerUsageLine(total: 23, active: 8, size: 915_600_000, reclaimable: 681_800_000))
        #expect(overview.cleanables.allSatisfy { $0.prune == .buildCache || $0.prune == .untaggedImages })
    }

    @Test func aMissingContainersOrVolumesLineIsAnEmptyLineNotACrash() throws {
        let only = "{\"Active\":\"0\",\"Reclaimable\":\"0B\",\"Size\":\"0B\",\"TotalCount\":\"0\",\"Type\":\"Build Cache\"}"
        let overview = DockerOverview.make(try scan(usage: only))
        #expect(overview.containers == DockerUsageLine(total: nil, active: nil, size: nil, reclaimable: nil))
        #expect(overview.volumes == DockerUsageLine(total: nil, active: nil, size: nil, reclaimable: nil))
    }

    @Test func otherUnusedImagesAreOneReadOnlyLineWithoutTheRemovableOnes() throws {
        // 10 images, 4 utilisées : 6 inutilisées, dont 1 sans étiquette à nettoyer : 5 autres. 580,7 Mo moins 397 Mo : 183,7 Mo.
        let overview = DockerOverview.make(try scan(untagged: [Self.removable]))
        #expect(overview.otherUnusedImages == DockerOtherImages(count: 5, size: 183_700_000))
        // Sans image à nettoyer : tout ce que Docker dit inutilisé.
        let plain = DockerOverview.make(try scan())
        #expect(plain.otherUnusedImages == DockerOtherImages(count: 6, size: 580_700_000))
    }

    @Test func otherUnusedImagesAreFlooredAtZeroAndHiddenWhenThereIsNone() throws {
        let none = """
            {"Active":"4","Reclaimable":"0B","Size":"2GB","TotalCount":"4","Type":"Images"}
            """
        #expect(DockerOverview.make(try scan(usage: none)).otherUnusedImages == nil)
        let tooBig = """
            {"Active":"0","Reclaimable":"100MB","Size":"2GB","TotalCount":"1","Type":"Images"}
            """
        let overview = DockerOverview.make(try scan(usage: tooBig, untagged: [Self.removable]))
        #expect(overview.otherUnusedImages == nil, "0 image, 0 octet : aucune ligne")
    }

    @Test func unknownImageFiguresGiveAnUnknownCountOrSize() throws {
        let partial = """
            {"Active":"x","Reclaimable":"?","Size":"2GB","TotalCount":"10","Type":"Images"}
            """
        #expect(DockerOverview.make(try scan(usage: partial)).otherUnusedImages == nil, "ni compte ni taille : pas de ligne")
        let sizeOnly = """
            {"Reclaimable":"580.7MB (28%)","Size":"2GB","Type":"Images"}
            """
        #expect(DockerOverview.make(try scan(usage: sizeOnly)).otherUnusedImages == DockerOtherImages(count: nil, size: 580_700_000))
    }

    @Test func aScanThatIsNotOkGivesAnEmptyOverview() {
        let overview = DockerOverview.make(DockerScan(status: .engineNotRunning))
        #expect(overview.cleanables.isEmpty && overview.otherUnusedImages == nil)
    }
}
