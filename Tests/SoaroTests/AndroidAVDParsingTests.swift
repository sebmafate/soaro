import Foundation
import Testing
@testable import Soaro

/// Lecture des fichiers d'un appareil virtuel Android : fonctions PURES, aucun accès aux fichiers (R16).
/// Fixtures anonymisées : `/Users/test`, noms inventés.
@Suite struct AndroidAVDParsingTests {
    private func ini(_ text: String) -> [String: String]? { AndroidEmulatorScanner.parseINI(Data(text.utf8)) }

    private let registration = """
    avd.ini.encoding=UTF-8
    path=/Users/test/.android/avd/Test_Phone_A.avd
    path.rel=avd/Test_Phone_A.avd
    target=android-36
    """

    private let config = """
    AvdId=Test_Phone_A
    PlayStore.enabled=true
    abi.type=arm64-v8a
    avd.ini.displayname=Test Phone A
    avd.ini.encoding=UTF-8
    disk.dataPartition.size=6G
    fastboot.chosenSnapshotFile=
    fastboot.forceChosenSnapshotBoot=no
    fastboot.forceColdBoot=no
    fastboot.forceFastBoot=yes
    hw.accelerometer=yes
    hw.arc=false
    hw.audioInput=yes
    hw.battery=yes
    hw.camera.back=virtualscene
    hw.camera.front=emulated
    hw.cpu.arch=arm64
    hw.cpu.ncore=4
    hw.dPad=no
    hw.device.manufacturer=Generic
    hw.device.name=medium_phone
    hw.gps=yes
    hw.gpu.enabled=yes
    hw.gpu.mode=auto
    hw.initialOrientation=portrait
    hw.keyboard=yes
    hw.lcd.density=420
    hw.lcd.height=2400
    hw.lcd.width=1080
    hw.ramSize=2048
    image.sysdir.1=system-images/android-36/google_apis_playstore/arm64-v8a/
    runtime.network.latency=none
    tag.display=Google Play
    tag.id=google_apis_playstore
    vm.heapSize=228
    """

    // MARK: Nom

    @Test func validAndInvalidNames() {
        for valid in ["Test_Phone_A", "Test_Phone-1.2", "a", "A.b-c_9", "..x", "x.."] {
            #expect(AndroidEmulatorScanner.isValidAVDName(valid), "\(valid)")
        }
        for invalid in ["../x", "a/b", "", ".", "..", "bad name", "tést", "a\nb", "/", "a\\b", "a:b"] {
            #expect(!AndroidEmulatorScanner.isValidAVDName(invalid), "\(invalid)")
        }
    }

    // MARK: INI

    @Test func theRegistrationFileParses() throws {
        let values = try #require(ini(registration))
        #expect(values["avd.ini.encoding"] == "UTF-8")
        #expect(values["path"] == "/Users/test/.android/avd/Test_Phone_A.avd")
        #expect(values["path.rel"] == "avd/Test_Phone_A.avd")
        #expect(values["target"] == "android-36")
    }

    @Test func aTypicalConfigGivesTheDisplayNameAndTheSystem() throws {
        let values = try #require(ini(config))
        #expect(values.count == 35)
        #expect(AndroidEmulatorScanner.displayName(config: values, avdName: "Test_Phone_A") == "Test Phone A")
        #expect(AndroidEmulatorScanner.systemVersion(imageSysdir: values["image.sysdir.1"]) == "36")
        #expect(values["fastboot.chosenSnapshotFile"] == "")
    }

    @Test func commentsBlankLinesAndLinesWithoutEqualsAreIgnored() throws {
        let values = try #require(ini("# comment\n; other comment\n\n   \nno equals here\na=1\n  # indented comment is a comment\n"))
        #expect(values == ["a": "1"])
    }

    @Test func keysAndValuesAreTrimmedAndSplitAtTheFirstEquals() throws {
        let values = try #require(ini("  key  =  a=b=c  \r\nother=x\r\n"))
        #expect(values == ["key": "a=b=c", "other": "x"])
    }

    @Test func theFirstOfARepeatedKeyWins() throws {
        let values = try #require(ini("a=first\na=second\n"))
        #expect(values["a"] == "first")
    }

    @Test func invalidUTF8GivesNothing() {
        #expect(AndroidEmulatorScanner.parseINI(Data([0x61, 0x3D, 0xFF, 0xFE, 0x0A])) == nil)
    }

    @Test func emptyInputGivesAnEmptyDictionary() {
        #expect(AndroidEmulatorScanner.parseINI(Data()) == [:])
    }

    // MARK: Système

    @Test func systemVersionFromTheImageFolder() {
        #expect(AndroidEmulatorScanner.systemVersion(imageSysdir: "system-images/android-36/google_apis_playstore/arm64-v8a/") == "36")
        #expect(AndroidEmulatorScanner.systemVersion(imageSysdir: "system-images/android-36.1/google_apis/arm64-v8a/") == "36.1")
        #expect(AndroidEmulatorScanner.systemVersion(imageSysdir: "/Users/test/Library/Android/sdk/system-images/android-34/default/arm64-v8a/") == "34")
    }

    @Test func anythingElseGivesNoVersion() {
        #expect(AndroidEmulatorScanner.systemVersion(imageSysdir: nil) == nil)
        #expect(AndroidEmulatorScanner.systemVersion(imageSysdir: "") == nil)
        #expect(AndroidEmulatorScanner.systemVersion(imageSysdir: "system-images/android-Baklava/google_apis/arm64-v8a/") == nil)
        #expect(AndroidEmulatorScanner.systemVersion(imageSysdir: "system-images/android-36-ext/x/y/") == nil)
        #expect(AndroidEmulatorScanner.systemVersion(imageSysdir: "system-images/android-/x/") == nil)
        #expect(AndroidEmulatorScanner.systemVersion(imageSysdir: "other/android-36/x/") == nil)
        #expect(AndroidEmulatorScanner.systemVersion(imageSysdir: "system-images/") == nil)
    }

    @Test func aMissingImageKeyGivesNoVersion() throws {
        let values = try #require(ini(config.replacingOccurrences(of: "image.sysdir.1", with: "image.sysdir.2")))
        #expect(AndroidEmulatorScanner.systemVersion(imageSysdir: values["image.sysdir.1"]) == nil)
    }

    // MARK: Nom affiché

    @Test func anEmptyOrMissingDisplayNameFallsBackToTheAVDName() throws {
        let empty = try #require(ini("avd.ini.displayname=\n"))
        #expect(AndroidEmulatorScanner.displayName(config: empty, avdName: "Test_Phone_A") == "Test_Phone_A")
        #expect(AndroidEmulatorScanner.displayName(config: [:], avdName: "Test_Phone_A") == "Test_Phone_A")
        #expect(AndroidEmulatorScanner.displayName(config: ["avd.ini.displayname": "   "], avdName: "Test_Phone_A") == "Test_Phone_A")
    }
}
