import Foundation
import Testing
@testable import Soaro

/// Section « Android system images » de `Soaro --scan` : mise en forme pure (anglais brut, non localisé) et
/// `Diagnostics.androidImageScan` dans un bac à sable, avec un environnement injecté et une mesure scriptée.
@Suite(.serialized) struct AndroidSystemImageReportTests {
    private let locale = Locale(identifier: "en_US")
    private let sdk = AndroidSDKLocation(path: "/Users/test/Library/Android/sdk", source: .defaultLocation)
    private let phonePath = "android-36/google_apis_playstore/arm64-v8a"
    private let oldPath = "android-34/default/arm64-v8a"

    private func device(_ name: String) -> AndroidDevice {
        AndroidDevice(name: name, displayName: "\(name) display", systemVersion: "36",
                      folder: URL(fileURLWithPath: "/Users/test/.android/avd/\(name).avd"), lastUsed: nil, lastUsedSource: nil)
    }

    private func image(_ path: String, _ usage: AndroidSystemImage.Usage) -> AndroidSystemImage {
        let key = AndroidSystemImageScanner.imageKey(imageSysdir: "system-images/\(path)")!
        return AndroidSystemImage(key: key, folder: URL(fileURLWithPath: "/Users/test/Library/Android/sdk/system-images/\(path)"), usage: usage)
    }

    private func scan(_ status: AndroidSystemImageListing.Status, images: [AndroidSystemImage] = [], sizes: [UInt64] = [],
                      skipped: Int = 0, reasons: [AndroidSystemImageIncompleteness.Reason] = [], sdk: AndroidSDKLocation? = nil) -> AndroidSystemImageScan {
        var table: [AndroidSystemImageKey: UInt64] = [:]
        for (image, size) in zip(images, sizes) { table[image.key] = size }
        return AndroidSystemImageScan(
            listing: AndroidSystemImageListing(status: status, images: images, sdk: sdk, skippedCount: skipped,
                                               incompleteness: AndroidSystemImageIncompleteness(reasons: reasons)),
            sizes: table)
    }

    private func lines(_ scan: AndroidSystemImageScan) -> [String] { AndroidSystemImageReport.lines(scan: scan, locale: locale) }
    private func size(_ bytes: UInt64) -> String { Format.fileBytes(bytes, locale: locale) }

    // MARK: États

    @Test func noSdk() {
        #expect(lines(scan(.sdkNotFound)) == ["== Android system images", "Android SDK not found"])
    }

    @Test func anSdkOutsideTheHome() {
        #expect(lines(scan(.sdkOutsideHome, sdk: sdk))
                == ["== Android system images", "system images not read: the SDK is outside the home folder", "SDK source: default"])
    }

    @Test func unreadable() {
        #expect(lines(scan(.unreadable, sdk: sdk))
                == ["== Android system images", "could not read the Android system images", "SDK source: default"])
    }

    @Test func noImage() {
        #expect(lines(scan(.ok, sdk: sdk)) == ["== Android system images", "no system image", "SDK source: default"])
        #expect(lines(scan(.ok, skipped: 2, sdk: sdk)).contains("2 folders skipped (not an android-<N> image, outside the home or no package file)"))
    }

    // MARK: Lignes d'images

    @Test func aUsedImageNamesItsAvds() {
        let images = [image(phonePath, .usedBy([device("Test_Phone_A"), device("Test_Tablet_B")]))]
        #expect(lines(scan(.ok, images: images, sizes: [3_200_000_000], sdk: sdk)) == [
            "== Android system images",
            "\(size(3_200_000_000))  \(phonePath)  API 36  used by Test_Phone_A, Test_Tablet_B",
            "note: read-only; Soaro does not remove system images",
            "SDK source: default"])
    }

    @Test func anUnusedImage() {
        let output = lines(scan(.ok, images: [image(oldPath, .notUsed)], sizes: [2_000_000_000], sdk: sdk))
        #expect(output[1] == "\(size(2_000_000_000))  \(oldPath)  API 34  not used by any listed AVD")
    }

    @Test func aCannotTellImageAndEachNote() {
        let reasons: [AndroidSystemImageIncompleteness.Reason] = [.customLocation(["ANDROID_AVD_HOME"]), .avdFolderUnreadable,
                                                                  .skippedRegistrations(2), .unknownImage(3)]
        let output = lines(scan(.ok, images: [image(oldPath, .cannotTell)], sizes: [1_000_000_000], reasons: reasons, sdk: sdk))
        #expect(output == [
            "== Android system images",
            "\(size(1_000_000_000))  \(oldPath)  API 34  cannot tell (see the notes)",
            "note: ANDROID_AVD_HOME is set: virtual devices kept there are not read, so an image may be in use",
            "note: the AVD folder could not be read",
            "note: 2 registrations could not be read",
            "note: 3 AVDs have no readable system image",
            "note: read-only; Soaro does not remove system images",
            "SDK source: default"])
    }

    @Test func singularNotes() {
        let output = lines(scan(.ok, images: [image(oldPath, .cannotTell)], sizes: [1], skipped: 1,
                                reasons: [.skippedRegistrations(1), .unknownImage(1)], sdk: sdk))
        #expect(output.contains("note: 1 registration could not be read"))
        #expect(output.contains("note: 1 AVD has no readable system image"))
        #expect(output.contains("1 folder skipped (not an android-<N> image, outside the home or no package file)"))
    }

    @Test func twoVariablesAreNamedInOneNoteInOrder() {
        let output = lines(scan(.ok, images: [image(oldPath, .cannotTell)], sizes: [1],
                                reasons: [.customLocation(["ANDROID_AVD_HOME", "ANDROID_EMULATOR_HOME"])], sdk: sdk))
        #expect(output.contains("note: ANDROID_AVD_HOME, ANDROID_EMULATOR_HOME are set: virtual devices kept there are not read, so an image may be in use"))
    }

    @Test func noNoteAndNoSkippedLineWhenTheStatusIsNotOk() {
        let reasons: [AndroidSystemImageIncompleteness.Reason] = [.customLocation(["ANDROID_AVD_HOME"]), .avdFolderUnreadable,
                                                                  .skippedRegistrations(2), .unknownImage(1)]
        #expect(lines(scan(.unreadable, skipped: 3, reasons: reasons, sdk: sdk))
                == ["== Android system images", "could not read the Android system images", "SDK source: default"])
        #expect(lines(scan(.sdkOutsideHome, skipped: 3, reasons: reasons, sdk: sdk))
                == ["== Android system images", "system images not read: the SDK is outside the home folder", "SDK source: default"])
        #expect(lines(scan(.sdkNotFound, skipped: 3, reasons: reasons)) == ["== Android system images", "Android SDK not found"])
    }

    @Test func theNewVariablesAreNamedLikeTheOthers() {
        let output = lines(scan(.ok, images: [image(oldPath, .cannotTell)], sizes: [1],
                                reasons: [.customLocation(["ANDROID_SDK_HOME", "ANDROID_PREFS_ROOT"])], sdk: sdk))
        #expect(output.contains("note: ANDROID_SDK_HOME, ANDROID_PREFS_ROOT are set: virtual devices kept there are not read, so an image may be in use"))
    }

    @Test func theSkippedLineAppearsOnlyAboveZero() {
        let none = lines(scan(.ok, images: [image(oldPath, .notUsed)], sizes: [1], skipped: 0, sdk: sdk))
        #expect(!none.contains { $0.contains("skipped") })
        let some = lines(scan(.ok, images: [image(oldPath, .notUsed)], sizes: [1], skipped: 3, sdk: sdk))
        #expect(some.contains("3 folders skipped (not an android-<N> image, outside the home or no package file)"))
    }

    @Test func anUnmeasuredImageShowsAQuestionMark() {
        let output = lines(scan(.ok, images: [image(oldPath, .notUsed)], sizes: [], sdk: sdk))
        #expect(output[1] == "?  \(oldPath)  API 34  not used by any listed AVD")
    }

    @Test func noLineContainsAPathOrAnEnvironmentValue() {
        let images = [image(phonePath, .usedBy([device("Test_Phone_A")])), image(oldPath, .cannotTell)]
        let reasons: [AndroidSystemImageIncompleteness.Reason] = [.customLocation(["ANDROID_AVD_HOME"]), .skippedRegistrations(1)]
        for status in [AndroidSystemImageListing.Status.ok, .sdkNotFound, .sdkOutsideHome, .unreadable] {
            for line in lines(scan(status, images: images, sizes: [1, 2], skipped: 1, reasons: reasons, sdk: sdk)) {
                #expect(!line.contains("/Users"), "\(line)")
            }
        }
    }

    // MARK: Diagnostics.androidImageScan (bac à sable)

    @Test func androidImageScanMeasuresExactlyTheImageFolders() throws {
        let box = try Sandbox(insideHome: true)
        try box.write("Library/Android/sdk/system-images/android-36/google_apis_playstore/arm64-v8a/source.properties", "x\n")
        try box.write("Library/Android/sdk/system-images/android-34/default/arm64-v8a/package.xml", "x\n")
        try box.write("Library/Android/sdk/system-images/android-34/default/arm64-v8a/system.img", "x\n")
        try box.write(".android/avd/Test_Phone_A.avd/config.ini", "image.sysdir.1=system-images/android-36/google_apis_playstore/arm64-v8a/\n")
        try box.write(".android/avd/Test_Phone_A.ini", "path.rel=avd/Test_Phone_A.avd\n")
        let measured = MeasureLog()
        let scan = Diagnostics.androidImageScan(environment: [:], home: box.root, measure: { url in
            measured.add(url.resolvingSymlinksInPath().standardizedFileURL.path)
            return url.lastPathComponent == "arm64-v8a" ? 1_000 : 0
        })
        let expected = ["Library/Android/sdk/system-images/android-36/google_apis_playstore/arm64-v8a",
                        "Library/Android/sdk/system-images/android-34/default/arm64-v8a"]
            .map { box.root.appendingPathComponent($0).resolvingSymlinksInPath().standardizedFileURL.path }
        #expect(measured.names == expected)
        #expect(scan.listing.status == .ok)
        #expect(scan.sizes.count == 2)
        let output = AndroidSystemImageReport.lines(scan: scan, locale: locale)
        #expect(output.contains("\(size(1_000))  android-36/google_apis_playstore/arm64-v8a  API 36  used by Test_Phone_A"))
        #expect(output.contains("\(size(1_000))  android-34/default/arm64-v8a  API 34  not used by any listed AVD"))
        #expect(output.allSatisfy { !$0.contains(box.root.path) })
    }

    @Test func anAliasRegistrationPrintsNoRegistrationNote() throws {
        let box = try Sandbox(insideHome: true)
        try box.write("Library/Android/sdk/system-images/android-36/google_apis_playstore/arm64-v8a/source.properties", "x\n")
        try box.write("Library/Android/sdk/system-images/android-34/default/arm64-v8a/source.properties", "x\n")
        try box.write(".android/avd/Test_Phone_A.avd/config.ini", "image.sysdir.1=system-images/android-36/google_apis_playstore/arm64-v8a/\n")
        try box.write(".android/avd/Test_Phone_A.ini", "path.rel=avd/Test_Phone_A.avd\n")
        try box.write(".android/avd/Test_Phone_B.ini", "path.rel=avd/Test_Phone_A.avd\n")
        let scan = Diagnostics.androidImageScan(environment: [:], home: box.root, measure: { _ in 1_000 })
        let output = AndroidSystemImageReport.lines(scan: scan, locale: locale)
        #expect(!output.contains { $0.contains("could not be read") }, "\(output)")
        #expect(output.contains("\(size(1_000))  android-34/default/arm64-v8a  API 34  not used by any listed AVD"))
    }

    @Test func androidImageScanWithoutAnSdkMeasuresNothing() throws {
        let box = try Sandbox(insideHome: true)
        let measured = MeasureLog()
        let scan = Diagnostics.androidImageScan(environment: [:], home: box.root, measure: { _ in measured.add("x"); return 1 })
        #expect(scan.listing.status == .sdkNotFound)
        #expect(measured.names.isEmpty)
    }
}

/// Journal des dossiers mesurés (la mesure s'exécute dans la même tâche : pas de concurrence ici).
private final class MeasureLog: @unchecked Sendable {
    private(set) var names: [String] = []
    func add(_ name: String) { names.append(name) }
}
