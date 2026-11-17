import Foundation
import Testing
@testable import Soaro

/// Section « Android emulators » de `Soaro --scan` : mise en forme pure (anglais brut, non localisé) et `Diagnostics.androidScan`
/// avec le faux lanceur, un dossier personnel de bac à sable et un environnement injecté.
@Suite(.serialized) struct AndroidEmulatorReportTests {
    private let now = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!
    private let locale = Locale(identifier: "en_US")
    private let utc = TimeZone(identifier: "UTC")!

    private func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    /// `files` : les dates de chaque fichier de diagnostic qui existe (nom, jours depuis) ; par défaut, seulement le gagnant.
    private func sized(_ name: String, display: String? = nil, version: String? = "36", days: Double?, source: String? = "userdata-qemu.img",
                       running: Bool = false, size: UInt64, files: [(String, Double)]? = nil) -> SizedAndroidDevice {
        let dates = files ?? (days.map { [(source ?? "userdata-qemu.img", $0)] } ?? [])
        return SizedAndroidDevice(
            device: AndroidDevice(name: name, displayName: display ?? name, systemVersion: version,
                                  folder: URL(fileURLWithPath: "/Users/test/.android/avd/\(name).avd"),
                                  lastUsed: days.map(ago), lastUsedSource: days == nil ? nil : source, isRunning: running,
                                  fileDates: dates.map { AndroidFileDate(file: $0.0, date: ago($0.1)) }),
            size: size)
    }

    private func report(_ scan: AndroidScan, limit: Int = 60) -> [String] {
        let suggestions = DeviceSuggestions.suggestAndroid(scan.devices, now: now, limitDays: limit)
        return AndroidEmulatorReport.lines(scan: scan, suggestions: suggestions, now: now, locale: locale, timeZone: utc)
    }

    /// La ligne qui dit quels fichiers donnent la date (les quatre de `lastUsedFiles`) : présente dès qu'un appareil est listé.
    private let countsNote = "note: the last-used date is the newest modification date among userdata-qemu.img.qcow2, userdata-qemu.img, "
        + "snapshots/default_boot/snapshot.pb, hardware-qemu.ini; the other files are shown for comparison"

    private func size(_ bytes: UInt64) -> String { Format.fileBytes(bytes, locale: locale) }

    // MARK: Mise en forme

    @Test func exactLinesForTwoListedDevicesAndOneSmallOne() {
        let sdk = AndroidSDKLocation(path: "/Users/test/Library/Android/sdk", source: .androidHome)
        let scan = AndroidScan(status: .ok, sdk: sdk, devices: [
            sized("Old_Phone_C", display: "Old Phone C", days: 90, size: 3_000_000_000,
                  files: [("hardware-qemu.ini", 200), ("emulator-user.ini", 1), ("userdata-qemu.img.qcow2", 95), ("userdata-qemu.img", 90)]),
            sized("Test_Phone_A", version: nil, days: 2, running: true, size: 1_000_000_000,
                  files: [("hardware-qemu.ini", 40), ("emulator-user.ini", 2), ("userdata-qemu.img", 2), ("cache.img.qcow2", 41)]),
            sized("Test_Tablet_B", days: nil, size: 50_000_000),
        ])
        #expect(report(scan) == [
            "== Android emulators",
            "\(size(3_000_000_000))  Old_Phone_C  Old Phone C (API 36)  last used 2026-08-18 (90 d, from userdata-qemu.img)  pre-selected: inactive",
            "    files: hardware-qemu.ini 2026-04-30 (200 d), emulator-user.ini 2026-11-15 (1 d), userdata-qemu.img.qcow2 2026-08-13 (95 d), userdata-qemu.img 2026-08-18 (90 d)",
            "\(size(1_000_000_000))  Test_Phone_A  Test_Phone_A (unknown system)  last used 2026-11-14 (2 d, from userdata-qemu.img)  running",
            "    files: hardware-qemu.ini 2026-10-07 (40 d), emulator-user.ini 2026-11-14 (2 d), userdata-qemu.img 2026-11-14 (2 d), cache.img.qcow2 2026-10-06 (41 d)",
            "1 small device (\(size(50_000_000))) not listed",
            countsNote,
            "SDK source: ANDROID_HOME",
        ])
    }

    @Test func theSkippedCountIsAlsoPrintedWhenTheListCouldNotBeRead() {
        let scan = AndroidScan(status: .couldNotRead, sdk: AndroidSDKLocation(path: "/x", source: .androidHome), devices: [], skippedCount: 2)
        #expect(report(scan) == ["== Android emulators", "could not read the Android emulators",
                                 "2 registrations skipped (folder missing, outside the home or not an AVD folder)"])
    }

    @Test func theOldDoesNotPreSelectNoteIsGoneAndTheCountingFilesAreNamedWhateverTheDevices() {
        let sdk = AndroidSDKLocation(path: "/x", source: .androidHome)
        for days in [3.0, 90.0] {
            let scan = AndroidScan(status: .ok, sdk: sdk, devices: [sized("Test_Phone_A", days: days, size: 500_000_000)])
            let lines = report(scan)
            #expect(!lines.joined(separator: "\n").contains("does not pre-select"), "la note « ne pré-sélectionne pas » a disparu")
            #expect(lines.filter { $0.hasPrefix("note:") } == [countsNote])
            #expect(!lines.joined(separator: "\n").contains("/x"))
        }
        // Rien de listé (tous petits) : pas de ligne de diagnostic, seulement le décompte des petits.
        let small = AndroidScan(status: .ok, sdk: sdk, devices: [sized("Test_Phone_A", days: 3, size: 5)])
        #expect(!report(small).contains { $0.hasPrefix("note:") })
    }

    @Test func aSkippedCountIsPrintedBeforeTheSdkSourceAndOnlyWhenNotZero() {
        let sdk = AndroidSDKLocation(path: "/x", source: .androidHome)
        let one = sized("Test_Phone_A", days: 5, size: 500_000_000)
        let lines = report(AndroidScan(status: .ok, sdk: sdk, devices: [one], skippedCount: 2))
        #expect(lines.suffix(2) == ["2 registrations skipped (folder missing, outside the home or not an AVD folder)", "SDK source: ANDROID_HOME"])
        #expect(!report(AndroidScan(status: .ok, sdk: sdk, devices: [one])).joined(separator: "\n").contains("skipped"))
        // Aucun appareil listé mais des inscriptions ignorées : c'est justement le cas à diagnostiquer.
        #expect(report(AndroidScan(status: .ok, sdk: sdk, devices: [], skippedCount: 1))
                == ["== Android emulators", "no Android virtual device",
                    "1 registration skipped (folder missing, outside the home or not an AVD folder)"])
    }

    @Test func aDeviceWithNoListedFilePrintsNoneAndNoPerFileDates() {
        let scan = AndroidScan(status: .ok, sdk: AndroidSDKLocation(path: "/x", source: .defaultLocation),
                               devices: [sized("Test_Phone_A", days: nil, size: 500_000_000)])
        #expect(report(scan) == [
            "== Android emulators",
            "\(size(500_000_000))  Test_Phone_A  Test_Phone_A (API 36)  last used unknown",
            "    files: none",
            countsNote,
            "SDK source: default",
        ])
    }

    @Test func manySmallDevicesArePluralAndTheFileSourceIsPrinted() {
        let scan = AndroidScan(status: .ok, sdk: AndroidSDKLocation(path: "/x", source: .androidSDKRoot), devices: [
            sized("Test_Phone_A", days: 5, source: "userdata-qemu.img", size: 400_000_000),
            sized("Test_Tablet_B", days: 5, size: 1), sized("Test_Tablet_C", days: 5, size: 2)])
        let lines = report(scan)
        #expect(lines[1].contains("from userdata-qemu.img"))
        #expect(lines[2] == "    files: userdata-qemu.img 2026-11-11 (5 d)")
        #expect(lines.contains("2 small devices (\(size(3))) not listed"))
    }

    @Test func linesFollowTheSuggestionOrder() {
        let scan = AndroidScan(status: .ok, sdk: AndroidSDKLocation(path: "/x", source: .androidHome), devices: [
            sized("Small_First", days: 1, size: 200_000_000), sized("Big_Second", days: 1, size: 900_000_000)])
        let lines = report(scan)
        #expect(lines[1].contains("Big_Second"))
        #expect(lines[3].contains("Small_First"))
    }

    @Test func statusLines() {
        #expect(report(AndroidScan(status: .sdkNotFound, sdk: nil, devices: [])) == ["== Android emulators", "Android SDK not found"])
        #expect(report(AndroidScan(status: .couldNotRead, sdk: AndroidSDKLocation(path: "/x", source: .androidHome), devices: []))
                == ["== Android emulators", "could not read the Android emulators"])
        #expect(report(AndroidScan(status: .ok, sdk: AndroidSDKLocation(path: "/x", source: .androidHome), devices: []))
                == ["== Android emulators", "no Android virtual device"])
    }

    @Test func noPathAndNoLocalisedKeyInTheReport() {
        let scan = AndroidScan(status: .ok, sdk: AndroidSDKLocation(path: "/Users/test/Library/Android/sdk", source: .defaultLocation),
                               devices: [sized("Test_Phone_A", days: 70, size: 500_000_000)])
        #expect(!report(scan).joined(separator: "\n").contains("/Users/test"))
    }

    // MARK: Diagnostics.androidScan

    private func makeAVD(_ box: Sandbox, _ name: String) throws {
        try box.dir(".android/avd/\(name).avd")
        try box.write(".android/avd/\(name).ini", "path.rel=avd/\(name).avd\n")
        try box.write(".android/avd/\(name).avd/config.ini", "avd.ini.displayname=\(name) display\n")
    }

    @Test func androidScanListsAndMeasuresWithTheFakeRunner() throws {
        let box = try Sandbox(insideHome: true)
        try box.dir("Library/Android/sdk")
        try makeAVD(box, "Test_Phone_A")
        try makeAVD(box, "Test_Tablet_B")
        let runner = FakeCommandRunner()
        runner.script(.finished(stdout: "emulator -avd Test_Tablet_B\n"), executable: "/bin/ps", arguments: AndroidEmulatorScanner.processListArguments)
        let measured = MeasureLog()
        let scan = Diagnostics.androidScan(runner: runner, home: box.root, environment: [:], locate: { _ in "/bin/ps" },
                                           measure: { url in measured.add(url.lastPathComponent); return 300_000_000 })
        #expect(scan.status == .ok)
        #expect(scan.sdk?.source == .defaultLocation)
        #expect(scan.devices.map(\.device.name) == ["Test_Phone_A", "Test_Tablet_B"])
        #expect(scan.devices.map(\.device.isRunning) == [false, true])
        #expect(scan.devices.map(\.size) == [300_000_000, 300_000_000])
        #expect(scan.skippedCount == 0)
        #expect(measured.names == ["Test_Phone_A.avd", "Test_Tablet_B.avd"])
        #expect(runner.calls.count == 1)
    }

    @Test func androidScanWithoutAnSdkLaunchesAndMeasuresNothing() throws {
        let box = try Sandbox(insideHome: true)
        try makeAVD(box, "Test_Phone_A")
        let runner = FakeCommandRunner()
        let measured = MeasureLog()
        let scan = Diagnostics.androidScan(runner: runner, home: box.root, environment: [:], locate: { _ in "/bin/ps" },
                                           measure: { _ in measured.add("x"); return 1 })
        #expect(scan.status == .sdkNotFound)
        #expect(runner.calls.isEmpty)
        #expect(measured.names.isEmpty)
    }

    @Test func androidScanChecksTheSdkBeforeLookingForPs() throws {
        let box = try Sandbox(insideHome: true)
        var lookups = 0
        let none = Diagnostics.androidScan(runner: FakeCommandRunner(), home: box.root, environment: [:],
                                           locate: { _ in lookups += 1; return "/bin/ps" }, measure: { _ in 1 })
        #expect(none.status == .sdkNotFound)
        #expect(lookups == 0, "sans SDK, `ps` n'est même pas cherché (comme dans le modèle)")
        try box.dir("Library/Android/sdk")
        _ = Diagnostics.androidScan(runner: FakeCommandRunner(), home: box.root, environment: [:],
                                    locate: { _ in lookups += 1; return "/bin/ps" }, measure: { _ in 1 })
        #expect(lookups == 1)
    }

    @Test func theRealRunnerIsBuiltOnlyWhereItIsAllowed() throws {
        let sources = RepositoryRoot.url().appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        var found = Set<String>()
        for file in files where try String(contentsOf: file, encoding: .utf8).contains("RealCommandRunner(") {
            found.insert(file.lastPathComponent)
        }
        #expect(found.isSubset(of: ["Diagnostics.swift", "CleanupTab.swift", "RealCommandRunner.swift"]), "\(found)")
    }
}

/// Journal des dossiers mesurés (la mesure s'exécute dans la même tâche : pas de concurrence ici).
private final class MeasureLog: @unchecked Sendable {
    private(set) var names: [String] = []
    func add(_ name: String) { names.append(name) }
}
