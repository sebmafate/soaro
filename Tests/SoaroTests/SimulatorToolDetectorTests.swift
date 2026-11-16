import Foundation
import Testing
@testable import Soaro

/// Faux système de fichiers écrit à la main : rien n'est lu sur le vrai disque.
private final class FakeToolFileSystem: ToolFileSystem {
    var directories = Set<String>()
    var executables = Set<String>()      // fichiers ordinaires exécutables
    var plainFiles = Set<String>()       // fichiers ordinaires non exécutables
    var links: [String: String] = [:]
    var listings: [String: [String]] = [:]

    func isDirectory(_ path: String) -> Bool { directories.contains(path) }
    func isExecutableRegularFile(_ path: String) -> Bool { executables.contains(path) }
    func symlinkDestination(of path: String) -> String? { links[path] }
    func entries(inDirectory path: String) -> [String] { listings[path] ?? [] }
}

@Suite struct SimulatorToolDetectorTests {
    private let home = URL(fileURLWithPath: "/home-fake/user-x")
    private var devicesPath: String { "/home-fake/user-x/Library/Developer/CoreSimulator/Devices" }
    private let link = "/var/db/xcode_select_link"
    private let xcodeSimctl = "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl"

    private func detect(_ fs: FakeToolFileSystem) -> SimulatorToolDetection {
        SimulatorToolDetector.detect(home: home, fileSystem: fs)
    }

    @Test func nothingAtAllMeansAbsent() {
        let result = detect(FakeToolFileSystem())
        #expect(result.devicesFolderExists == false)
        #expect(result.simctlPath == nil)
        #expect(result.isToolPresent == false)
    }

    @Test func devicesFolderOnlyMeansPresentWithoutSimctlAndNothingIsLaunched() {
        let fs = FakeToolFileSystem()
        fs.directories.insert(devicesPath)
        let result = detect(fs)
        #expect(result.devicesFolderExists)
        #expect(result.simctlPath == nil)
        #expect(result.isToolPresent)

        // La porte du lanceur reste fermée : le faux lanceur ne reçoit aucun appel.
        let runner = FakeCommandRunner()
        let xcrun = ToolLocator.simulatorXcrunPath(detection: result, locate: { _ in "/usr/bin/xcrun" })
        #expect(xcrun == nil)
        let scan = SimulatorScanner.scan(runner: runner, xcrunPath: xcrun, home: home)
        #expect(scan.status == .toolNotFound)
        #expect(runner.calls.isEmpty)
    }

    @Test func diagnosticsRunsNothingWhenNoSimctlIsOnDisk() {
        // `Soaro --scan` suit la même porte : sans simctl actif, aucun appel, même si `xcrun` existe.
        let fs = FakeToolFileSystem()
        fs.links[link] = "/Library/Developer/CommandLineTools"
        fs.executables.insert(xcodeSimctl)
        let runner = FakeCommandRunner()
        let scan = Diagnostics.simulatorScan(runner: runner, home: home, fileSystem: fs, locate: { _ in "/usr/bin/xcrun" })
        #expect(scan.status == .toolNotFound)
        #expect(runner.calls.isEmpty)
        #expect(runner.unscriptedCalls.isEmpty)
    }

    @Test func diagnosticsRunsTheCommandWhenTheActiveSimctlExists() {
        let fs = FakeToolFileSystem()
        fs.links[link] = "/Applications/Xcode.app/Contents/Developer"
        fs.executables.insert(xcodeSimctl)
        let runner = FakeCommandRunner()
        runner.script(.finished(stdout: "{\"devices\": {}}"), executable: "/usr/bin/xcrun", arguments: SimulatorScanner.listArguments)
        let scan = Diagnostics.simulatorScan(runner: runner, home: home, fileSystem: fs, locate: { _ in "/usr/bin/xcrun" })
        #expect(scan.status == .ok)
        #expect(runner.calls.count == 1)
    }

    @Test func devicesFolderThatIsAFileDoesNotCount() {
        let fs = FakeToolFileSystem()
        fs.plainFiles.insert(devicesPath)
        #expect(detect(fs).devicesFolderExists == false)
    }

    @Test func linkToCommandLineToolsWithoutSimctlAndNoXcodeIsAbsent() {
        let fs = FakeToolFileSystem()
        fs.links[link] = "/Library/Developer/CommandLineTools"
        fs.directories.insert("/Library/Developer/CommandLineTools")
        let result = detect(fs)
        #expect(result.simctlPath == nil)
        #expect(result.isToolPresent == false)
    }

    @Test func linkToXcodeWithSimctlGivesThatPath() {
        let fs = FakeToolFileSystem()
        let beta = "/Applications/Xcode-beta.app/Contents/Developer"
        fs.links[link] = beta
        fs.executables.insert(beta + "/usr/bin/simctl")
        fs.executables.insert(xcodeSimctl)   // présent aussi : le lien passe en premier
        #expect(detect(fs).simctlPath == beta + "/usr/bin/simctl")
    }

    @Test func missingLinkFallsBackToXcodeApp() {
        let fs = FakeToolFileSystem()
        fs.executables.insert(xcodeSimctl)
        #expect(detect(fs).simctlPath == xcodeSimctl)
    }

    @Test func onlyXcodeBetaIsFound() {
        let fs = FakeToolFileSystem()
        fs.listings["/Applications"] = ["Safari.app", "Xcode-beta.app", "Notes.app"]
        let path = "/Applications/Xcode-beta.app/Contents/Developer/usr/bin/simctl"
        fs.executables.insert(path)
        #expect(detect(fs).simctlPath == path)
    }

    @Test func otherXcodeCopiesAreTriedInNameOrder() {
        let fs = FakeToolFileSystem()
        fs.listings["/Applications"] = ["Xcode_16.app", "Xcode-beta.app", "Xcode15.app", "Xcodeless", "NotXcode.app"]
        fs.executables.insert("/Applications/Xcode_16.app/Contents/Developer/usr/bin/simctl")
        fs.executables.insert("/Applications/Xcode-beta.app/Contents/Developer/usr/bin/simctl")
        fs.executables.insert("/Applications/Xcode15.app/Contents/Developer/usr/bin/simctl")
        fs.executables.insert("/Applications/NotXcode.app/Contents/Developer/usr/bin/simctl")
        // Tri par nom : « Xcode-beta.app » < « Xcode15.app » < « Xcode_16.app ».
        #expect(detect(fs).simctlPath == "/Applications/Xcode-beta.app/Contents/Developer/usr/bin/simctl")
    }

    @Test func candidateOrderLinkThenXcodeAppThenOthers() {
        let fs = FakeToolFileSystem()
        fs.listings["/Applications"] = ["Xcode-beta.app"]
        fs.executables.insert("/Applications/Xcode-beta.app/Contents/Developer/usr/bin/simctl")
        fs.executables.insert(xcodeSimctl)
        #expect(detect(fs).simctlPath == xcodeSimctl, "Xcode.app passe avant les autres copies")
    }

    @Test func aDirectoryOrANonExecutableCandidateIsSkipped() {
        let fs = FakeToolFileSystem()
        // Lien absent : Xcode.app a un fichier non exécutable, Xcode-dir.app un dossier, Xcode-old.app un vrai simctl.
        fs.plainFiles.insert(xcodeSimctl)
        fs.directories.insert("/Applications/Xcode-dir.app/Contents/Developer/usr/bin/simctl")
        fs.listings["/Applications"] = ["Xcode-dir.app", "Xcode-old.app"]
        let last = "/Applications/Xcode-old.app/Contents/Developer/usr/bin/simctl"
        fs.executables.insert(last)
        #expect(detect(fs).simctlPath == last)
    }

    @Test func aLinkToADirectoryOrANonExecutableSimctlIsAbsentWithoutFallback() {
        let fs = FakeToolFileSystem()
        fs.links[link] = "/Applications/Xcode-beta.app/Contents/Developer"
        fs.directories.insert("/Applications/Xcode-beta.app/Contents/Developer/usr/bin/simctl")
        fs.executables.insert(xcodeSimctl)
        #expect(detect(fs).simctlPath == nil, "le lien est la seule source : pas de repli")
    }

    // MARK: Le simctl que xcrun lancera vraiment (celui du dossier actif)

    @Test func linkToCommandLineToolsWithXcodeInstalledMeansTheActiveSimctlIsAbsent() {
        let fs = FakeToolFileSystem()
        fs.links[link] = "/Library/Developer/CommandLineTools"
        fs.directories.insert("/Library/Developer/CommandLineTools")
        fs.executables.insert(xcodeSimctl)                          // Xcode est installé, mais pas actif
        fs.listings["/Applications"] = ["Xcode.app", "Xcode-beta.app"]
        fs.executables.insert("/Applications/Xcode-beta.app/Contents/Developer/usr/bin/simctl")
        fs.directories.insert(devicesPath)
        let result = detect(fs)
        #expect(result.simctlPath == nil)
        #expect(result.devicesFolderExists)
        #expect(result.isToolPresent, "la rangée reste visible : le dossier des appareils existe")

        // Le lanceur n'est jamais appelé ; le message neutre s'affichera.
        let runner = FakeCommandRunner()
        let xcrun = ToolLocator.simulatorXcrunPath(detection: result, locate: { _ in "/usr/bin/xcrun" })
        #expect(xcrun == nil)
        #expect(SimulatorScanner.list(runner: runner, xcrunPath: xcrun).status == .toolNotFound)
        #expect(runner.calls.isEmpty)
    }

    @MainActor
    @Test func cltActiveWithXcodeInstalledShowsTheNeutralMessageAndLaunchesNothing() async {
        let fs = FakeToolFileSystem()
        fs.links[link] = "/Library/Developer/CommandLineTools"
        fs.executables.insert(xcodeSimctl)
        fs.directories.insert(devicesPath)
        let detection = SimulatorToolDetector.detect(home: home, fileSystem: fs)
        #expect(SimulatorToolDetection.showsToolsRow(detection: detection, demo: false))

        let runner = FakeCommandRunner()
        let model = SimulatorsModel(runner: runner, detect: { detection }, locateXcrun: { _ in "/usr/bin/xcrun" },
                                    home: home, demo: false, notify: { _ in })
        model.scan()
        await model.scanTask?.value
        #expect(runner.calls.isEmpty)
        #expect(model.phase == .failed(.couldNotRead))
        #expect(model.message == "Could not read the iOS Simulators.")
    }

    @Test func missingLinkAndNoXcodeMeansAbsent() {
        let fs = FakeToolFileSystem()
        fs.listings["/Applications"] = ["Safari.app"]
        #expect(detect(fs).simctlPath == nil)
    }

    @Test func relativeLinkDestinationIsResolvedAgainstVarDb() {
        let fs = FakeToolFileSystem()
        fs.links[link] = "../../Applications/Xcode-rel.app/Contents/Developer"
        let path = "/Applications/Xcode-rel.app/Contents/Developer/usr/bin/simctl"
        fs.executables.insert(path)
        #expect(detect(fs).simctlPath == path)
    }

    /// Normalisation PURE (chaînes seulement) : même résultat sur toute version de macOS, sans URL ni système de fichiers.
    @Test(arguments: [
        ("../../Applications/Xcode-rel.app/Contents/Developer", "/Applications/Xcode-rel.app/Contents/Developer"),
        ("./x/../Xcode.app/Contents/Developer", "/var/db/Xcode.app/Contents/Developer"),
        ("../../Applications/Xcode.app/Contents/Developer/", "/Applications/Xcode.app/Contents/Developer"),
        ("..//..//Applications//Xcode.app///Contents/Developer", "/Applications/Xcode.app/Contents/Developer"),
        ("../../../../../Applications/Xcode.app", "/Applications/Xcode.app"),
        ("../../..", "/"),
        (".", "/var/db"),
        ("", "/var/db"),
        ("a/./b/../c", "/var/db/a/c"),
        // Destination absolue : normalisée de la même façon, sans accès au disque.
        ("/Applications/Xcode.app/Contents/Developer", "/Applications/Xcode.app/Contents/Developer"),
        ("/Applications//Xcode.app/./Contents/../Contents/Developer/", "/Applications/Xcode.app/Contents/Developer"),
        ("/../../Library/Developer/CommandLineTools", "/Library/Developer/CommandLineTools"),
        ("/", "/"),
    ])
    func linkDestinationIsNormalisedAsPureStrings(destination: String, expected: String) {
        #expect(SimulatorToolDetector.resolvedPath(destination: destination, base: "/var/db") == expected)
    }

    @Test func relativeLinkWithDotsAndTrailingSlashStillGivesTheCandidate() {
        let fs = FakeToolFileSystem()
        fs.links[link] = "./../db/../../Applications//Xcode-rel.app/Contents/Developer/"
        let path = "/Applications/Xcode-rel.app/Contents/Developer/usr/bin/simctl"
        fs.executables.insert(path)
        #expect(detect(fs).simctlPath == path)
    }

    @Test func aLinkToTheRootDoesNotDoubleTheSlash() {
        let fs = FakeToolFileSystem()
        fs.links[link] = "/"
        fs.executables.insert("/usr/bin/simctl")
        #expect(detect(fs).simctlPath == "/usr/bin/simctl")
    }

    @Test func gateOpensOnlyWithSimctlAndXcrun() {
        let withSimctl = SimulatorToolDetection(devicesFolderExists: false, simctlPath: "/x/simctl")
        let without = SimulatorToolDetection(devicesFolderExists: true, simctlPath: nil)
        #expect(ToolLocator.simulatorXcrunPath(detection: withSimctl, locate: { _ in "/usr/bin/xcrun" }) == "/usr/bin/xcrun")
        #expect(ToolLocator.simulatorXcrunPath(detection: withSimctl, locate: { _ in nil }) == nil)
        #expect(ToolLocator.simulatorXcrunPath(detection: without, locate: { _ in "/usr/bin/xcrun" }) == nil)
    }

    @Test func detectorSourceLaunchesNothing() throws {
        let url = RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Cleanup/SimulatorToolDetector.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("Process"))
        #expect(!text.contains("CommandRunner"))
        #expect(!text.contains("DEVELOPER_DIR"))
        #expect(!text.contains("environment"))
    }
}
