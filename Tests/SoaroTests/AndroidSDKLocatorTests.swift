import Foundation
import Testing
@testable import Soaro

/// Recherche du SDK Android (R18) : fonction pure, aucun lancement, jamais le PATH.
/// L'environnement est TOUJOURS injecté (`[:]` ou valeurs écrites à la main) : jamais celui de la machine (CI : `ANDROID_HOME`).
@Suite struct AndroidSDKLocatorTests {
    private let home = URL(fileURLWithPath: "/Users/test")
    private let defaultSDK = "/Users/test/Library/Android/sdk"

    private func locate(_ environment: [String: String], existing: Set<String>) -> AndroidSDKLocation? {
        ToolLocator.androidSDK(environment: environment, home: home, isDirectory: { existing.contains($0) })
    }

    @Test func sdkRootVariableToAnExistingFolderIsTheSDK() {
        let found = locate(["ANDROID_SDK_ROOT": "/opt/sdk-a"], existing: ["/opt/sdk-a"])
        #expect(found == AndroidSDKLocation(path: "/opt/sdk-a", source: .androidSDKRoot))
        #expect(found?.source.rawValue == "ANDROID_SDK_ROOT")
    }

    @Test func sdkRootWinsOverAndroidHome() {
        let found = locate(["ANDROID_SDK_ROOT": "/opt/sdk-a", "ANDROID_HOME": "/opt/sdk-b"], existing: ["/opt/sdk-a", "/opt/sdk-b"])
        #expect(found == AndroidSDKLocation(path: "/opt/sdk-a", source: .androidSDKRoot))
    }

    @Test func anEmptySdkRootLetsAndroidHomeDecide() {
        let found = locate(["ANDROID_SDK_ROOT": "", "ANDROID_HOME": "/opt/sdk-b"], existing: ["/opt/sdk-b"])
        #expect(found == AndroidSDKLocation(path: "/opt/sdk-b", source: .androidHome))
        #expect(found?.source.rawValue == "ANDROID_HOME")
    }

    @Test func androidHomeAloneIsUsed() {
        #expect(locate(["ANDROID_HOME": "/opt/sdk-b"], existing: ["/opt/sdk-b"])?.source == .androidHome)
    }

    @Test func aMissingFolderInSdkRootGivesNothingEvenWhenTheDefaultExists() {
        #expect(locate(["ANDROID_SDK_ROOT": "/opt/missing"], existing: [defaultSDK]) == nil)
    }

    @Test func aMissingFolderInSdkRootGivesNothingEvenWhenAndroidHomeIsFine() {
        #expect(locate(["ANDROID_SDK_ROOT": "/opt/missing", "ANDROID_HOME": "/opt/sdk-b"], existing: ["/opt/sdk-b"]) == nil)
    }

    @Test func aRelativeValueGivesNothing() {
        #expect(locate(["ANDROID_SDK_ROOT": "sdk"], existing: ["sdk", defaultSDK]) == nil)
        #expect(locate(["ANDROID_HOME": "./sdk"], existing: ["./sdk", defaultSDK]) == nil)
    }

    @Test func aFileInsteadOfAFolderGivesNothing() throws {
        let box = try Sandbox()
        let file = try box.file("not-a-folder")
        let found = ToolLocator.androidSDK(environment: ["ANDROID_SDK_ROOT": file.path], home: box.root)
        #expect(found == nil)
    }

    @Test func aRealFolderIsFoundWithTheDefaultCheck() throws {
        let box = try Sandbox()
        try box.dir("sdk")
        let path = box.root.appendingPathComponent("sdk").path
        #expect(ToolLocator.androidSDK(environment: ["ANDROID_HOME": path], home: box.root)?.path == path)
    }

    @Test func theDefaultFolderIsUsedWhenNothingIsSet() {
        #expect(locate([:], existing: [defaultSDK]) == AndroidSDKLocation(path: defaultSDK, source: .defaultLocation))
        #expect(locate(["ANDROID_SDK_ROOT": "", "ANDROID_HOME": ""], existing: [defaultSDK])?.source == .defaultLocation)
    }

    @Test func nothingSetAndNoDefaultGivesNothing() {
        #expect(locate([:], existing: []) == nil)
    }

    @Test func theLookupReadsNothingElseFromTheEnvironment() {
        // Le PATH n'est jamais lu : même avec un PATH qui désigne un SDK, seul le défaut compte.
        #expect(locate(["PATH": "/opt/sdk-a"], existing: ["/opt/sdk-a"]) == nil)
    }

    @Test func processListCandidatesAreExactlyPsByAbsolutePath() {
        #expect(ToolLocator.processListCandidates == ["/bin/ps"])
    }
}
