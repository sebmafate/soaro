import Foundation
import Testing
@testable import Soaro

/// Lecture de `<sdk>/system-images` (SL12a, T2) : LECTURE SEULE, dans le bac à sable `.soaro-test-<uuid>`
/// (jamais le vrai SDK ni le vrai dossier personnel).
@Suite(.serialized) struct AndroidSystemImageListingTests {
    /// Le dossier d'un SDK de test : `<bac>/Library/Android/sdk`.
    private func sdk(_ box: Sandbox) -> AndroidSDKLocation {
        AndroidSDKLocation(path: box.root.appendingPathComponent("Library/Android/sdk").path, source: .defaultLocation)
    }

    /// Crée `<sdk>/system-images/<relative>` avec un fichier repère ; renvoie le dossier de l'image.
    @discardableResult
    private func makeImage(_ box: Sandbox, _ relative: String, marker: String? = "source.properties") throws -> URL {
        let folder = "Library/Android/sdk/system-images/\(relative)"
        try box.dir(folder)
        if let marker { try box.write("\(folder)/\(marker)", "Pkg.Revision=1\n") }
        return box.root.appendingPathComponent(folder)
    }

    private func list(_ box: Sandbox) -> AndroidSystemImageFolderListing {
        AndroidSystemImageScanner.listImages(sdk: sdk(box), home: box.root)
    }

    private func realPath(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }

    /// Chaque entrée sous la racine avec sa date de modification et sa taille, pour comparer avant et après.
    private func snapshot(_ root: URL) -> [String] {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(atPath: root.path) else { return [] }
        return enumerator.compactMap { $0 as? String }.sorted().map { relative in
            let attributes = try? manager.attributesOfItem(atPath: root.appendingPathComponent(relative).path)
            return "\(relative)|\(attributes?[.modificationDate] ?? "")|\(attributes?[.size] ?? "")"
        }
    }

    // MARK: Cas nominal

    @Test func listsTwoImagesInTheRightOrderWithKeysAndFolders() throws {
        let box = try Sandbox(insideHome: true)
        let a = try makeImage(box, "android-34/default/arm64-v8a")
        let b = try makeImage(box, "android-36/google_apis_playstore/arm64-v8a")
        let listing = list(box)
        #expect(listing.status == .ok)
        #expect(listing.skippedCount == 0)
        #expect(listing.images.map(\.key.path) == ["android-36/google_apis_playstore/arm64-v8a", "android-34/default/arm64-v8a"])
        #expect(listing.images.map { realPath($0.folder) } == [realPath(b), realPath(a)])
        #expect(listing.images.map(\.key.version) == ["36", "34"])
    }

    @Test func versionsAreSortedNumericallyDescendingThenVariantThenAbi() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-35/google_apis/arm64-v8a")
        try makeImage(box, "android-9/default/arm64-v8a")
        try makeImage(box, "android-36/google_apis/x86_64")
        try makeImage(box, "android-36.1/google_apis/arm64-v8a")
        try makeImage(box, "android-36/google_apis/arm64-v8a")
        try makeImage(box, "android-36/default/arm64-v8a")
        #expect(list(box).images.map(\.key.path) == [
            "android-36.1/google_apis/arm64-v8a", "android-36/default/arm64-v8a", "android-36/google_apis/arm64-v8a",
            "android-36/google_apis/x86_64", "android-35/google_apis/arm64-v8a", "android-9/default/arm64-v8a"])
    }

    @Test func aPackageXmlAloneIsEnoughToBeListed() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis/arm64-v8a", marker: "package.xml")
        #expect(list(box).images.count == 1)
        #expect(list(box).skippedCount == 0)
    }

    @Test func aFolderWithoutAMarkerIsSkippedAndCounted() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis/arm64-v8a", marker: nil)
        let listing = list(box)
        #expect(listing.images.isEmpty)
        #expect(listing.skippedCount == 1)
    }

    @Test func aMarkerThatIsAFolderDoesNotCount() throws {
        let box = try Sandbox(insideHome: true)
        let folder = try makeImage(box, "android-36/google_apis/arm64-v8a", marker: nil)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("source.properties"), withIntermediateDirectories: true)
        #expect(list(box).images.isEmpty)
        #expect(list(box).skippedCount == 1)
    }

    @Test func aPreviewFolderIsSkippedAndCounted() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-Baklava/google_apis/arm64-v8a")
        let listing = list(box)
        #expect(listing.images.isEmpty)
        #expect(listing.skippedCount == 1)
    }

    @Test func anInvalidVariantOrAbiNameIsSkippedAndCounted() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google apis/arm64-v8a")
        try makeImage(box, "android-36/google_apis/arm 64")
        let listing = list(box)
        #expect(listing.images.isEmpty)
        #expect(listing.skippedCount == 2)
    }

    @Test func aDSStoreFileAtEachLevelIsIgnoredAndNotCounted() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis/arm64-v8a")
        try box.write("Library/Android/sdk/system-images/.DS_Store", "x")
        try box.write("Library/Android/sdk/system-images/android-36/.DS_Store", "x")
        try box.write("Library/Android/sdk/system-images/android-36/google_apis/.DS_Store", "x")
        let listing = list(box)
        #expect(listing.images.count == 1)
        #expect(listing.skippedCount == 0)
    }

    // MARK: Dossier absent, illisible

    @Test func aMissingSystemImagesFolderIsOkAndEmpty() throws {
        let box = try Sandbox(insideHome: true)
        try box.dir("Library/Android/sdk")
        let listing = list(box)
        #expect(listing.status == .ok)
        #expect(listing.images.isEmpty)
        #expect(listing.skippedCount == 0)
    }

    @Test func aSystemImagesPathThatIsAFileIsUnreadable() throws {
        let box = try Sandbox(insideHome: true)
        try box.file("Library/Android/sdk/system-images")
        #expect(list(box).status == .unreadable)
    }

    @Test func aSystemImagesFolderThatCannotBeListedIsUnreadable() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis/arm64-v8a")
        let folder = box.root.appendingPathComponent("Library/Android/sdk/system-images").path
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder) }
        #expect(list(box).status == .unreadable)
    }

    @Test func aLevelThatCannotBeListedIsSkippedAndCounted() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis/arm64-v8a")
        try makeImage(box, "android-35/google_apis/arm64-v8a")
        let level = box.root.appendingPathComponent("Library/Android/sdk/system-images/android-35").path
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: level)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: level) }
        let listing = list(box)
        #expect(listing.status == .ok)
        #expect(listing.images.map(\.key.version) == ["36"])
        #expect(listing.skippedCount == 1)
    }

    // MARK: Liens symboliques et périmètre

    @Test func anAbiFolderThatIsASymlinkOutsideTheHomeIsSkipped() throws {
        let box = try Sandbox(insideHome: true)
        let outside = try Sandbox()
        try outside.write("real/source.properties", "Pkg.Revision=1\n")
        try box.dir("Library/Android/sdk/system-images/android-36/google_apis")
        try FileManager.default.createSymbolicLink(
            atPath: box.root.appendingPathComponent("Library/Android/sdk/system-images/android-36/google_apis/arm64-v8a").path,
            withDestinationPath: outside.root.appendingPathComponent("real").path)
        let listing = list(box)
        #expect(listing.images.isEmpty)
        #expect(listing.skippedCount == 1)
    }

    @Test func aSymlinkToAnotherImageInsideTheSandboxGivesOneRow() throws {
        let box = try Sandbox(insideHome: true)
        let real = try makeImage(box, "android-36/google_apis/arm64-v8a")
        try FileManager.default.createSymbolicLink(
            atPath: box.root.appendingPathComponent("Library/Android/sdk/system-images/android-36/google_apis/x86_64").path,
            withDestinationPath: real.path)
        let listing = list(box)
        #expect(listing.images.count == 1)
        #expect(listing.skippedCount == 1)
        #expect(listing.images.map(\.key.abi) == ["arm64-v8a"], "le premier par nom, de façon déterministe")
    }

    @Test func anSdkOutsideTheHomeIsNotRead() throws {
        let box = try Sandbox(insideHome: true)
        let outside = try Sandbox(insideHome: false)
        try outside.write("system-images/android-36/google_apis/arm64-v8a/source.properties", "x\n")
        let listing = AndroidSystemImageScanner.listImages(sdk: AndroidSDKLocation(path: outside.root.path, source: .androidSDKRoot),
                                                           home: box.root)
        #expect(listing.status == .sdkOutsideHome)
        #expect(listing.images.isEmpty)
        #expect(listing.skippedCount == 0)
    }

    @Test func anSdkEqualToTheHomeIsNotStrictlyInside() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis/arm64-v8a")
        let listing = AndroidSystemImageScanner.listImages(sdk: AndroidSDKLocation(path: box.root.path, source: .androidSDKRoot), home: box.root)
        #expect(listing.status == .sdkOutsideHome)
    }

    @Test func anSdkThatIsASymlinkOutsideTheHomeIsNotRead() throws {
        let box = try Sandbox(insideHome: true)
        let outside = try Sandbox(insideHome: false)
        try outside.write("system-images/android-36/google_apis/arm64-v8a/source.properties", "x\n")
        try box.dir("Library/Android")
        try FileManager.default.createSymbolicLink(atPath: box.root.appendingPathComponent("Library/Android/sdk").path,
                                                   withDestinationPath: outside.root.path)
        #expect(list(box).status == .sdkOutsideHome)
    }

    @Test func aFourthLevelIsNotListedAsAnImage() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis/arm64-v8a/extra", marker: "source.properties")
        let listing = list(box)
        #expect(listing.images.isEmpty, "le dossier ABI n'a pas de fichier repère : seul le quatrième niveau en a un")
        #expect(listing.skippedCount == 1)
    }

    // MARK: Lecture seule

    @Test func nothingInTheSandboxChanges() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis/arm64-v8a")
        try makeImage(box, "android-35/default/arm64-v8a", marker: nil)
        try makeImage(box, "android-Baklava/google_apis/arm64-v8a")
        try box.write("Library/Android/sdk/system-images/.DS_Store", "x")
        let before = snapshot(box.root)
        _ = list(box)
        #expect(snapshot(box.root) == before)
        #expect(!before.isEmpty)
    }
}
