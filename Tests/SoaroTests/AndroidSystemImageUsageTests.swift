import Foundation
import Testing
@testable import Soaro

/// Qui utilise chaque image système (SL12a, T3) : le rattachement PUR (appareils faits à la main) et le listage complet
/// (SDK, AVD, images, environnement) dans le bac à sable `.soaro-test-<uuid>`, avec un environnement TOUJOURS injecté.
@Suite(.serialized) struct AndroidSystemImageUsageTests {
    private let phoneImage = "system-images/android-36/google_apis_playstore/arm64-v8a/"
    private let tabletImage = "system-images/android-34/default/arm64-v8a/"

    // MARK: Fabriques

    private func device(_ name: String, display: String? = nil, image: String?) -> AndroidDevice {
        AndroidDevice(name: name, displayName: display ?? name, systemVersion: nil,
                      folder: URL(fileURLWithPath: "/Users/test/.android/avd/\(name).avd"), lastUsed: nil, lastUsedSource: nil,
                      imageSysdir: image)
    }

    private func folder(_ path: String) -> AndroidSystemImageFolder {
        let key = AndroidSystemImageScanner.imageKey(imageSysdir: "system-images/\(path)")!
        return AndroidSystemImageFolder(key: key, folder: URL(fileURLWithPath: "/Users/test/Library/Android/sdk/system-images/\(path)"))
    }

    private func makeAVD(_ box: Sandbox, name: String, display: String? = nil, system: String? = "system-images/android-36/google_apis_playstore/arm64-v8a/",
                         registration: String? = nil) throws {
        try box.dir(".android/avd/\(name).avd")
        let ini = registration ?? "avd.ini.encoding=UTF-8\npath=\(box.root.path)/.android/avd/\(name).avd\npath.rel=avd/\(name).avd\ntarget=android-36\n"
        try box.write(".android/avd/\(name).ini", ini)
        var config = "AvdId=\(name)\n"
        if let display { config += "avd.ini.displayname=\(display)\n" }
        if let system { config += "image.sysdir.1=\(system)\n" }
        try box.write(".android/avd/\(name).avd/config.ini", config)
    }

    private func makeImage(_ box: Sandbox, _ relative: String) throws {
        try box.write("Library/Android/sdk/system-images/\(relative)/source.properties", "Pkg.Revision=1\n")
    }

    private func list(_ box: Sandbox, environment: [String: String] = [:]) -> AndroidSystemImageListing {
        AndroidSystemImageScanner.list(environment: environment, home: box.root)
    }

    private func usage(_ listing: AndroidSystemImageListing, _ path: String) -> AndroidSystemImage.Usage? {
        listing.images.first { $0.key.path == path }?.usage
    }

    private let none = AndroidSystemImageIncompleteness(reasons: [])

    // MARK: Rattachement pur

    @Test func twoAvdsOnOneImageAreBothUsersInDisplayOrder() {
        let b = device("Test_Tablet_B", display: "Test Tablet B", image: phoneImage)
        let a = device("Test_Phone_A", display: "Test Phone A", image: phoneImage)
        let rows = AndroidSystemImageScanner.usage(images: [folder("android-36/google_apis_playstore/arm64-v8a")], devices: [b, a], incompleteness: none)
        #expect(rows.map(\.usage) == [.usedBy([a, b])])
    }

    @Test func oneUsedAndOneUnusedWhenComplete() {
        let a = device("Test_Phone_A", image: phoneImage)
        let rows = AndroidSystemImageScanner.usage(
            images: [folder("android-36/google_apis_playstore/arm64-v8a"), folder("android-34/default/arm64-v8a")], devices: [a], incompleteness: none)
        #expect(rows.map(\.usage) == [.usedBy([a]), .notUsed])
    }

    @Test func anIncompleteListingMakesTheUnusedImageCannotTellButNotTheUsedOne() {
        let a = device("Test_Phone_A", image: phoneImage)
        let reasons = AndroidSystemImageIncompleteness(reasons: [.avdFolderUnreadable])
        let rows = AndroidSystemImageScanner.usage(
            images: [folder("android-36/google_apis_playstore/arm64-v8a"), folder("android-34/default/arm64-v8a")], devices: [a], incompleteness: reasons)
        #expect(rows.map(\.usage) == [.usedBy([a]), .cannotTell])
    }

    @Test func aKeyInAnotherCaseStillMatches() {
        let a = device("Test_Phone_A", image: "system-images/android-36/Google_APIs_PlayStore/ARM64-v8a/")
        let rows = AndroidSystemImageScanner.usage(images: [folder("android-36/google_apis_playstore/arm64-v8a")], devices: [a], incompleteness: none)
        #expect(rows.map(\.usage) == [.usedBy([a])])
    }

    @Test func aDeviceWithAnUnreadableImageUsesNothing() {
        let a = device("Test_Phone_A", image: nil)
        let rows = AndroidSystemImageScanner.usage(images: [folder("android-36/google_apis_playstore/arm64-v8a")], devices: [a], incompleteness: none)
        #expect(rows.map(\.usage) == [.notUsed])
    }

    @Test func theImageOrderIsKept() {
        let images = [folder("android-36/google_apis/arm64-v8a"), folder("android-35/google_apis/arm64-v8a"), folder("android-34/default/arm64-v8a")]
        let rows = AndroidSystemImageScanner.usage(images: images, devices: [], incompleteness: none)
        #expect(rows.map(\.key) == images.map(\.key))
        #expect(rows.map(\.folder) == images.map(\.folder))
    }

    // MARK: Listage complet (bac à sable)

    @Test func twoAvdsOnOneImageThroughTheFullListing() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis_playstore/arm64-v8a")
        try makeAVD(box, name: "Test_Tablet_B", display: "Test Tablet B")
        try makeAVD(box, name: "Test_Phone_A", display: "Test Phone A")
        let listing = list(box)
        #expect(listing.status == .ok)
        guard case .usedBy(let devices)? = usage(listing, "android-36/google_apis_playstore/arm64-v8a") else {
            Issue.record("l'image devrait être utilisée"); return
        }
        #expect(devices.map(\.displayName) == ["Test Phone A", "Test Tablet B"])
        #expect(listing.incompleteness.reasons.isEmpty)
        #expect(listing.sdk?.source == .defaultLocation)
    }

    @Test func oneImageUsedOneNotAndTheListingIsComplete() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis_playstore/arm64-v8a")
        try makeImage(box, "android-34/default/arm64-v8a")
        try makeAVD(box, name: "Test_Phone_A")
        let listing = list(box)
        #expect(listing.images.map(\.key.path) == ["android-36/google_apis_playstore/arm64-v8a", "android-34/default/arm64-v8a"])
        #expect(listing.images.map { if case .usedBy = $0.usage { "used" } else { "\($0.usage)" } } == ["used", "notUsed"])
    }

    @Test func aCustomLocationVariableMakesTheUnusedImageCannotTell() throws {
        for variable in ["ANDROID_AVD_HOME", "ANDROID_USER_HOME", "ANDROID_EMULATOR_HOME"] {
            let box = try Sandbox(insideHome: true)
            try makeImage(box, "android-36/google_apis_playstore/arm64-v8a")
            try makeImage(box, "android-34/default/arm64-v8a")
            try makeAVD(box, name: "Test_Phone_A")
            let listing = list(box, environment: [variable: "/Users/test/elsewhere"])
            #expect(listing.incompleteness.reasons == [.customLocation([variable])], "\(variable)")
            #expect(usage(listing, "android-34/default/arm64-v8a") == .cannotTell, "\(variable)")
            if case .usedBy? = usage(listing, "android-36/google_apis_playstore/arm64-v8a") {} else { Issue.record("\(variable) : l'image utilisée reste utilisée") }
        }
    }

    @Test func allThreeVariablesAreNamedInOrder() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-34/default/arm64-v8a")
        let environment = ["ANDROID_EMULATOR_HOME": "/Users/test/c", "ANDROID_AVD_HOME": "/Users/test/a", "ANDROID_USER_HOME": "/Users/test/b"]
        let listing = list(box, environment: environment)
        #expect(listing.incompleteness.reasons == [.customLocation(["ANDROID_AVD_HOME", "ANDROID_USER_HOME", "ANDROID_EMULATOR_HOME"])])
    }

    @Test func aVariableSetToAnEmptyStringDoesNotCount() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-34/default/arm64-v8a")
        let listing = list(box, environment: ["ANDROID_AVD_HOME": "", "ANDROID_USER_HOME": ""])
        #expect(listing.incompleteness.reasons.isEmpty)
        #expect(usage(listing, "android-34/default/arm64-v8a") == .notUsed)
    }

    @Test func aRegistrationOutsideTheHomeGivesCannotTellWithTheSkippedCount() throws {
        let box = try Sandbox(insideHome: true)
        let outside = try Sandbox()
        try outside.dir("Test_Phone_A.avd")
        try makeImage(box, "android-36/google_apis_playstore/arm64-v8a")
        try makeAVD(box, name: "Test_Phone_A", registration: "path=\(outside.root.path)/Test_Phone_A.avd\n")
        let listing = list(box)
        #expect(listing.incompleteness.reasons == [.skippedRegistrations(1)])
        #expect(usage(listing, "android-36/google_apis_playstore/arm64-v8a") == .cannotTell)
    }

    @Test func anAliasRegistrationIsNotAnIncompleteness() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis_playstore/arm64-v8a")
        try makeImage(box, "android-34/default/arm64-v8a")
        try makeAVD(box, name: "Test_Phone_A")
        try box.write(".android/avd/Test_Phone_B.ini", "path.rel=avd/Test_Phone_A.avd\n")       // second `.ini` du même dossier
        let listing = list(box)
        #expect(listing.incompleteness.reasons.isEmpty, "un alias n'est pas une inscription illisible")
        #expect(usage(listing, "android-34/default/arm64-v8a") == .notUsed, "et l'image inutilisée n'est pas « cannot tell »")
    }

    @Test func twoRegistrationsOfOneAvdGiveOneUserWithItsImageAndNoUnknownImage() throws {
        // Casse si `withAliases` perd `imageSysdir` : l'appareil n'aurait plus d'image (« unknown image ») et l'image ne serait pas utilisée.
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis_playstore/arm64-v8a")
        try makeAVD(box, name: "Test_Phone_A", display: "Test Phone A")
        try box.write(".android/avd/Test_Phone_B.ini", "path.rel=avd/Test_Phone_A.avd\n")
        let listing = list(box)
        guard case .usedBy(let devices)? = usage(listing, "android-36/google_apis_playstore/arm64-v8a") else {
            Issue.record("l'image devrait être utilisée"); return
        }
        #expect(devices.map(\.name) == ["Test_Phone_A"], "l'appareil une seule fois")
        #expect(devices.first?.aliases == ["Test_Phone_B"])
        #expect(!listing.incompleteness.reasons.contains(.unknownImage(1)))
        #expect(listing.incompleteness.reasons.isEmpty)
    }

    @Test func anAvdWithoutAnImageSysdirGivesUnknownImage() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis_playstore/arm64-v8a")
        try makeAVD(box, name: "Test_Phone_A", system: nil)
        let listing = list(box)
        #expect(listing.incompleteness.reasons == [.unknownImage(1)])
        #expect(usage(listing, "android-36/google_apis_playstore/arm64-v8a") == .cannotTell)
    }

    @Test func anUnreadableAvdFolderMakesEveryImageCannotTell() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis_playstore/arm64-v8a")
        try makeImage(box, "android-34/default/arm64-v8a")
        try box.file(".android/avd")
        let listing = list(box)
        #expect(listing.status == .ok)
        #expect(listing.incompleteness.reasons == [.avdFolderUnreadable])
        #expect(listing.images.map(\.usage) == [.cannotTell, .cannotTell])
    }

    @Test func reasonsComeInTheDocumentedOrder() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-34/default/arm64-v8a")
        try makeAVD(box, name: "Test_Phone_A", system: nil)
        try box.write(".android/avd/Gone.ini", "path.rel=avd/Gone.avd\n")
        let listing = list(box, environment: ["ANDROID_USER_HOME": "/Users/test/b"])
        #expect(listing.incompleteness.reasons == [.customLocation(["ANDROID_USER_HOME"]), .skippedRegistrations(1), .unknownImage(1)])
    }

    @Test func anAvdUnderOneHundredMegabytesStillCountsAsAUser() throws {
        // `listAVDs` ne mesure rien : tout AVD listé compte, quelle que soit sa taille (ici quelques octets).
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis_playstore/arm64-v8a")
        try makeAVD(box, name: "Test_Phone_A")
        if case .usedBy(let devices)? = usage(list(box), "android-36/google_apis_playstore/arm64-v8a") {
            #expect(devices.map(\.name) == ["Test_Phone_A"])
        } else {
            Issue.record("l'appareil de quelques octets doit compter")
        }
    }

    @Test func aKeyInADifferentCaseStillMatchesOnDisk() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis_playstore/arm64-v8a")
        try makeAVD(box, name: "Test_Phone_A", system: "system-images/android-36/Google_APIs_PlayStore/ARM64-v8a/")
        if case .usedBy? = usage(list(box), "android-36/google_apis_playstore/arm64-v8a") {} else { Issue.record("doit être utilisée") }
    }

    // MARK: Deux noms pour un même dossier (liens symboliques)

    @Test func anImageUsedByEitherKeyOfALinkedFolderIsUsedByBothDevicesOnOneRow() {
        let real = AndroidSystemImageScanner.imageKey(imageSysdir: "system-images/android-36/google_apis/arm64-v8a")!
        let alias = AndroidSystemImageScanner.imageKey(imageSysdir: "system-images/android-35/google_apis/arm64-v8a")!
        let folder = AndroidSystemImageFolder(key: real, folder: URL(fileURLWithPath: "/Users/test/Library/Android/sdk/system-images/android-36/google_apis/arm64-v8a"),
                                              keys: [alias, real])
        let a = device("Test_Phone_A", image: "system-images/android-35/google_apis/arm64-v8a/")
        let b = device("Test_Tablet_B", image: "system-images/android-36/google_apis/arm64-v8a/")
        let rows = AndroidSystemImageScanner.usage(images: [folder], devices: [b, a], incompleteness: none)
        #expect(rows.count == 1)
        #expect(rows.first?.key == real)
        #expect(rows.map(\.usage) == [.usedBy([a, b])])
        let onlyAlias = AndroidSystemImageScanner.usage(images: [folder], devices: [a], incompleteness: none)
        #expect(onlyAlias.map(\.usage) == [.usedBy([a])], "le dossier est utilisé même quand seul le nom du lien est écrit dans config.ini")
    }

    @Test(arguments: ["android-35", "android-37"])
    func aDeviceUsingTheLinkNameKeepsTheRealFolderUsedOnDisk(linkName: String) throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis_playstore/arm64-v8a")
        try FileManager.default.createSymbolicLink(
            atPath: box.root.appendingPathComponent("Library/Android/sdk/system-images/\(linkName)").path,
            withDestinationPath: box.root.appendingPathComponent("Library/Android/sdk/system-images/android-36").path)
        try makeAVD(box, name: "Test_Phone_A", system: "system-images/\(linkName)/google_apis_playstore/arm64-v8a/")
        try makeAVD(box, name: "Test_Tablet_B", system: "system-images/android-36/google_apis_playstore/arm64-v8a/")
        let listing = list(box)
        #expect(listing.images.count == 1)
        guard case .usedBy(let devices)? = listing.images.first?.usage else { Issue.record("l'image doit être utilisée"); return }
        #expect(devices.map(\.name) == ["Test_Phone_A", "Test_Tablet_B"])
        #expect(listing.images.first?.key.path == "android-36/google_apis_playstore/arm64-v8a")
    }

    // MARK: SDK

    @Test func noSdkGivesSdkNotFoundEvenWithImagesAndAvdsInTheSandbox() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis_playstore/arm64-v8a")
        try makeAVD(box, name: "Test_Phone_A")
        // L'environnement `[:]` ET le dossier par défaut présent : le SDK est trouvé, donc on le retire pour isoler le cas.
        try FileManager.default.removeItem(at: box.root.appendingPathComponent("Library"))
        let listing = list(box)
        #expect(listing.status == .sdkNotFound)
        #expect(listing.images.isEmpty)
        #expect(listing.sdk == nil)
    }

    @Test func aMissingSdkRootHasNoFallbackToTheDefaultFolder() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis_playstore/arm64-v8a")
        let listing = list(box, environment: ["ANDROID_SDK_ROOT": box.root.appendingPathComponent("missing").path])
        #expect(listing.status == .sdkNotFound)
    }

    @Test func theSdkRootVariableNamesTheSdk() throws {
        let box = try Sandbox(insideHome: true)
        try box.write("MySdk/system-images/android-35/google_apis/arm64-v8a/package.xml", "x\n")
        let listing = list(box, environment: ["ANDROID_SDK_ROOT": box.root.appendingPathComponent("MySdk").path])
        #expect(listing.status == .ok)
        #expect(listing.images.map(\.key.path) == ["android-35/google_apis/arm64-v8a"])
        #expect(listing.sdk?.source == .androidSDKRoot)
    }

    @Test func anSdkOutsideTheHomeIsReturnedAsIs() throws {
        let box = try Sandbox(insideHome: true)
        let outside = try Sandbox(insideHome: false)
        try outside.write("system-images/android-35/google_apis/arm64-v8a/package.xml", "x\n")
        try makeAVD(box, name: "Test_Phone_A")
        let listing = list(box, environment: ["ANDROID_HOME": outside.root.path])
        #expect(listing.status == .sdkOutsideHome)
        #expect(listing.images.isEmpty)
    }

    @Test func aSystemImagesPathThatIsAFileIsUnreadable() throws {
        let box = try Sandbox(insideHome: true)
        try box.file("Library/Android/sdk/system-images")
        #expect(list(box).status == .unreadable)
    }

    @Test func noImageIsOkAndEmptyWithoutReadingTheAvdFolder() throws {
        let box = try Sandbox(insideHome: true)
        try box.dir("Library/Android/sdk/system-images")
        try box.file(".android/avd")     // illisible : ne doit pas apparaître, car il n'est pas lu
        let listing = list(box)
        #expect(listing.status == .ok)
        #expect(listing.images.isEmpty)
        #expect(listing.incompleteness.reasons.isEmpty)
    }

    @Test func skippedFoldersAreCarriedByTheListing() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis_playstore/arm64-v8a")
        try makeImage(box, "android-Baklava/google_apis/arm64-v8a")
        #expect(list(box).skippedCount == 1)
    }

    @Test func anAvdKeptInAnotherFolderIsNeverRead() throws {
        let box = try Sandbox(insideHome: true)
        try makeImage(box, "android-36/google_apis_playstore/arm64-v8a")
        try box.write("elsewhere/Test_Phone_A.ini", "path=\(box.root.path)/elsewhere/Test_Phone_A.avd\n")
        try box.write("elsewhere/Test_Phone_A.avd/config.ini", "image.sysdir.1=\(phoneImage)\n")
        let listing = list(box, environment: ["ANDROID_AVD_HOME": box.root.appendingPathComponent("elsewhere").path])
        #expect(usage(listing, "android-36/google_apis_playstore/arm64-v8a") == .cannotTell, "jamais « utilisée » : le dossier n'est pas lu")
    }

    // MARK: Pas de lanceur, pas de `ps`

    @Test func listTakesNoRunner() {
        // La signature EST le test : seulement l'environnement et le dossier personnel.
        let function: ([String: String], URL) -> AndroidSystemImageListing = AndroidSystemImageScanner.list(environment:home:)
        _ = function
    }

    @Test func theScannerSourceNeverMentionsPs() throws {
        let url = RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Cleanup/AndroidSystemImageScanner.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("runningAVDNames"))
        #expect(!text.contains("psPath"))
        #expect(text.range(of: "\\bps\\b", options: .regularExpression) == nil)
    }
}
