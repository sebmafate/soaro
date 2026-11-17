import Foundation
import Testing
@testable import Soaro

/// Détection des émulateurs en cours d'exécution (R16, ADR 0009 règle 3) : à partir de `/bin/ps`, par le faux lanceur.
/// Les lignes `ps` sont écrites à la main depuis le format connu, anonymisées. Aucun vrai `ps`.
@Suite(.serialized) struct AndroidRunningDetectionTests {
    private let studioLine = "/Users/test/Library/Android/sdk/emulator/qemu/darwin-aarch64/qemu-system-aarch64 -netdelay none -netspeed full -avd Test_Phone_A -qt-hide-window -grpc-use-token -idle-grpc-timeout 300"
    private let shortFormLine = "/Users/test/Library/Android/sdk/emulator/emulator @Test_Phone_B"
    private let psArguments = ["-axww", "-o", "command="]

    private func names(_ text: String) -> Set<String> { AndroidEmulatorScanner.runningNames(fromProcessList: text) }

    // MARK: Lecture du texte

    @Test func anAndroidStudioLineGivesItsName() {
        #expect(names(studioLine) == ["Test_Phone_A"])
    }

    @Test func theShortFormGivesItsName() {
        #expect(names(shortFormLine) == ["Test_Phone_B"])
    }

    @Test func severalLinesGiveSeveralNames() {
        #expect(names("/sbin/launchd\n\(studioLine)\n/usr/bin/some-tool --flag\n\(shortFormLine)\n") == ["Test_Phone_A", "Test_Phone_B"])
    }

    @Test func matchingIsExactAndCaseSensitive() {
        let found = names("emulator -avd Test_Phone_AB")
        #expect(found == ["Test_Phone_AB"])
        #expect(!found.contains("Test_Phone_A"))
        #expect(!names("emulator -avd test_phone_a").contains("Test_Phone_A"))
    }

    @Test func aLineMentioningAnIniWithoutAvdMatchesNothing() {
        #expect(names("/usr/bin/vim /Users/test/.android/avd/Test_Phone_A.ini").isEmpty)
        #expect(names("tail -f Test_Phone_A").isEmpty)
    }

    @Test func aTrailingAvdFlagIsIgnored() {
        #expect(names("/x/emulator -netspeed full -avd").isEmpty)
        #expect(names("/x/emulator -avd \n-avd Test_Phone_A").contains("Test_Phone_A"))
    }

    @Test func theFlagAtTheEndOfALineDoesNotTakeTheNextLinesFirstWord() {
        #expect(names("/x/emulator -avd\nTest_Phone_A -foo").isEmpty)
    }

    @Test func emptyOutputGivesAnEmptySet() {
        #expect(names("").isEmpty)
        #expect(names("\n\n  \n").isEmpty)
    }

    @Test func invalidNamesAreDropped() {
        #expect(names("emulator -avd ../x").isEmpty)
        #expect(names("emulator -avd a/b").isEmpty)
        #expect(names("emulator -avd ..").isEmpty)
        #expect(names("emulator @").isEmpty)
        #expect(names("emulator @a/b").isEmpty)
    }

    @Test func tabsSeparateTokensToo() {
        #expect(names("emulator\t-avd\tTest_Phone_A") == ["Test_Phone_A"])
    }

    // MARK: Commande

    @Test func theCommandIsExactlyPsWithItsArgumentsAndLimits() {
        let runner = FakeCommandRunner()
        runner.script(.finished(stdout: studioLine), executable: "/bin/ps", arguments: psArguments)
        let found = AndroidEmulatorScanner.runningAVDNames(runner: runner, psPath: "/bin/ps")
        #expect(found == ["Test_Phone_A"])
        #expect(runner.calls == [.init(executable: "/bin/ps", arguments: ["-axww", "-o", "command="], timeLimit: 10, outputLimit: 4 * 1024 * 1024)])
        #expect(AndroidEmulatorScanner.processListTimeLimit == 10)
        #expect(AndroidEmulatorScanner.processListOutputLimit == 4_194_304)
    }

    @Test func emptyOutputIsAnEmptySetNotUnavailable() {
        let runner = FakeCommandRunner()
        runner.script(.finished(stdout: ""), executable: "/bin/ps", arguments: psArguments)
        #expect(AndroidEmulatorScanner.runningAVDNames(runner: runner, psPath: "/bin/ps") == [])
    }

    private func unavailable(_ outcome: CommandOutcome) -> Bool {
        let runner = FakeCommandRunner()
        runner.script(outcome, executable: "/bin/ps", arguments: psArguments)
        return AndroidEmulatorScanner.runningAVDNames(runner: runner, psPath: "/bin/ps") == nil
    }

    @Test func aTimeoutIsUnavailable() { #expect(unavailable(.timedOut)) }
    @Test func aLaunchFailureIsUnavailable() { #expect(unavailable(.failedToLaunch)) }
    @Test func aRefusalIsUnavailable() {
        #expect(unavailable(.refused(.notAbsolutePath)))
        #expect(unavailable(.refused(.shell)))
    }
    @Test func aNonZeroExitIsUnavailable() { #expect(unavailable(.finished(exit: 1, stdout: studioLine))) }
    @Test func aSignalEndIsUnavailable() { #expect(unavailable(.finished(exit: 9, stdout: studioLine, termination: .signaled))) }
    @Test func truncatedOutputIsUnavailable() { #expect(unavailable(.finished(stdout: studioLine, truncated: true))) }

    @Test func aNilPathLaunchesNothing() {
        let runner = FakeCommandRunner()
        #expect(AndroidEmulatorScanner.runningAVDNames(runner: runner, psPath: nil) == nil)
        #expect(runner.calls.isEmpty)
    }

    @Test func standardErrorIsNeverRead() {
        let runner = FakeCommandRunner()
        runner.script(.finished(stdout: "", stderr: "emulator -avd Test_Phone_A"), executable: "/bin/ps", arguments: psArguments)
        #expect(AndroidEmulatorScanner.runningAVDNames(runner: runner, psPath: "/bin/ps") == [])
    }
}
