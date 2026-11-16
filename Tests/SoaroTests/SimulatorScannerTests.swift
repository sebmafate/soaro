import Foundation
import Testing
@testable import Soaro

@Suite struct SimulatorScannerTests {
    private let xcrun = "/usr/bin/xcrun"
    private let args = ["simctl", "list", "devices", "-j"]
    private let u1 = "00000000-0000-4000-8000-000000000001"
    private let u2 = "00000000-0000-4000-8000-000000000002"

    private func listJSON(_ udids: [String]) -> String {
        let entries = udids.map { "{\"udid\": \"\($0)\", \"name\": \"Device \($0.suffix(1))\", \"state\": \"Shutdown\", \"deviceTypeIdentifier\": \"com.apple.CoreSimulator.SimDeviceType.iPhone-17\"}" }
        return "{\"devices\": {\"com.apple.CoreSimulator.SimRuntime.iOS-26-2\": [\(entries.joined(separator: ","))]}}"
    }

    private func fake(_ outcome: CommandOutcome) -> FakeCommandRunner {
        let fake = FakeCommandRunner()
        fake.script(outcome, executable: xcrun, arguments: args)
        return fake
    }

    private func scan(_ runner: FakeCommandRunner, home: URL, xcrun path: String? = "/usr/bin/xcrun", isCancelled: @escaping () -> Bool = { false }) -> SimulatorScan {
        SimulatorScanner.scan(runner: runner, xcrunPath: path, home: home, isCancelled: isCancelled)
    }

    private func deviceFolder(_ box: Sandbox, _ udid: String) -> String {
        "Library/Developer/CoreSimulator/Devices/\(udid)"
    }

    // MARK: Commande exacte

    @Test func runsExactlyOneCommandWithTheDocumentedLimits() throws {
        let box = try Sandbox()
        let runner = fake(.finished(stdout: listJSON([u1])))
        _ = scan(runner, home: box.root)

        #expect(runner.calls == [.init(executable: "/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "-j"],
                                       timeLimit: 60, outputLimit: 8 * 1024 * 1024)])
        #expect(SimulatorScanner.listTimeLimit == 60)
        #expect(SimulatorScanner.outputLimit == 8_388_608)
    }

    // MARK: États

    @Test func toolNotFoundRunsNothing() throws {
        let box = try Sandbox()
        let runner = FakeCommandRunner()
        let result = scan(runner, home: box.root, xcrun: nil)
        #expect(result.status == .toolNotFound)
        #expect(result.devices.isEmpty)
        #expect(runner.calls.isEmpty)
    }

    @Test func aToolThatCannotBeLaunchedIsReportedAsNotFound() throws {
        let box = try Sandbox()
        let result = scan(fake(.failedToLaunch), home: box.root)
        #expect(result.status == .toolNotFound)
        #expect(result.devices.isEmpty)
    }

    @Test func nonZeroExitIsAFailureAndStderrIsNotKept() throws {
        let box = try Sandbox()
        let result = scan(fake(.finished(exit: 72, stdout: listJSON([u1]), stderr: "xcrun: error: something with /Users/someone")), home: box.root)
        #expect(result.status == .commandFailed(exitCode: 72))
        #expect(result.devices.isEmpty, "pas d'analyse d'une sortie d'échec")
    }

    @Test func timedOutIsReported() throws {
        let box = try Sandbox()
        let result = scan(fake(.timedOut), home: box.root)
        #expect(result.status == .timedOut)
        #expect(result.devices.isEmpty)
    }

    @Test func aRefusedCommandIsAFailureWithoutExitCode() throws {
        let box = try Sandbox()
        let result = scan(fake(.refused(.shell)), home: box.root)
        #expect(result.status == .commandFailed(exitCode: nil))
    }

    @Test func malformedJSONIsNotReadable() throws {
        let box = try Sandbox()
        for text in ["", "not json", "{\"devices\": ", "[]", "{}"] {
            let result = scan(fake(.finished(stdout: text)), home: box.root)
            #expect(result.status == .outputNotReadable, "«\(text)»")
            #expect(result.devices.isEmpty)
        }
    }

    @Test func truncatedOutputIsNotReadableEvenIfItLooksValid() throws {
        let box = try Sandbox()
        let result = scan(fake(.finished(stdout: listJSON([u1]), truncated: true)), home: box.root)
        #expect(result.status == .outputNotReadable)
        #expect(result.devices.isEmpty, "pas d'analyse partielle")
    }

    @Test func truncatedOutputIsNotReadableWhateverTheExitCode() throws {
        let box = try Sandbox()
        // Un processus tué parce que sa sortie dépassait la borne n'a pas de code de sortie ordinaire (9 = SIGKILL observé).
        for (code, termination) in [(Int32(9), CommandTermination.signaled), (9, .exited), (1, .exited), (0, .signaled)] {
            let result = scan(fake(.finished(exit: code, stdout: listJSON([u1]), truncated: true, termination: termination)), home: box.root)
            #expect(result.status == .outputNotReadable, "code \(code), \(termination)")
            #expect(result.devices.isEmpty)
        }
    }

    @Test func aProcessEndedByASignalIsAFailureWithoutAnExitCode() throws {
        let box = try Sandbox()
        let result = scan(fake(.finished(exit: 11, stdout: listJSON([u1]), termination: .signaled)), home: box.root)
        #expect(result.status == .commandFailed(exitCode: nil))
        #expect(result.devices.isEmpty)
    }

    @Test func emptyDevicesIsOkAndEmpty() throws {
        let box = try Sandbox()
        let result = scan(fake(.finished(stdout: "{\"devices\": {}}")), home: box.root)
        #expect(result.status == .ok)
        #expect(result.devices.isEmpty)
        #expect(!result.cancelled)
    }

    // MARK: Tailles

    @Test func sizesComeFromTheWholeDeviceFolderUnderTheGivenHome() throws {
        let box = try Sandbox()
        try box.file("\(deviceFolder(box, u1))/data/a.bin", bytes: 300_000)
        try box.file("\(deviceFolder(box, u1))/device.plist", bytes: 100_000)
        try box.file("\(deviceFolder(box, u2))/data/b.bin", bytes: 50_000)
        // Hors du dossier des appareils : ne doit pas compter.
        try box.file("Library/Developer/CoreSimulator/Other/c.bin", bytes: 900_000)

        let result = scan(fake(.finished(stdout: listJSON([u1, u2]))), home: box.root)
        #expect(result.status == .ok)
        #expect(result.devices.map(\.device.udid) == [u1, u2])
        let expected1 = CleanupService.allocatedSize(of: box.root.appendingPathComponent(deviceFolder(box, u1)))
        let expected2 = CleanupService.allocatedSize(of: box.root.appendingPathComponent(deviceFolder(box, u2)))
        #expect(result.devices[0].size == expected1)
        #expect(result.devices[1].size == expected2)
        #expect(expected1 >= 400_000 && expected1 < 600_000)
        #expect(expected2 >= 50_000 && expected2 < 150_000)
    }

    @Test func aMissingFolderWeighsZero() throws {
        let box = try Sandbox()
        let result = scan(fake(.finished(stdout: listJSON([u1]))), home: box.root)
        #expect(result.status == .ok)
        #expect(result.devices.first?.size == 0)
    }

    @Test func theDataPathAndDataPathSizeOfTheToolAreNeverUsed() throws {
        let box = try Sandbox()
        let json = """
        {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
          {"udid": "\(u1)", "name": "X", "state": "Shutdown", "dataPath": "/somewhere/else/data", "dataPathSize": 999999999999}
        ]}}
        """
        try box.file("\(deviceFolder(box, u1))/data/a.bin", bytes: 100_000)
        let result = scan(fake(.finished(stdout: json)), home: box.root)
        let size = try #require(result.devices.first?.size)
        #expect(size < 1_000_000)
    }

    @Test func sparseFileCountsAllocatedSpaceNotApparentSize() throws {
        let box = try Sandbox()
        let folder = box.root.appendingPathComponent(deviceFolder(box, u1)).appendingPathComponent("data")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("sparse.img")
        #expect(FileManager.default.createFile(atPath: file.path, contents: nil))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 1_000_000_000)
        try handle.close()

        // Taille apparente : 1 Go.
        let apparent = try #require(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? UInt64)
        #expect(apparent == 1_000_000_000)
        // Taille allouée : très petite (le test suppose un volume APFS pour le dossier temporaire).
        let allocated = CleanupService.allocatedSize(of: file)
        #expect(allocated < 50_000_000, "espace alloué \(allocated) octets")

        let result = scan(fake(.finished(stdout: listJSON([u1]))), home: box.root)
        let size = try #require(result.devices.first?.size)
        #expect(size < 50_000_000)
    }

    // MARK: Annulation

    @Test func cancellationStopsTheSizeLoop() throws {
        let box = try Sandbox()
        let udids = (1...5).map { "00000000-0000-4000-8000-00000000000\($0)" }
        var polls = 0
        let result = scan(fake(.finished(stdout: listJSON(udids))), home: box.root, isCancelled: { polls += 1; return polls > 2 })
        #expect(result.cancelled)
        #expect(result.devices.count == 2)
        #expect(polls == 3, "une fois annulé, plus aucun dossier n'est mesuré")
    }

    @Test func notCancelledMeasuresEveryDevice() throws {
        let box = try Sandbox()
        let udids = (1...3).map { "00000000-0000-4000-8000-00000000000\($0)" }
        let result = scan(fake(.finished(stdout: listJSON(udids))), home: box.root)
        #expect(result.devices.count == 3)
        #expect(!result.cancelled)
    }
}
