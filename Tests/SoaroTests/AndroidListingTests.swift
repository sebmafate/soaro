import Foundation
import Testing
@testable import Soaro

/// Un seul listage Android : SDK, AVD, processus (R16, R18, R6). Dossier personnel dans le bac à sable, faux lanceur,
/// environnement injecté (jamais celui de la machine : la CI définit `ANDROID_HOME`).
@Suite(.serialized) struct AndroidListingTests {
    private let psArguments = ["-axww", "-o", "command="]

    private func makeAVD(_ box: Sandbox, _ name: String) throws {
        try box.dir(".android/avd/\(name).avd")
        try box.write(".android/avd/\(name).ini", "path.rel=avd/\(name).avd\n")
        try box.write(".android/avd/\(name).avd/config.ini", "image.sysdir.1=system-images/android-36/google_apis/arm64-v8a/\n")
    }

    private func makeSDK(_ box: Sandbox) throws { try box.dir("Library/Android/sdk") }

    private func list(_ box: Sandbox, runner: FakeCommandRunner, psPath: String? = "/bin/ps", environment: [String: String] = [:]) -> AndroidListing {
        AndroidEmulatorScanner.list(runner: runner, psPath: psPath, environment: environment, home: box.root)
    }

    @Test func noSdkMeansNothingAndNothingIsLaunchedEvenWithAvds() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, "Test_Phone_A")
        let runner = FakeCommandRunner()
        let listing = list(box, runner: runner)
        #expect(listing.status == .sdkNotFound)
        #expect(listing.devices.isEmpty)
        #expect(listing.sdk == nil)
        #expect(runner.calls.isEmpty)
    }

    @Test func aMissingSdkRootHidesTheGroupEvenWhenTheDefaultExists() throws {
        let box = try Sandbox(insideHome: true)
        try makeSDK(box)
        try makeAVD(box, "Test_Phone_A")
        let runner = FakeCommandRunner()
        let listing = list(box, runner: runner, environment: ["ANDROID_SDK_ROOT": box.root.appendingPathComponent("nonexistent").path])
        #expect(listing.status == .sdkNotFound)
        #expect(runner.calls.isEmpty)
    }

    @Test func anSdkWithoutAnAvdFolderIsOkAndEmptyWithoutCallingPs() throws {
        let box = try Sandbox(insideHome: true)
        try makeSDK(box)
        let runner = FakeCommandRunner()
        let listing = list(box, runner: runner)
        #expect(listing.status == .ok)
        #expect(listing.devices.isEmpty)
        #expect(listing.sdk?.source == .defaultLocation)
        #expect(runner.calls.isEmpty)
    }

    @Test func runningIsMarkedFromThePsOutputWithExactlyOneCall() throws {
        let box = try Sandbox(insideHome: true)
        try makeSDK(box)
        try makeAVD(box, "Test_Phone_A")
        try makeAVD(box, "Test_Tablet_B")
        let runner = FakeCommandRunner()
        runner.script(.finished(stdout: "/Users/test/Library/Android/sdk/emulator/qemu/darwin-aarch64/qemu-system-aarch64 -avd Test_Phone_A -qt-hide-window\n"),
                      executable: "/bin/ps", arguments: psArguments)
        let listing = list(box, runner: runner)
        #expect(listing.status == .ok)
        #expect(listing.devices.map(\.name) == ["Test_Phone_A", "Test_Tablet_B"])
        #expect(listing.devices.map(\.isRunning) == [true, false])
        #expect(runner.calls.count == 1)
        #expect(runner.calls.first?.executable == "/bin/ps")
    }

    @Test func aDifferentCaseInThePsLineStillMarksTheDeviceRunning() throws {
        let box = try Sandbox(insideHome: true)
        try makeSDK(box)
        try makeAVD(box, "Test_Phone_A")
        try makeAVD(box, "Test_Phone_AB")
        let runner = FakeCommandRunner()
        runner.script(.finished(stdout: "emulator -avd test_phone_a\n"), executable: "/bin/ps", arguments: psArguments)
        let listing = list(box, runner: runner)
        #expect(listing.devices.map(\.isRunning) == [true, false])
    }

    @Test func aRunningEmulatorStartedUnderTheOtherRegistrationNameMarksTheSharedFolderRunning() throws {
        let box = try Sandbox(insideHome: true)
        try makeSDK(box)
        try makeAVD(box, "Test_Phone_A")
        try box.write(".android/avd/Test_Phone_Z.ini", "path.rel=avd/Test_Phone_A.avd\n")     // même dossier, autre nom
        let runner = FakeCommandRunner()
        runner.script(.finished(stdout: "emulator -avd test_phone_z\n"), executable: "/bin/ps", arguments: psArguments)
        let listing = list(box, runner: runner)
        #expect(listing.devices.map(\.name) == ["Test_Phone_A"], "une ligne par dossier")
        #expect(listing.devices.first?.aliases == ["Test_Phone_Z"])
        #expect(listing.devices.first?.isRunning == true, "un émulateur lancé sous l'autre nom compte : jamais proposé")
        let other = FakeCommandRunner()
        other.script(.finished(stdout: "emulator -avd Test_Phone_AB\n"), executable: "/bin/ps", arguments: psArguments)
        #expect(list(box, runner: other).devices.first?.isRunning == false)
    }

    @Test func aTimedOutPsMakesTheGroupUnreadable() throws {
        let box = try Sandbox(insideHome: true)
        try makeSDK(box)
        try makeAVD(box, "Test_Phone_A")
        let runner = FakeCommandRunner()
        runner.script(.timedOut, executable: "/bin/ps", arguments: psArguments)
        let listing = list(box, runner: runner)
        #expect(listing.status == .couldNotRead)
        #expect(listing.devices.isEmpty, "aucune ligne n'est proposée quand l'état « en cours » est invérifiable")
    }

    @Test func aNilPsPathMakesTheGroupUnreadableWithoutAnyCall() throws {
        let box = try Sandbox(insideHome: true)
        try makeSDK(box)
        try makeAVD(box, "Test_Phone_A")
        let runner = FakeCommandRunner()
        let listing = list(box, runner: runner, psPath: nil)
        #expect(listing.status == .couldNotRead)
        #expect(runner.calls.isEmpty)
    }

    @Test func anUnreadableAvdFolderIsCouldNotReadWithoutCallingPs() throws {
        let box = try Sandbox(insideHome: true)
        try makeSDK(box)
        try box.file(".android/avd")
        let runner = FakeCommandRunner()
        let listing = list(box, runner: runner)
        #expect(listing.status == .couldNotRead)
        #expect(runner.calls.isEmpty)
    }

    @Test func theListingCarriesTheSkippedCount() throws {
        let box = try Sandbox(insideHome: true)
        try makeSDK(box)
        try makeAVD(box, "Test_Phone_A")
        try box.write(".android/avd/Gone.ini", "path.rel=avd/Gone.avd\n")
        let runner = FakeCommandRunner()
        runner.script(.finished(stdout: ""), executable: "/bin/ps", arguments: psArguments)
        let listing = list(box, runner: runner)
        #expect(listing.devices.count == 1)
        #expect(listing.skippedCount == 1)
    }

    @Test func theSdkFromTheEnvironmentIsReported() throws {
        let box = try Sandbox(insideHome: true)
        try box.dir("elsewhere/sdk")
        let path = box.root.appendingPathComponent("elsewhere/sdk").path
        let listing = list(box, runner: FakeCommandRunner(), environment: ["ANDROID_HOME": path])
        #expect(listing.status == .ok)
        #expect(listing.sdk == AndroidSDKLocation(path: path, source: .androidHome))
    }

    @Test func eachDeviceHasItsFolderForTheMeasure() throws {
        let box = try Sandbox(insideHome: true)
        try makeSDK(box)
        try makeAVD(box, "Test_Phone_A")
        let runner = FakeCommandRunner()
        runner.script(.finished(stdout: ""), executable: "/bin/ps", arguments: psArguments)
        let device = try #require(list(box, runner: runner).devices.first)
        #expect(device.folder.lastPathComponent == "Test_Phone_A.avd")
    }
}
