import Foundation
import Testing
@testable import Soaro

/// « Select all » dans les modèles : un groupe à la fois, jamais une ligne en cours d'exécution, rien pendant une suppression.
/// Bac à sable `.soaro-test-` (jamais le vrai `~/.android`), faux lanceur, mesure écrite à la main ; rien n'est supprimé ici.
@MainActor
@Suite(.serialized) struct SimulatorsSelectAllTests {
    static let u1 = "00000000-0000-4000-8000-000000000001"
    static let u2 = "00000000-0000-4000-8000-000000000002"
    static let u3 = "00000000-0000-4000-8000-000000000003"
    static let big: UInt64 = 500_000_000
    let now = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!
    let present = SimulatorToolDetection(devicesFolderExists: true, simctlPath: "/fake/simctl")
    let gate = SimulatorDeletionGate()

    /// Trois simulateurs (le troisième en cours d'exécution) et trois AVD (le troisième en cours d'exécution).
    func fixture(demo: Bool = false, gated: Bool = false, androidPreselects: Bool = false) throws -> (SimulatorsModel, Sandbox, ScriptedMeasure) {
        let box = try Sandbox(insideHome: true)
        try box.dir("Library/Android/sdk")
        for name in ["Test_Phone_A", "Test_Tablet_B", "Test_Watch_C"] {
            try box.dir(".android/avd/\(name).avd")
            try box.write(".android/avd/\(name).ini", "path.rel=avd/\(name).avd\n")
            try box.write(".android/avd/\(name).avd/config.ini", "avd.ini.displayname=\(name.replacingOccurrences(of: "_", with: " "))\n")
        }
        let fake = FakeCommandRunner()
        let list = SimulatorRemovalOneDeviceTests.listJSON([(Self.u1, "Test iPhone 1", "Shutdown"), (Self.u2, "Test iPhone 2", "Shutdown"),
                                                            (Self.u3, "Test iPhone 3", "Booted")])
        fake.script(.finished(stdout: list), executable: "/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "-j"])
        fake.script(.finished(stdout: "qemu-system-aarch64 -avd Test_Watch_C -netdelay none"), executable: "/bin/ps", arguments: ["-axww", "-o", "command="])
        var sizes: [String: UInt64] = [:]
        for key in [Self.u1, Self.u2, Self.u3, "Test_Phone_A.avd", "Test_Tablet_B.avd", "Test_Watch_C.avd"] { sizes[key] = Self.big }
        let measure = ScriptedMeasure(sizes, gated: gated)
        let detection = present
        let model = SimulatorsModel(runner: fake, detect: { detection },
                                    locateTool: { $0 == ToolLocator.processListCandidates ? "/bin/ps" : "/usr/bin/xcrun" },
                                    environment: [:], home: box.root, now: { self.now },
                                    measure: { measure.measure($0) }, demo: demo,
                                    confirm: { _, _, _, _ in false }, deletionGate: gate, androidPreselects: androidPreselects, notify: { _ in })
        return (model, box, measure)
    }

    func scanned(demo: Bool = false) async throws -> (SimulatorsModel, Sandbox) {
        let (model, box, _) = try fixture(demo: demo)
        model.scan()
        await model.scanTask?.value
        return (model, box)
    }

    // MARK: Un groupe à la fois

    @Test func selectAllInTheIosGroupChecksTheNonRunningIosRowsOnly() async throws {
        let (m, _) = try await scanned()
        #expect(m.rows.count == 3 && m.androidRows.count == 3)
        m.setAllSelected(true, group: .ios)
        #expect(m.selected == [Self.u1, Self.u2], "le simulateur démarré reste décoché")
        #expect(m.androidSelected.isEmpty, "Android n'est pas touché")
        #expect(m.selectAllState(.ios) == .all)
        #expect(m.selectAllState(.android) == .none)
    }

    @Test func selectAllInTheAndroidGroupChecksTheNonRunningAvdsOnlyAndNeverTouchesIos() async throws {
        let (m, _) = try await scanned()
        let ios = try #require(m.rows.first { !$0.isRunning })
        m.toggle(ios)
        m.setAllSelected(true, group: .android)
        #expect(m.androidSelected == ["Test_Phone_A", "Test_Tablet_B"], "l'AVD en cours d'exécution reste décoché")
        #expect(m.selected == [ios.device.device.udid], "iOS n'est pas touché")
        #expect(m.selectAllState(.android) == .all)
        #expect(m.selectAllState(.ios) == .some)
    }

    @Test func deselectAllClearsOnlyThatGroup() async throws {
        let (m, _) = try await scanned()
        m.setAllSelected(true, group: .ios)
        m.setAllSelected(true, group: .android)
        m.setAllSelected(false, group: .android)
        #expect(m.androidSelected.isEmpty)
        #expect(m.selected == [Self.u1, Self.u2])
        m.setAllSelected(false, group: .ios)
        #expect(m.selected.isEmpty)
    }

    @Test func aClickFollowsTheTriStateRuleNoneSomeAll() async throws {
        let (m, _) = try await scanned()
        #expect(m.selectAllState(.android) == .none)
        m.toggleAll(.android)
        #expect(m.selectAllState(.android) == .all, "aucune : tout cocher")
        m.toggleAll(.android)
        #expect(m.selectAllState(.android) == .none, "tout : tout décocher")
        let one = try #require(m.androidRows.first { !$0.isRunning })
        m.toggle(one)
        #expect(m.selectAllState(.android) == .some)
        m.toggleAll(.android)
        #expect(m.selectAllState(.android) == .all, "mixte : tout cocher")
    }

    @Test func theStateIgnoresRunningRowsSoAllSelectableRowsCheckedIsAll() async throws {
        let (m, _) = try await scanned()
        #expect(m.selectableCount(.ios) == 2 && m.selectableCount(.android) == 2, "les lignes en cours d'exécution ne comptent pas")
        m.setAllSelected(true, group: .ios)
        #expect(m.selectedSelectableCount(.ios) == 2)
        #expect(m.selectAllState(.ios) == .all)
    }

    @Test func aRunningRowIsNeverCheckedEvenWhenAskedTwice() async throws {
        let (m, _) = try await scanned()
        m.setAllSelected(true, group: .ios)
        m.setAllSelected(true, group: .ios)
        m.setAllSelected(true, group: .android)
        #expect(!m.selected.contains(Self.u3) && !m.androidSelected.contains("Test_Watch_C"))
    }

    @Test func anInactiveRunningAvdIsNeverCheckedAndSelectAllAndDeselectAllLeaveItAsItIsAndTheStateIgnoresIt() async throws {
        // Pré-sélection allumée dans ce test seulement : l'AVD en cours d'exécution est inactif (la règle le suggérerait s'il ne tournait pas).
        let (m, box, _) = try fixture(androidPreselects: true)
        for name in ["Test_Phone_A", "Test_Tablet_B", "Test_Watch_C"] {
            let file = box.root.appendingPathComponent(".android/avd/\(name).avd/userdata-qemu.img")
            try Data(count: 3).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-90 * 86_400)], ofItemAtPath: file.path)
        }
        m.scan()
        await m.scanTask?.value
        let running = try #require(m.androidRows.first { $0.device.device.name == "Test_Watch_C" })
        #expect(running.isRunning)
        #expect(m.androidSelected == ["Test_Phone_A", "Test_Tablet_B"], "la pré-sélection coche les inactifs qui ne tournent pas, jamais celui qui tourne")
        #expect(m.selectAllState(.android) == .all, "l'état ignore la ligne en cours d'exécution")

        m.setAllSelected(true, group: .android)
        #expect(m.androidSelected == ["Test_Phone_A", "Test_Tablet_B"], "tout cocher la laisse décochée")
        #expect(m.selectAllState(.android) == .all)
        m.setAllSelected(false, group: .android)
        #expect(m.androidSelected.isEmpty && m.selectAllState(.android) == .none)
        m.toggle(running)
        #expect(m.androidSelected.isEmpty, "et elle ne se coche pas à la main non plus")
    }

    // MARK: Totaux, Delete, limite

    @Test func theCountAndSizeFollowAndDeleteStaysGatedByItsOwnRules() async throws {
        let (m, _) = try await scanned()
        #expect(!m.canDelete)
        m.setAllSelected(true, group: .ios)
        #expect(m.selectedCount == 2 && m.selectedSize == 2 * Self.big)
        #expect(m.canDelete)
        m.setAllSelected(true, group: .android)
        #expect(m.selectedCount == 4 && m.selectedSize == 4 * Self.big)
        m.setAllSelected(false, group: .ios)
        m.setAllSelected(false, group: .android)
        #expect(m.selectedCount == 0 && !m.canDelete)
    }

    @Test func selectAllWorksWhileSizesAreBeingMeasuredButDeleteWaits() async throws {
        let (m, _, gated) = try fixture(gated: true)
        m.scan()
        await gated.started.wait()                       // la première mesure est en cours
        #expect(m.isMeasuring)
        m.setAllSelected(true, group: .ios)
        #expect(m.selected.count == 2, "la sélection marche pendant la mesure, comme `toggle`")
        #expect(!m.canDelete, "Delete attend la fin des mesures")
        for _ in 0..<12 { gated.release.signal() }
        await m.scanTask?.value
    }

    @Test func aLimitChangeStillReplacesTheSelectionWithTheSuggestion() async throws {
        let (m, _) = try await scanned()
        m.setAllSelected(true, group: .ios)
        m.setAllSelected(true, group: .android)
        m.setLimit(30)
        #expect(m.selected.isEmpty && m.androidSelected.isEmpty, "aucune ligne n'a de date : la suggestion est vide, elle remplace tout")
    }

    // MARK: Rien pendant une suppression

    @Test func selectAllIsIgnoredWhileADeletionRunsAndTheCheckboxIsDisabled() async throws {
        let (m, _) = try await scanned()
        m.setAllSelected(true, group: .ios)
        #expect(m.canSelectAll(.ios) && m.canSelectAll(.android))
        #expect(gate.begin(), "un lot de suppression tourne (ici ou ailleurs)")
        #expect(m.isDeleting)
        #expect(!m.canSelectAll(.ios) && !m.canSelectAll(.android))
        m.setAllSelected(false, group: .ios)
        m.setAllSelected(true, group: .android)
        m.toggleAll(.ios)
        #expect(m.selected == [Self.u1, Self.u2] && m.androidSelected.isEmpty, "rien n'a changé")
        gate.end()
        m.setAllSelected(false, group: .ios)
        #expect(m.selected.isEmpty)
    }

    @Test func aGroupWithoutAnySelectableRowHasADisabledCheckbox() async throws {
        let (m, _) = try await scanned()
        #expect(m.canSelectAll(.ios))
        let nothing = SimulatorsModel(runner: FakeCommandRunner(), detect: { SimulatorToolDetection(devicesFolderExists: false, simctlPath: nil) },
                                      locateTool: { _ in nil }, environment: [:], home: URL(fileURLWithPath: "/home-fake/user-x"),
                                      measure: { _ in 0 }, demo: false, confirm: { _, _, _, _ in false },
                                      deletionGate: SimulatorDeletionGate(), notify: { _ in })
        #expect(!nothing.canSelectAll(.ios) && !nothing.canSelectAll(.android))
        nothing.setAllSelected(true, group: .ios)
        #expect(nothing.selected.isEmpty)
        #expect(nothing.selectAllState(.ios) == .none)
    }

    // MARK: Démo

    @Test func selectAllWorksInDemoInMemoryOnly() async throws {
        let (m, _) = try await scanned(demo: true)
        m.setAllSelected(true, group: .ios)
        m.setAllSelected(true, group: .android)
        #expect(m.selectAllState(.ios) == .all && m.selectAllState(.android) == .all)
        #expect(m.androidSelected.count == m.selectableCount(.android))
        #expect(m.androidRows.filter(\.isRunning).allSatisfy { !m.androidSelected.contains($0.device.device.name) })
        m.setAllSelected(false, group: .ios)
        #expect(m.selected.isEmpty)
    }
}
