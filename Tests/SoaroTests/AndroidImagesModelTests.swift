import Foundation
import Testing
@testable import Soaro

/// `measure` des images : note chaque dossier demandé (chemin complet), rend la taille prévue (clé : les trois derniers composants
/// `android-36/google_apis/arm64-v8a`), et peut s'arrêter à chaque dossier d'IMAGE pour que le test observe l'état entre deux mesures.
/// Les autres dossiers (appareils iOS et Android) rendent `otherSize`, sans jamais s'arrêter.
final class ImageMeasure: @unchecked Sendable {
    private let lock = NSLock()
    private var sizes: [String: UInt64]
    private var recorded: [URL] = []
    private let gated: Bool
    let otherSize: UInt64
    let started = AsyncSignal()
    let release = DispatchSemaphore(value: 0)

    init(_ sizes: [String: UInt64] = [:], gated: Bool = false, otherSize: UInt64 = 500_000_000) {
        self.sizes = sizes
        self.gated = gated
        self.otherSize = otherSize
    }

    static func isImageFolder(_ url: URL) -> Bool { url.path.contains("/system-images/") }

    static func key(_ url: URL) -> String { url.pathComponents.suffix(3).joined(separator: "/") }

    var imageCalls: [String] { lock.lock(); defer { lock.unlock() }; return recorded.filter(Self.isImageFolder).map(Self.key) }
    var allCalls: [URL] { lock.lock(); defer { lock.unlock() }; return recorded }

    func measure(_ folder: URL) -> UInt64 {
        lock.lock(); recorded.append(folder); lock.unlock()
        guard Self.isImageFolder(folder) else { return otherSize }
        if gated { started.signal(); release.wait() }
        lock.lock(); defer { lock.unlock() }
        return sizes[Self.key(folder)] ?? 0
    }
}

/// Le groupe « images système » du modèle de l'outil (SL12a, T6) : indépendant de Delete, sans sélection, tailles une à une.
/// Dossier personnel de bac à sable `.soaro-test-` (jamais le vrai SDK), faux lanceur, environnement injecté, `measure` écrit à la main.
@MainActor
@Suite(.serialized) struct AndroidImagesModelTests {
    static let u1 = "00000000-0000-4000-8000-000000000001"
    static let listArgs = ["simctl", "list", "devices", "-j"]
    static let psArguments = ["-axww", "-o", "command="]
    static let path36 = "android-36/google_apis_playstore/arm64-v8a"
    static let path34 = "android-34/default/arm64-v8a"
    let now = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!
    let present = SimulatorToolDetection(devicesFolderExists: true, simctlPath: "/fake/simctl")
    let absent = SimulatorToolDetection(devicesFolderExists: false, simctlPath: nil)

    /// Dossier personnel de bac à sable : le SDK par défaut avec ces images, et ces AVD (nom, image système).
    func home(images: [String], avds: [(name: String, display: String, image: String?)] = [], sdk: Bool = true) throws -> Sandbox {
        let box = try Sandbox(insideHome: true)
        if sdk { try box.dir("Library/Android/sdk") }
        for image in images { try box.write("Library/Android/sdk/system-images/\(image)/source.properties", "Pkg.Revision=1\n") }
        for avd in avds {
            try box.dir(".android/avd/\(avd.name).avd")
            try box.write(".android/avd/\(avd.name).ini", "path.rel=avd/\(avd.name).avd\n")
            var config = "avd.ini.displayname=\(avd.display)\n"
            if let image = avd.image { config += "image.sysdir.1=system-images/\(image)/\n" }
            try box.write(".android/avd/\(avd.name).avd/config.ini", config)
        }
        return box
    }

    let phone = (name: "Test_Phone_A", display: "Test Phone A", image: Optional(path36))

    func runner(ios: [String] = []) -> FakeCommandRunner {
        let fake = FakeCommandRunner()
        fake.script(.finished(stdout: SimulatorsModelTests.listJSON(ios)), executable: "/usr/bin/xcrun", arguments: Self.listArgs)
        fake.script(.finished(stdout: ""), executable: "/bin/ps", arguments: Self.psArguments)
        return fake
    }

    /// GARDE-FOU : le dossier personnel du modèle est un bac à sable, sinon le test échoue AVANT tout scan.
    func model(_ runner: CommandRunner, home box: Sandbox, detection: SimulatorToolDetection? = nil, environment: [String: String] = [:],
               measure: ImageMeasure, gate: SimulatorDeletionGate? = nil, confirm: RecordingConfirm? = nil,
               removeFile: @escaping (URL) throws -> Void = { _ in }) throws -> SimulatorsModel {
        try #require(box.root.path.contains(".soaro-test-"), "le modèle doit utiliser un dossier personnel de bac à sable")
        let detection = detection ?? absent
        return SimulatorsModel(runner: runner, detect: { detection },
                               locateTool: { $0 == ToolLocator.processListCandidates ? "/bin/ps" : "/usr/bin/xcrun" },
                               environment: environment, home: box.root, now: { self.now },
                               measure: { measure.measure($0) }, removeFile: removeFile, demo: false,
                               confirm: confirm?.handler ?? { _, _, _, _ in false }, deletionGate: gate ?? SimulatorDeletionGate(),
                               notify: { _ in })
    }

    func run(_ m: SimulatorsModel) async {
        m.scan()
        await m.scanTask?.value
    }

    // MARK: Liste et tailles

    @Test func imagesAreListedAfterTheScanWithSizesAppliedOneByOneThenSortedBySize() async throws {
        let box = try home(images: [Self.path36, Self.path34], avds: [phone])
        let measure = ImageMeasure([Self.path36: 2_000_000_000, Self.path34: 9_000_000_000], gated: true)
        let m = try model(runner(), home: box, measure: measure)
        m.scan()
        await measure.started.wait()                         // la première mesure d'image est en cours
        #expect(m.imagesPhase == .listed)
        #expect(m.imageRows.map(\.key.path) == [Self.path36, Self.path34], "ordre du listage pendant la mesure")
        #expect(m.imageRows.allSatisfy { m.size(of: $0) == nil }, "« … » tant qu'une taille manque")
        measure.release.signal()
        await measure.started.wait()                         // la seconde est en cours : la première est arrivée
        #expect(m.size(of: m.imageRows[0]) == 2_000_000_000)
        #expect(m.size(of: m.imageRows[1]) == nil)
        #expect(m.imageRows.map(\.key.path) == [Self.path36, Self.path34], "toujours l'ordre du listage")
        measure.release.signal()
        await m.scanTask?.value
        #expect(m.imageRows.map(\.key.path) == [Self.path34, Self.path36], "par taille décroissante à la dernière")
        #expect(m.imageRows.map { m.size(of: $0) } == [9_000_000_000, 2_000_000_000])
        #expect(measure.imageCalls == [Self.path36, Self.path34])
    }

    @Test func equalSizesKeepTheListingOrderAndSmallImagesAreNeverHidden() async throws {
        let box = try home(images: [Self.path36, Self.path34])
        let m = try model(runner(), home: box, measure: ImageMeasure([Self.path36: 1_000, Self.path34: 1_000]))
        await run(m)
        #expect(m.imageRows.map(\.key.path) == [Self.path36, Self.path34])
        #expect(m.imageRows.allSatisfy { m.size(of: $0) == 1_000 })
    }

    @Test func eachRowCarriesItsUsage() async throws {
        let box = try home(images: [Self.path36, Self.path34], avds: [phone])
        let m = try model(runner(), home: box, measure: ImageMeasure())
        await run(m)
        let usages = Dictionary(uniqueKeysWithValues: m.imageRows.map { ($0.key.path, $0.usage) })
        if case .usedBy(let devices)? = usages[Self.path36] { #expect(devices.map(\.name) == ["Test_Phone_A"]) } else { Issue.record("36 utilisée") }
        #expect(usages[Self.path34] == .notUsed)
        #expect(!m.imagesUsageIncomplete)
    }

    @Test func anInjectedCustomLocationVariableMakesUsageIncomplete() async throws {
        let box = try home(images: [Self.path34])
        let m = try model(runner(), home: box, environment: ["ANDROID_AVD_HOME": box.root.path + "/elsewhere"], measure: ImageMeasure())
        await run(m)
        #expect(m.imageRows.map(\.usage) == [.cannotTell])
        #expect(m.imagesUsageIncomplete)
    }

    // MARK: Caché, échec

    @Test func noSdkHidesTheImagesAndNoImageFolderIsMeasured() async throws {
        let box = try home(images: [Self.path36], sdk: false)
        try FileManager.default.removeItem(at: box.root.appendingPathComponent("Library"))     // pas de SDK du tout
        let measure = ImageMeasure()
        let m = try model(runner(), home: box, measure: measure)
        await run(m)
        #expect(m.imagesPhase == .hidden)
        #expect(m.imageRows.isEmpty)
        #expect(measure.imageCalls.isEmpty)
    }

    @Test func noImageHidesTheGroup() async throws {
        let box = try home(images: [])
        let m = try model(runner(), home: box, measure: ImageMeasure())
        await run(m)
        #expect(m.imagesPhase == .hidden)
    }

    @Test func anSdkOutsideTheHomeHidesTheGroupAndReadsNothing() async throws {
        let box = try home(images: [], sdk: false)
        let outside = try Sandbox(insideHome: false)
        try outside.write("system-images/\(Self.path36)/source.properties", "x\n")
        let measure = ImageMeasure()
        let m = try model(runner(), home: box, environment: ["ANDROID_SDK_ROOT": outside.root.path], measure: measure)
        await run(m)
        #expect(m.imagesPhase == .hidden)
        #expect(measure.imageCalls.isEmpty)
    }

    @Test func aSystemImagesFileFailsTheGroupWhileTheOtherGroupsStayUsable() async throws {
        let box = try home(images: [], avds: [phone])
        try box.file("Library/Android/sdk/system-images")
        let m = try model(runner(ios: [Self.u1]), home: box, detection: present, measure: ImageMeasure())
        await run(m)
        #expect(m.imagesPhase == .failed(.couldNotRead))
        #expect(m.imagesMessage == "Could not read the Android system images.")
        #expect(m.phase == .listed)
        #expect(m.androidPhase == .listed)
        #expect(m.rows.count == 1 && m.androidRows.count == 1)
    }

    // MARK: Les autres groupes ne changent pas

    @Test func theRunnerCallsAreExactlyThoseOfTheOtherGroups() async throws {
        let box = try home(images: [Self.path36, Self.path34], avds: [phone])
        let fake = runner(ios: [Self.u1])
        let m = try model(fake, home: box, detection: present, measure: ImageMeasure())
        await run(m)
        #expect(m.imageRows.count == 2)
        #expect(fake.calls.map(\.executable) == ["/usr/bin/xcrun", "/bin/ps"])
        #expect(fake.calls.map(\.arguments) == [Self.listArgs, Self.psArguments])
    }

    @Test func imageMeasuringNeverBlocksDeleteNorEntersTheTotals() async throws {
        let box = try home(images: [Self.path36, Self.path34], avds: [phone])
        let measure = ImageMeasure([Self.path36: 7_000_000_000, Self.path34: 3_000_000_000], gated: true)
        let m = try model(runner(), home: box, measure: measure)
        m.scan()
        await measure.started.wait()                         // les tailles Android sont arrivées, les images sont en cours de mesure
        #expect(m.imagesPhase == .listed)
        #expect(!m.isMeasuring, "la mesure des images n'entre pas dans isMeasuring")
        let row = try #require(m.androidRows.first)
        m.toggle(row)
        #expect(m.canDelete, "une ligne Android cochée : Delete reste utilisable pendant la mesure des images")
        #expect(m.selectedCount == 1)
        #expect(m.listedCount == 1)
        #expect(m.measuredSizeTotal == measure.otherSize)
        #expect(m.hiddenSmallCount == 0)
        #expect(!m.showsNothingToSuggest || m.listedCount > 0)
        measure.release.signal()
        measure.release.signal()
        await m.scanTask?.value
        #expect(m.selectedSize == measure.otherSize, "les images ne comptent pas dans la taille cochée")
        #expect(m.measuredSizeTotal == measure.otherSize, "ni dans le total")
        #expect(m.listedCount == 1)
    }

    @Test func noImageIsSelectedAndThereIsNoImageGroupForSelectAll() async throws {
        let box = try home(images: [Self.path36], avds: [phone])
        let m = try model(runner(), home: box, measure: ImageMeasure([Self.path36: 5_000_000_000]))
        await run(m)
        #expect(m.selectedCount == 0)
        #expect(m.selectedSize == 0)
        #expect(!m.canDelete)
        // Le seul `Group` de « Select all » : iOS et Android (le compilateur refuserait un cas `images`).
        #expect([SimulatorsModel.Group.ios, .android].count == 2)
    }

    // MARK: Suppression Android seule, nouveau scan

    @Test func anAndroidOnlyDeletionNeverTouchesAnImageFolderAndTheRescanReloadsTheImages() async throws {
        let box = try home(images: [Self.path36, Self.path34], avds: [phone])
        let measure = ImageMeasure([Self.path36: 2_000_000_000, Self.path34: 1_000_000_000])
        let confirm = RecordingConfirm(answer: true)
        let removed = RemovedPaths()
        let m = try model(runner(), home: box, measure: measure, confirm: confirm, removeFile: { removed.add($0) })
        await run(m)
        #expect(measure.imageCalls.count == 2)
        let row = try #require(m.androidRows.first)
        m.toggle(row)
        #expect(m.canDelete)

        m.deleteSelected()
        await m.deleteTask?.value

        #expect(confirm.asks.count == 1)
        #expect(!removed.paths.isEmpty, "l'appareil Android a bien été visé")
        #expect(removed.paths.allSatisfy { !$0.contains("/system-images/") }, "aucun dossier d'image n'a été passé à removeFile")
        #expect(measure.imageCalls.count == 4, "les images sont relues par le nouveau scan")
        #expect(m.imagesPhase == .listed)
        #expect(m.imageRows.count == 2)
        #expect(FileManager.default.fileExists(atPath: box.root.appendingPathComponent("Library/Android/sdk/system-images/\(Self.path36)").path))
    }

    @Test func theConfirmationNeverMentionsAnImage() async throws {
        let box = try home(images: [Self.path36], avds: [phone])
        let confirm = RecordingConfirm(answer: false)
        let m = try model(runner(), home: box, measure: ImageMeasure(), confirm: confirm)
        await run(m)
        m.toggle(try #require(m.androidRows.first))
        m.deleteSelected()
        let ask = try #require(confirm.asks.first)
        #expect(ask.title == "Delete the selected devices? (1)")
        #expect(!ask.message.contains("system image") && !ask.message.contains(Self.path36))
    }

    // MARK: Retour

    @Test func backDuringImageMeasuringClearsEverythingAndStopsMeasuring() async throws {
        let box = try home(images: [Self.path36, Self.path34], avds: [phone])
        let measure = ImageMeasure([Self.path36: 2_000_000_000, Self.path34: 1_000_000_000], gated: true)
        let m = try model(runner(), home: box, measure: measure)
        m.scan()
        await measure.started.wait()
        #expect(m.imagesPhase == .listed)
        m.cancel()
        #expect(m.imagesPhase == .notScanned)
        #expect(m.phase == .notScanned && m.androidPhase == .notScanned)
        #expect(m.imageRows.isEmpty)
        #expect(!m.imagesUsageIncomplete)
        measure.release.signal()
        await m.scanTask?.value
        #expect(measure.imageCalls == [Self.path36], "aucune autre mesure après Retour")
        #expect(m.imagesPhase == .notScanned)
        #expect(m.imageRows.isEmpty)
    }

    @Test func aNewScanClearsTheOldImageRowsFirst() async throws {
        let box = try home(images: [Self.path36])
        let measure = ImageMeasure([Self.path36: 5])
        let m = try model(runner(), home: box, measure: measure)
        await run(m)
        #expect(m.imageRows.count == 1)
        try FileManager.default.removeItem(at: box.root.appendingPathComponent("Library/Android/sdk/system-images"))
        await run(m)
        #expect(m.imagesPhase == .hidden)
        #expect(m.imageRows.isEmpty)
        #expect(m.size(of: AndroidSystemImage(key: AndroidSystemImageScanner.imageKey(imageSysdir: "system-images/\(Self.path36)")!,
                                              folder: box.root, usage: .notUsed)) == nil)
    }
}

/// Chemins passés à `removeFile` (noté, jamais supprimé : le test ne supprime rien).
final class RemovedPaths: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return recorded }
    func add(_ url: URL) { lock.lock(); recorded.append(url.path); lock.unlock() }
}
