import Foundation
import Testing
@testable import Soaro

/// Mise en forme de la section « iOS Simulators » de `--scan` : fonction pure, locale et instant explicites.
@Suite struct SimulatorReportTests {
    private let now = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!
    private let locale = Locale(identifier: "en_US")
    private let iosA = "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
    private let iosB = "com.apple.CoreSimulator.SimRuntime.iOS-18-0"

    private func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    private func sized(_ n: Int, name: String, days: Double?, size: UInt64, model: String? = nil, runtime: String? = nil,
                       state: String = "Shutdown", available: Bool = true) -> SizedSimulator {
        let runtimeID = runtime ?? iosA
        return SizedSimulator(
            device: SimulatorDevice(udid: String(format: "00000000-0000-4000-8000-%012d", n), name: name,
                                    modelIdentifier: model ?? "model-\(n)", runtimeIdentifier: runtimeID,
                                    runtimeName: SimulatorScanner.runtimeName(runtimeID), state: state,
                                    isAvailable: available, lastUsed: days.map(ago)),
            size: size)
    }

    private func report(_ scan: SimulatorScan, limit: Int = 60) -> [String] {
        let suggestions = DeviceSuggestions.suggest(scan.devices, now: now, limitDays: limit)
        return SimulatorReport.lines(scan: scan, suggestions: suggestions, locale: locale, limitDays: limit)
    }

    private func line(containing text: String, in lines: [String]) -> String? { lines.first { $0.contains(text) } }

    // MARK: Cas normal

    @Test func normalReportHasHeaderDeviceLinesFooterAndSummary() {
        let devices = [
            sized(1, name: "Phone Old", days: 100, size: 3_000_000_000),
            sized(2, name: "Phone New", days: 3, size: 500_000_000, model: "m"),
            sized(3, name: "Phone Copy", days: 20, size: 800_000_000, model: "m"),
            sized(4, name: "Tiny", days: 1, size: 5_000_000),
        ]
        let lines = report(SimulatorScan(status: .ok, devices: devices.map { $0 }))

        #expect(lines.first == "== iOS Simulators")
        let header = lines[1]
        #expect(header.contains("4 devices"))
        #expect(header.contains(Format.fileBytes(4_305_000_000, locale: locale)))
        #expect(header.contains("60 d"))
        #expect(header.contains("100 MB"))

        let old = line(containing: "Phone Old", in: lines)
        #expect(old?.contains(Format.fileBytes(3_000_000_000, locale: locale)) == true)
        #expect(old?.contains("iOS 26.2") == true)
        #expect(old?.contains("00000000-0000-4000-8000-000000000001") == true)
        #expect(old?.contains("100 d") == true)
        #expect(old?.contains("pre-selected") == true)
        #expect(old?.contains("inactive for 100 d") == true)
        #expect(old?.contains("older copy") == false)

        let copy = line(containing: "Phone Copy", in: lines)
        #expect(copy?.contains("older copy") == true)
        #expect(copy?.contains("inactive for") == false)
        #expect(line(containing: "Phone New", in: lines)?.contains("pre-selected") == false)

        #expect(line(containing: "Tiny", in: lines) == nil, "un petit appareil n'est pas listé")
        #expect(lines.contains("1 small device (\(Format.fileBytes(5_000_000, locale: locale))) not listed"))
        #expect(lines.contains("Pre-selected: 2 · \(Format.fileBytes(3_800_000_000, locale: locale))"))
    }

    @Test func devicesAreListedBySizeDescending() {
        let lines = report(SimulatorScan(status: .ok, devices: [
            sized(1, name: "Small One", days: 1, size: 200_000_000),
            sized(2, name: "Big One", days: 1, size: 900_000_000),
        ]))
        let big = lines.firstIndex { $0.contains("Big One") }
        let small = lines.firstIndex { $0.contains("Small One") }
        #expect(big != nil && small != nil && big! < small!)
    }

    @Test func pluralFooterAndNothingPreSelected() {
        let lines = report(SimulatorScan(status: .ok, devices: [
            sized(1, name: "A", days: 1, size: 1_000), sized(2, name: "B", days: 1, size: 2_000),
        ]))
        #expect(lines.contains { $0.hasPrefix("2 small devices (") && $0.hasSuffix(") not listed") })
        #expect(lines.contains("Pre-selected: 0 · \(Format.fileBytes(0, locale: locale))"))
    }

    // MARK: Cas particuliers

    @Test func runningAndUnavailableDevicesAreFlaggedAndNotPreSelected() {
        let lines = report(SimulatorScan(status: .ok, devices: [
            sized(1, name: "Live", days: 300, size: 600_000_000, state: "Booted"),
            sized(2, name: "Broken", days: 2, size: 700_000_000, available: false),
        ]))
        let live = line(containing: "Live", in: lines)
        #expect(live?.contains("running") == true)
        #expect(live?.contains("pre-selected") == false)
        let broken = line(containing: "Broken", in: lines)
        #expect(broken?.contains("unavailable") == true)
        #expect(broken?.contains("running") == false)
        #expect(line(containing: "Live", in: lines)?.contains("unavailable") == false)
    }

    @Test func anUnknownDateIsPrintedAsUnknownAndNeverPreSelected() {
        let lines = report(SimulatorScan(status: .ok, devices: [sized(1, name: "Undated", days: nil, size: 600_000_000)]))
        let row = line(containing: "Undated", in: lines)
        #expect(row?.contains("last used unknown") == true)
        #expect(row?.contains("pre-selected") == false)
    }

    @Test func noDeviceStillPrintsHeaderAndSummary() {
        let lines = report(SimulatorScan(status: .ok, devices: []))
        #expect(lines.first == "== iOS Simulators")
        #expect(lines[1].contains("0 devices"))
        #expect(lines.contains("Pre-selected: 0 · \(Format.fileBytes(0, locale: locale))"))
        #expect(!lines.contains { $0.contains("small device") }, "pas de pied de page s'il n'y a pas de petit appareil")
    }

    @Test func theLimitUsedIsPrinted() {
        let devices = [sized(1, name: "Mid", days: 45, size: 600_000_000)]
        let at30 = report(SimulatorScan(status: .ok, devices: devices), limit: 30)
        #expect(at30[1].contains("30 d"))
        #expect(line(containing: "Mid", in: at30)?.contains("inactive for 45 d") == true)
        let at60 = report(SimulatorScan(status: .ok, devices: devices), limit: 60)
        #expect(line(containing: "Mid", in: at60)?.contains("pre-selected") == false)
    }

    // MARK: Échecs : une seule ligne neutre, distincte

    @Test func eachFailureStatusIsOneDistinctNeutralLine() {
        let statuses: [(SimulatorScan.Status, String)] = [
            (.toolNotFound, "xcrun not found"),
            (.commandFailed(exitCode: 72), "command failed (exit code 72)"),
            (.commandFailed(exitCode: nil), "command failed"),
            (.timedOut, "did not answer within 60 s"),
            (.outputNotReadable, "output not readable"),
        ]
        var seen = Set<String>()
        for (status, expected) in statuses {
            let lines = report(SimulatorScan(status: status))
            #expect(lines.count == 2, "en-tête + une ligne")
            #expect(lines.first == "== iOS Simulators")
            #expect(lines[1].contains(expected), "\(status)")
            #expect(!lines[1].contains("Pre-selected"))
            seen.insert(lines[1])
        }
        #expect(seen.count == statuses.count)
    }

    // MARK: Confidentialité de la sortie

    @Test func noLineContainsAUsersPath() {
        let devices = [sized(1, name: "Phone", days: 100, size: 600_000_000), sized(2, name: "Tiny", days: 100, size: 1)]
        var all = report(SimulatorScan(status: .ok, devices: devices))
        for status in [SimulatorScan.Status.toolNotFound, .commandFailed(exitCode: 1), .timedOut, .outputNotReadable] {
            all += report(SimulatorScan(status: status))
        }
        #expect(all.allSatisfy { !$0.contains("/Users/") })
    }
}
