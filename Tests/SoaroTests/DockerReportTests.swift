import Foundation
import Testing
@testable import Soaro

/// SL13 T2 (R10, R6) : lecture défensive de la sortie de `docker`. Les entrées sont des sorties RÉELLES de `docker system df` et de
/// `docker images` (Docker Desktop 29.7.2, 2026-11-18), anonymisées : aucun nom de conteneur ni d'image du poste de l'auteur.
@Suite struct DockerReportTests {
    // MARK: Entrées

    /// `docker system df --format '{{json .}}'`, tel que rendu (seule la ligne du cache de build est celle de SPK-002 avant le nettoyage).
    static let realUsage = """
        {"Active":"4","Reclaimable":"580.7MB (28%)","Size":"2.042GB","TotalCount":"10","Type":"Images"}
        {"Active":"2","Reclaimable":"90.11kB (78%)","Size":"114.7kB","TotalCount":"11","Type":"Containers"}
        {"Active":"8","Reclaimable":"681.8MB (74%)","Size":"915.6MB","TotalCount":"23","Type":"Local Volumes"}
        {"Active":"0","Reclaimable":"21.19GB (94%)","Size":"22.46GB","TotalCount":"299","Type":"Build Cache"}

        """

    /// Une ligne de `docker images -f dangling=true --format '{{json .}}'`. La forme est celle des lignes réelles de `docker images`
    /// (aucune image sans étiquette n'existait ce jour-là) ; nom et étiquette valent `<none>`, comme Docker les écrit.
    static func untagged(id: String = "aaaaaaaaaaaa", size: String? = "397MB", containers: String? = "0") -> String {
        var fields = ["\"CreatedAt\":\"2026-11-10 09:00:00 +0100 CET\"", "\"CreatedSince\":\"1 week ago\"", "\"Digest\":\"\\u003cnone\\u003e\"",
                      "\"ID\":\"\(id)\"", "\"Repository\":\"\\u003cnone\\u003e\"", "\"SharedSize\":\"N/A\"", "\"Tag\":\"\\u003cnone\\u003e\"",
                      "\"UniqueSize\":\"N/A\""]
        if let size { fields.append("\"Size\":\"\(size)\"") }
        if let containers { fields.append("\"Containers\":\"\(containers)\"") }
        return "{" + fields.joined(separator: ",") + "}"
    }

    static func data(_ text: String) -> Data { Data(text.utf8) }

    // MARK: Tailles (décimales, comme Docker)

    @Test func sizesAreDecimalAndExactToTheUnitDockerPrints() {
        #expect(DockerSize.parse("0B") == 0)
        #expect(DockerSize.parse("512B") == 512)
        #expect(DockerSize.parse("114.7kB") == 114_700)
        #expect(DockerSize.parse("90.11kB") == 90_110)
        #expect(DockerSize.parse("915.6MB") == 915_600_000)
        #expect(DockerSize.parse("2.042GB") == 2_042_000_000)
        #expect(DockerSize.parse("22.46GB") == 22_460_000_000)
        #expect(DockerSize.parse("1.5TB") == 1_500_000_000_000)
        #expect(DockerSize.parse(" 3GB ") == 3_000_000_000)
        #expect(DockerSize.parse("12KB") == 12_000, "écriture majuscule tolérée")
    }

    @Test func aSizeFollowedByAPercentageTakesTheSizeOnly() {
        #expect(DockerSize.parse("580.7MB (28%)") == 580_700_000)
        #expect(DockerSize.parse("0B") == 0)
    }

    @Test func anythingElseIsUnknownNeverAGuess() {
        for text in ["", " ", "N/A", "abc", "GB", "12", "12 parsecs", "-5MB", "1e3GB", "NaNGB", "1.2.3MB", "5 MB x", "(28%)", "99999999999999999999GB"] {
            #expect(DockerSize.parse(text) == nil, "\(text.debugDescription)")
        }
    }

    // MARK: `docker system df`

    @Test func theRealUsageOutputGivesFourLines() throws {
        let usage = try #require(DockerReport.parseUsage(Self.data(Self.realUsage)))
        #expect(usage.images == DockerUsageLine(total: 10, active: 4, size: 2_042_000_000, reclaimable: 580_700_000))
        #expect(usage.containers == DockerUsageLine(total: 11, active: 2, size: 114_700, reclaimable: 90_110))
        #expect(usage.volumes == DockerUsageLine(total: 23, active: 8, size: 915_600_000, reclaimable: 681_800_000))
        #expect(usage.buildCache == DockerUsageLine(total: 299, active: 0, size: 22_460_000_000, reclaimable: 21_190_000_000))
    }

    @Test func theEmptyBuildCacheOfTheRealRecordingIsZeroNotUnknown() throws {
        let text = """
            {"Active":"0","Reclaimable":"0B","Size":"0B","TotalCount":"0","Type":"Build Cache"}
            """
        let usage = try #require(DockerReport.parseUsage(Self.data(text)))
        #expect(usage.buildCache == DockerUsageLine(total: 0, active: 0, size: 0, reclaimable: 0))
        #expect(usage.images == nil, "une ligne absente est inconnue")
    }

    @Test func aMissingOrMalformedFieldIsUnknownAndTheOthersAreKept() throws {
        let text = """
            {"Active":"x","Reclaimable":"?","Size":"2.042GB","TotalCount":"10","Type":"Images"}
            {"Size":"114.7kB","Type":"Containers"}
            {"Active":4,"Reclaimable":"1MB","Size":"1MB","TotalCount":7,"Type":"Local Volumes"}
            {"Active":"-1","Reclaimable":"12","Size":"","TotalCount":"1.5","Type":"Build Cache"}
            """
        let usage = try #require(DockerReport.parseUsage(Self.data(text)))
        #expect(usage.images == DockerUsageLine(total: 10, active: nil, size: 2_042_000_000, reclaimable: nil))
        #expect(usage.containers == DockerUsageLine(total: nil, active: nil, size: 114_700, reclaimable: nil))
        #expect(usage.volumes == DockerUsageLine(total: 7, active: 4, size: 1_000_000, reclaimable: 1_000_000), "nombres JSON acceptés pour les comptes")
        #expect(usage.buildCache == DockerUsageLine(total: nil, active: nil, size: nil, reclaimable: nil))
    }

    @Test func unknownTypesUnknownFieldsAndBlankOrBrokenLinesAreIgnored() throws {
        let text = """

            not json at all
            {"Type":"Something New","Size":"1GB"}
            {"Active":"1","Extra":"field","Future":{"a":1},"Reclaimable":"0B","Size":"1GB","TotalCount":"1","Type":"Images"}
            [1,2,3]
            {"Type":"Images","Size":"9GB"}
            """
        let usage = try #require(DockerReport.parseUsage(Self.data(text)))
        #expect(usage.images == DockerUsageLine(total: 1, active: 1, size: 1_000_000_000, reclaimable: 0), "la première ligne d'un type gagne")
        #expect(usage.containers == nil && usage.volumes == nil && usage.buildCache == nil)
    }

    @Test func unreadableUsageIsNilNeverACrashNorAnEmptyUsage() {
        #expect(DockerReport.parseUsage(Data()) == nil)
        #expect(DockerReport.parseUsage(Self.data("\n\n")) == nil)
        #expect(DockerReport.parseUsage(Self.data("Cannot connect to the Docker daemon")) == nil)
        #expect(DockerReport.parseUsage(Self.data("{\"Type\":\"Something New\"}")) == nil)
        #expect(DockerReport.parseUsage(Data([0xFF, 0xFE, 0x00, 0x7B])) == nil)
        // Sortie coupée au milieu d'une ligne : la ligne entière est perdue, les lignes complètes restent.
        let cut = String(Self.realUsage.dropLast(40))
        let usage = DockerReport.parseUsage(Self.data(cut))
        #expect(usage?.images != nil && usage?.buildCache == nil)
    }

    @Test func aSingleJSONArrayOfLinesIsReadToo() throws {
        let text = "[{\"Active\":\"0\",\"Reclaimable\":\"0B\",\"Size\":\"0B\",\"TotalCount\":\"0\",\"Type\":\"Build Cache\"}]"
        let usage = try #require(DockerReport.parseUsage(Self.data(text)))
        #expect(usage.buildCache?.size == 0)
    }

    // MARK: Images sans étiquette

    @Test func anEmptyListMeansNoUntaggedImage() {
        #expect(DockerReport.parseUntaggedImages(Data()) == [])
        #expect(DockerReport.parseUntaggedImages(Self.data("\n")) == [])
    }

    @Test func untaggedImagesAreReadWithSizeAndContainerCount() throws {
        let text = [Self.untagged(id: "aaaaaaaaaaaa", size: "397MB", containers: "0"),
                    Self.untagged(id: "bbbbbbbbbbbb", size: "12.5kB", containers: "2")].joined(separator: "\n")
        let images = try #require(DockerReport.parseUntaggedImages(Self.data(text)))
        #expect(images == [DockerUntaggedImage(id: "aaaaaaaaaaaa", size: 397_000_000, containerCount: 0),
                           DockerUntaggedImage(id: "bbbbbbbbbbbb", size: 12_500, containerCount: 2)])
        #expect(images[0].isRemovable)
        #expect(!images[1].isRemovable, "une image qu'un conteneur utilise n'est jamais dans la liste à nettoyer")
    }

    @Test func anImageWhoseUseCannotBeToldIsNeverRemovable() throws {
        let text = [Self.untagged(id: "cccccccccccc", containers: nil), Self.untagged(id: "dddddddddddd", containers: "N/A"),
                    Self.untagged(id: "eeeeeeeeeeee", containers: "-1")].joined(separator: "\n")
        let images = try #require(DockerReport.parseUntaggedImages(Self.data(text)))
        #expect(images.count == 3)
        #expect(images.allSatisfy { $0.containerCount == nil && !$0.isRemovable })
    }

    @Test func aMissingOrBadSizeIsUnknownAndAnEntryWithoutAValidIDIsDropped() throws {
        let text = [Self.untagged(id: "aaaaaaaaaaaa", size: nil), Self.untagged(id: "bbbbbbbbbbbb", size: "huge"),
                    Self.untagged(id: ""), Self.untagged(id: "not an id!"), Self.untagged(id: "sha256:" + String(repeating: "a", count: 64)),
                    "{\"Repository\":\"<none>\"}", "garbage"].joined(separator: "\n")
        let images = try #require(DockerReport.parseUntaggedImages(Self.data(text)))
        #expect(images.map(\.id) == ["aaaaaaaaaaaa", "bbbbbbbbbbbb", String(repeating: "a", count: 64)])
        #expect(images[0].size == nil && images[1].size == nil && images[2].size == 397_000_000)
    }

    @Test func theSameImageListedTwiceCountsOnce() throws {
        let text = [Self.untagged(id: "aaaaaaaaaaaa"), Self.untagged(id: "aaaaaaaaaaaa")].joined(separator: "\n")
        #expect(DockerReport.parseUntaggedImages(Self.data(text))?.count == 1)
    }

    @Test func untaggedOutputThatIsNotAListIsNil() {
        #expect(DockerReport.parseUntaggedImages(Self.data("Cannot connect to the Docker daemon")) == nil)
        #expect(DockerReport.parseUntaggedImages(Self.data("{\"x\":1}")) == nil, "aucune ligne exploitable dans une sortie non vide")
        #expect(DockerReport.parseUntaggedImages(Data([0xFF, 0xFE])) == nil)
    }

    // MARK: Chiffre annoncé par un nettoyage

    @Test func theTotalOfAPruneIsTheLastTotalLine() {
        let cache = "ID1\nID2\nID3\nTotal:\t22.46GB\n"
        #expect(DockerReport.parsePruneTotal(Self.data(cache)) == 22_460_000_000)
        let images = "Deleted Images:\nuntagged: x\ndeleted: sha256:abc\n\nTotal reclaimed space: 397MB\n"
        #expect(DockerReport.parsePruneTotal(Self.data(images)) == 397_000_000)
        #expect(DockerReport.parsePruneTotal(Self.data("Total reclaimed space: 0B\n")) == 0)
        #expect(DockerReport.parsePruneTotal(Self.data("Total: 1GB\nTotal: 2GB")) == 2_000_000_000)
    }

    @Test func aPruneOutputWithoutAReadableTotalIsUnknown() {
        for text in ["", "ID1\nID2\n", "Total:\n", "Total: lots\n", "Total reclaimed space: -1B", "total: 1GB"] {
            #expect(DockerReport.parsePruneTotal(Self.data(text)) == nil, "\(text.debugDescription)")
        }
        #expect(DockerReport.parsePruneTotal(Data([0xFF, 0xFE])) == nil)
    }
}
