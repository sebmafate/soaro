import Foundation
import Testing
@testable import Soaro

/// La lecture de la liste (une commande, sans tailles) est séparée de la mesure des dossiers.
@Suite struct SimulatorListingTests {
    private let u1 = "00000000-0000-4000-8000-000000000001"
    private let u2 = "00000000-0000-4000-8000-000000000002"

    private func listJSON(_ udids: [String]) -> String {
        let entries = udids.map { "{\"udid\": \"\($0)\", \"name\": \"Device \($0.suffix(1))\", \"state\": \"Shutdown\"}" }
        return "{\"devices\": {\"com.apple.CoreSimulator.SimRuntime.iOS-26-2\": [\(entries.joined(separator: ","))]}}"
    }

    private func fake(_ outcome: CommandOutcome) -> FakeCommandRunner {
        let fake = FakeCommandRunner()
        fake.script(outcome, executable: "/usr/bin/xcrun", arguments: SimulatorScanner.listArguments)
        return fake
    }

    private var failures: [(String, CommandOutcome, SimulatorScan.Status)] {
        [("failed to launch", .failedToLaunch, .toolNotFound),
         ("refused", .refused(.shell), .commandFailed(exitCode: nil)),
         ("timed out", .timedOut, .timedOut),
         ("non-zero exit", .finished(exit: 72, stdout: "x"), .commandFailed(exitCode: 72)),
         ("signalled", .finished(exit: 11, termination: .signaled), .commandFailed(exitCode: nil)),
         ("truncated", .finished(stdout: "{", truncated: true), .outputNotReadable),
         ("malformed", .finished(stdout: "not json"), .outputNotReadable)]
    }

    @Test func listingGivesTheSameStatusAsScanForEachFailure() throws {
        let box = try Sandbox()
        for (label, outcome, expected) in failures {
            let listing = SimulatorScanner.list(runner: fake(outcome), xcrunPath: "/usr/bin/xcrun")
            let scan = SimulatorScanner.scan(runner: fake(outcome), xcrunPath: "/usr/bin/xcrun", home: box.root)
            #expect(listing.status == expected, "\(label)")
            #expect(listing.status == scan.status, "\(label)")
            #expect(listing.devices.isEmpty, "\(label)")
        }
    }

    @Test func toolNotFoundRunsNothing() {
        let runner = FakeCommandRunner()
        let listing = SimulatorScanner.list(runner: runner, xcrunPath: nil)
        #expect(listing.status == .toolNotFound)
        #expect(runner.calls.isEmpty)
    }

    @Test func emptyListIsOkAndEmpty() {
        let listing = SimulatorScanner.list(runner: fake(.finished(stdout: "{\"devices\": {}}")), xcrunPath: "/usr/bin/xcrun")
        #expect(listing.status == .ok)
        #expect(listing.devices.isEmpty)
    }

    @Test func listingParsesDevicesWithOneCallAndTheDocumentedLimits() {
        let runner = fake(.finished(stdout: listJSON([u1, u2])))
        let listing = SimulatorScanner.list(runner: runner, xcrunPath: "/usr/bin/xcrun")
        #expect(listing.status == .ok)
        #expect(listing.devices.map(\.udid) == [u1, u2])
        #expect(runner.calls == [.init(executable: "/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "-j"],
                                       timeLimit: 60, outputLimit: 8 * 1024 * 1024)])
    }

    @Test func listingNeverReadsAFolder() throws {
        let url = RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Cleanup/SimulatorScanner.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        let start = try #require(text.range(of: "static func list("))
        let rest = text[start.upperBound...]
        let end = rest.range(of: "\n    }\n")?.lowerBound ?? rest.endIndex
        let body = String(rest[..<end])
        #expect(!body.contains("allocatedSize"))
        #expect(!body.contains("home"))
    }

    // MARK: Dossier d'un appareil

    @Test func deviceFolderIsBuiltUnderTheDevicesFolderOnly() {
        let home = URL(fileURLWithPath: "/home-fake/user-x")
        #expect(SimulatorScanner.deviceFolder(udid: u1, home: home)?.path
                == "/home-fake/user-x/Library/Developer/CoreSimulator/Devices/\(u1)")
    }

    @Test func deviceFolderRefusesAnInvalidUDID() {
        let home = URL(fileURLWithPath: "/home-fake/user-x")
        for bad in ["", "..", "../x", "00000000-0000-4000-8000-00000000000", u1 + "/..", "/" + u1, "not-a-udid"] {
            #expect(SimulatorScanner.deviceFolder(udid: bad, home: home) == nil, "«\(bad)»")
        }
    }
}
