import Foundation
import Testing
@testable import Soaro

@Suite struct AdviceParsingTests {
    @Test func parsesRealBattlimitOutput() {
        let output = """
        Battery level limits:
        (
                {
                Terminated = 0;
                chargeSocLimitDrain = 1;
                chargeSocLimitOwner = 73251;
                chargeSocLimitReason = optimizedChargeLimit;
                chargeSocLimitSoc = 80;
            },
                {
                chargeSocLimitOwner = 0;
                chargeSocLimitSoc = 90;
            }
        )
        """
        #expect(AdviceParsing.chargeLimit(output) == 80)
        #expect(AdviceParsing.chargeLimit("Battery level limits:\n(\n)") == nil)
        #expect(AdviceParsing.chargeLimit("chargeSocLimitSoc = 250;") == nil)      // valeur aberrante ignorée
    }

    @Test func findsOnlyThirdPartySleepBlockers() {
        // Extrait réel de `pmset -g assertions`, plus une app tierce.
        let output = """
        Listed by owning process:
           pid 471(bluetoothd): [0x0005753a00018c6a] 00:00:13 PreventUserIdleSystemSleep named: "com.apple.BTStack"
           pid 478(WindowServer): [0x00053e9b00099fa4] 00:00:00 UserIsActive named: "com.apple.iohideventsystem.queue.tickle"
           pid 422(powerd): [0x00053e8c00019f58] 03:53:31 PreventUserIdleSystemSleep named: "Powerd - Prevent sleep while display is on"
           pid 422(powerd): [0x0001f07f0008978b] 75:36:12 ExternalMedia named: "com.apple.powermanagement.externalmediamounted"
           pid 9001(Amphetamine): [0x0001f07f00089700] 05:10:02 PreventUserIdleSystemSleep named: "Amphetamine session"
           pid 9002(Google Chrome): [0x0001f07f00089701] 00:02:00 NoIdleSleepAssertion named: "Video Wake Lock"
           pid 9003(Zoom): [0x0001f07f00089702] 01:00:00 PreventUserIdleDisplaySleep named: "écran seulement"
        """
        let blockers = AdviceParsing.sleepBlockers(output)
        #expect(blockers == [
            SleepBlocker(name: "Amphetamine", seconds: 5 * 3_600 + 10 * 60 + 2),
            SleepBlocker(name: "Google Chrome", seconds: 120),
        ])
    }

    @Test func extractsPendingMacOSVersion() {
        #expect(AdviceParsing.pendingUpdateVersion(["AutoInstallProductKeys": ["MSU_UPDATE_26B123_patch_27.2_minor"]]) == "27.2")
        #expect(AdviceParsing.pendingUpdateVersion(["AutoInstallProductKeys": ["MSU_UPDATE_25B5042k_full_26.1_minor", "MSU_UPDATE_26B123_patch_27.2_minor"]]) == "27.2")
        #expect(AdviceParsing.pendingUpdateVersion(["RecommendedUpdates": [
            ["Display Name": "Safari", "Display Version": "19.0"],
            ["Display Name": "macOS Golden Gate", "Display Version": "27.3"],
        ]]) == "27.3")
        #expect(AdviceParsing.pendingUpdateVersion([:]) == nil)
        #expect(AdviceParsing.pendingUpdateVersion(["AutoInstallProductKeys": ["n'importe quoi"]]) == nil)
    }

    @Test func detectsTimeMachineConfiguration() {
        #expect(!AdviceParsing.timeMachineConfigured("tmutil: No destinations configured."))
        #expect(AdviceParsing.timeMachineConfigured("====\nName          : Sauvegarde\nKind          : Local\nID            : 1234-ABCD"))
        let old = Date(timeIntervalSince1970: 1_000), recent = Date(timeIntervalSince1970: 9_000)
        #expect(AdviceParsing.lastBackup(["Destinations": [["SnapshotDates": [old]], ["SnapshotDates": [recent, old]]]]) == recent)
        #expect(AdviceParsing.lastBackup(["PreferencesVersion": 6]) == nil)
    }

    @Test func comparesVersionsNumerically() {
        #expect(AdviceEngine.isVersion("27.2", newerThan: "27.0.1"))
        #expect(AdviceEngine.isVersion("27.10", newerThan: "27.9"))          // pas une comparaison de texte
        #expect(!AdviceEngine.isVersion("27.0.1", newerThan: "27.0.1"))
        #expect(!AdviceEngine.isVersion("26.3", newerThan: "27.0"))
        #expect(!AdviceEngine.isVersion("", newerThan: "27.0"))
    }
}

@Suite struct AdviceEngineTests {
    private let GB: UInt64 = 1_000_000_000

    private func battery(_ percent: Double, plugged: Bool, charging: Bool = false) -> BatteryStats {
        BatteryStats(percent: percent, isCharging: charging, isPluggedIn: plugged, isFullyCharged: false, minutesRemaining: nil, cycleCount: 1,
                     health: 1, designCapacity: nil, maxCapacity: nil, temperature: nil, batteryPower: nil, systemPower: nil, adapterWatts: nil)
    }

    private func ids(_ input: AdviceInput) -> [String] { AdviceEngine.evaluate(input).map(\.id) }

    private var quiet: AdviceInput {
        AdviceInput(facts: SystemFacts(), battery: battery(90, plugged: true, charging: true), disk: DiskStats(total: 1_000 * GB, available: 500 * GB), osVersion: "27.0.1")
    }

    @Test func healthySystemGetsNoAdvice() {
        #expect(ids(quiet).isEmpty)
    }

    @Test func explainsChargeLimitOnlyWhenItIsTheReason() {
        var input = quiet
        input.facts.chargeLimit = 80
        input.battery = battery(80, plugged: true)
        #expect(ids(input) == ["battery.chargeLimit"])

        input.battery = battery(55, plugged: true, charging: true)      // en charge : la limite n'explique rien
        #expect(ids(input).isEmpty)
        input.battery = battery(80, plugged: false)                     // sur batterie : idem
        #expect(ids(input).isEmpty)
        input.battery = battery(80, plugged: true)
        input.facts.chargeLimit = 100
        #expect(ids(input).isEmpty)
    }

    @Test func lowPowerModeSuggestedOnlyOnLowBattery() {
        var input = quiet
        input.battery = battery(25, plugged: false)
        #expect(ids(input) == ["battery.lowPowerMode"])
        input.facts.lowPowerMode = true
        #expect(ids(input).isEmpty)
        input.facts.lowPowerMode = false
        input.battery = battery(25, plugged: true, charging: true)
        #expect(ids(input).isEmpty)
    }

    @Test func sleepBlockerNeedsTwoHours() {
        var input = quiet
        input.facts.sleepBlockers = [SleepBlocker(name: "Amphetamine", seconds: 3_600)]
        #expect(ids(input).isEmpty)
        input.facts.sleepBlockers = [SleepBlocker(name: "Amphetamine", seconds: 5 * 3_600), SleepBlocker(name: "Zoom", seconds: 60)]
        let advice = AdviceEngine.evaluate(input)
        #expect(advice.map(\.id) == ["sleep.blocked"])
        #expect(advice[0].title == "Amphetamine is preventing sleep")
        #expect(!advice[0].detail.contains("Zoom"))
    }

    @Test func manyStartupAgentsPointToTheStartupTool() {
        var input = quiet
        input.facts.enabledAgentCount = 11
        #expect(ids(input).isEmpty)
        input.facts.enabledAgentCount = 28
        let advice = AdviceEngine.evaluate(input)
        #expect(advice.first?.action == .showStartupItems)
        #expect(advice.first?.title == "Programs launching at login: 28")
    }

    @Test func spotlightIndexingIsExplainedWithoutAction() {
        var input = quiet
        input.processes = [
            ProcessGroup(id: "mds_stores", name: "mds_stores", cpu: 45, memory: 0, pids: [1], appPath: nil),
            ProcessGroup(id: "mdworker_shared", name: "mdworker_shared", cpu: 20, memory: 0, pids: [2], appPath: nil),
            ProcessGroup(id: "Safari", name: "Safari", cpu: 300, memory: 0, pids: [3], appPath: nil),
        ]
        let advice = AdviceEngine.evaluate(input)
        #expect(advice.map(\.id) == ["spotlight.indexing"])
        #expect(advice[0].action == nil)
        input.processes[0].cpu = 5
        #expect(ids(input).isEmpty)
    }

    @Test func storageAdviceDependsOnTrashSetting() {
        var input = quiet
        input.disk = DiskStats(total: 1_000 * GB, available: 140 * GB)
        #expect(ids(input) == ["storage.optimize"])
        input.facts.autoEmptyTrash = false
        #expect(ids(input) == ["storage.autoTrash"])
        input.disk = DiskStats(total: 1_000 * GB, available: 400 * GB)
        #expect(ids(input).isEmpty)
    }

    @Test func pendingUpdateOnlyIfNewerThanInstalled() {
        var input = quiet
        input.facts.pendingUpdateVersion = "27.2"
        #expect(ids(input) == ["update.pending.27.2"])
        input.osVersion = "27.2"                       // déjà installée : la clé traîne dans les préférences
        #expect(ids(input).isEmpty)
    }

    @Test func backupAdvice() {
        var input = quiet
        input.facts.timeMachineConfigured = false
        #expect(ids(input) == ["backup.none"])
        input.facts.timeMachineConfigured = true
        input.facts.lastBackup = input.now.addingTimeInterval(-20 * 86_400)
        #expect(AdviceEngine.evaluate(input).first?.title == "Last backup 20 days ago")
        input.facts.lastBackup = input.now.addingTimeInterval(-2 * 86_400)
        #expect(ids(input).isEmpty)
        input.facts.lastBackup = nil                   // configuré mais date illisible : on ne conclut rien
        #expect(ids(input).isEmpty)
    }

    @Test func everySettingsLinkIsAWellFormedURL() {
        for pane in [SettingsPane.battery, SettingsPane.softwareUpdate, SettingsPane.storage, SettingsPane.timeMachine] {
            #expect(URL(string: pane)?.scheme == "x-apple.systempreferences", "\(pane)")
        }
    }
}

@Suite struct AdviceDismissalTests {
    @MainActor @Test func dismissedAdviceStaysHiddenUntilRestored() {
        let key = "dismissedAdvice"
        let saved = UserDefaults.standard.stringArray(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)

        let state = AppState(history: nil)
        let item = Advice(id: "test.advice", systemImage: "leaf", title: "t", detail: "d", action: nil, actionLabel: nil)
        state.dismissAdvice(item)
        #expect(UserDefaults.standard.stringArray(forKey: key) == ["test.advice"])
        #expect(state.dismissedAdviceCount == 1)
        state.restoreDismissedAdvice()
        #expect(UserDefaults.standard.stringArray(forKey: key) == nil)
        #expect(state.dismissedAdviceCount == 0)
    }
}
