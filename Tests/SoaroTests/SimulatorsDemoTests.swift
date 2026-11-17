import Foundation
import Testing
@testable import Soaro

/// Mode démo (T8) : appareils inventés, aucun lancement, aucune mesure, aucune lecture de fichier.
@MainActor
@Suite struct SimulatorsDemoTests {
    let now = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!

    func demoModel(runner: CommandRunner, measure: ScriptedMeasure? = nil, detect: (() -> Void)? = nil) -> SimulatorsModel {
        let measure = measure ?? ScriptedMeasure([:])
        return SimulatorsModel(runner: runner,
                               detect: { detect?(); return SimulatorToolDetection(devicesFolderExists: false, simctlPath: nil) },
                               locateTool: { _ in nil },
                               environment: [:], home: URL(fileURLWithPath: "/home-fake/user-x"), now: { self.now },
                               measure: { measure.measure($0) }, demo: true, confirm: { _, _, _, _ in false }, notify: { _ in })
    }

    @Test func demoNeverCallsTheRunnerNorMeasuresNorDetects() async {
        let runner = FakeCommandRunner()           // un appel non prévu fait échouer le test
        let measure = ScriptedMeasure([:])
        var detections = 0
        let m = demoModel(runner: runner, measure: measure, detect: { detections += 1 })
        m.scan()
        await m.scanTask?.value
        #expect(runner.calls.isEmpty)
        #expect(measure.calls.isEmpty)
        #expect(detections == 0)
    }

    @Test func demoListArrivesAtOnceWithEverySizeKnown() {
        let m = demoModel(runner: FakeCommandRunner())
        m.scan()                                   // sans attendre : tout est déjà là
        #expect(m.phase == .listed)
        #expect(!m.isMeasuring)
        #expect(m.rows.count >= 8 && m.rows.count <= 10)
        #expect(m.rows.allSatisfy { m.size(of: $0) != nil })
        #expect(m.hiddenSmallCount >= 2, "plusieurs petits appareils pour le pied de page")
        #expect(m.hiddenSmallSize > 0)
        #expect(m.rows.map { m.size(of: $0)! } == m.rows.map { m.size(of: $0)! }.sorted(by: >), "trié par taille")
    }

    @Test func demoListContainsEachCase() {
        let m = demoModel(runner: FakeCommandRunner())
        m.scan()
        let rows = m.rows
        #expect(rows.contains { $0.isInactive && ($0.daysSinceLastUse ?? 0) > 60 }, "un appareil inactif depuis plus de 60 jours")
        let copy = rows.first { $0.isOlderCopy }
        #expect(copy != nil, "une ancienne copie")
        #expect(copy?.keptDevice?.device.name == copy?.device.device.name, "dont l'appareil gardé porte le même nom")
        #expect(rows.contains { $0.daysSinceLastUse == 0 && !$0.isRunning }, "un appareil utilisé aujourd'hui")
        #expect(rows.contains { $0.isRunning }, "un appareil en cours d'exécution")
        #expect(rows.contains { !$0.device.device.isAvailable }, "un appareil indisponible (système non installé)")
        #expect(rows.contains { $0.device.device.runtimeIdentifier.contains("watchOS") }, "un watchOS")
        #expect(rows.contains { SimulatorPresentation.systemLabel(runtimeIdentifier: $0.device.device.runtimeIdentifier).hasPrefix("visionOS") },
                "un visionOS")
        #expect(rows.contains { $0.daysSinceLastUse == nil && !$0.isRunning }, "un appareil sans date")
        #expect(m.selected.count >= 2, "des appareils pré-sélectionnés")
        #expect(!m.showsNothingToSuggest)
    }

    @Test func demoDatesAreRelativeToNow() {
        let first = DemoData.simulators(now: now)
        let later = DemoData.simulators(now: now.addingTimeInterval(400 * 86_400))
        #expect(first.map(\.device.udid) == later.map(\.device.udid))
        for (a, b) in zip(first, later) {
            #expect(a.size == b.size)
            switch (a.device.lastUsed, b.device.lastUsed) {
            case let (x?, y?): #expect(y.timeIntervalSince(x) == 400 * 86_400)
            case (nil, nil): break
            default: Issue.record("la date inconnue doit rester inconnue")
            }
        }
        // Le modèle utilise l'horloge injectée : les jours écoulés restent les mêmes quelle que soit la date « maintenant ».
        func days(at date: Date) -> [Int?] {
            let m = SimulatorsModel(runner: FakeCommandRunner(), detect: { SimulatorToolDetection(devicesFolderExists: false, simctlPath: nil) },
                                    environment: [:], home: URL(fileURLWithPath: "/home-fake/user-x"), now: { date }, demo: true, confirm: { _, _, _, _ in false }, notify: { _ in })
            m.scan()
            return m.rows.map(\.daysSinceLastUse)
        }
        #expect(days(at: now) == days(at: now.addingTimeInterval(400 * 86_400)))
    }

    @Test func demoDevicesAreMadeUp() {
        let devices = DemoData.simulators(now: now)
        for device in devices.map(\.device) {
            #expect(device.udid.hasPrefix("00000000-0000-4000-8000-0000000000"), "UDID manifestement faux : \(device.udid)")
            #expect(SimulatorScanner.isValidUDID(device.udid))
            #expect(!device.name.isEmpty)
        }
        #expect(Set(devices.map(\.device.udid)).count == devices.count)
        // Aucun UDID de démo n'est un UDID des jeux d'essai de SL7 (« 00000000-0000-4000-8000-%012d », n de 1 à 40).
        let fixtures = Set((1...40).map { String(format: "00000000-0000-4000-8000-%012d", $0) })
        #expect(fixtures.isDisjoint(with: Set(devices.map(\.device.udid))))
    }

    @Test func demoSourceHasNoRealIdentifiers() throws {
        let url = RepositoryRoot.url().appendingPathComponent("Sources/Soaro/DemoData.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        let pattern = #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
        let regex = try NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            #expect(ns.substring(with: match.range).hasPrefix("00000000-0000-4000-8000-0000000000"))
        }
        #expect(!text.contains("/Users/"))
    }

    @Test func demoModelWritesNothingAndReadsNoFile() throws {
        // Le dossier personnel de démo n'existe pas : si le modèle y touchait, il échouerait ou créerait quelque chose.
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("soaro-demo-\(UUID().uuidString)")
        let m = SimulatorsModel(runner: FakeCommandRunner(), detect: { SimulatorToolDetection(devicesFolderExists: false, simctlPath: nil) },
                                environment: [:], home: missing, now: { self.now }, demo: true, confirm: { _, _, _, _ in false }, notify: { _ in })
        m.scan()
        #expect(m.phase == .listed)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    // MARK: Android en démo (SL10 T10)

    @Test func demoAndroidAppearsAtOnceWithoutRunnerMeasureOrDetection() async {
        let runner = FakeCommandRunner()           // un appel non prévu fait échouer le test
        let measure = ScriptedMeasure([:])
        var detections = 0
        let m = demoModel(runner: runner, measure: measure, detect: { detections += 1 })
        m.scan()                                   // sans attendre : tout est déjà là
        #expect(m.androidPhase == .listed)
        #expect(m.androidMessage == nil)
        #expect(m.androidRows.allSatisfy { m.size(of: $0) != nil }, "toutes les tailles sont connues")
        await m.scanTask?.value
        #expect(runner.calls.isEmpty)
        #expect(measure.calls.isEmpty)
        #expect(detections == 0)
    }

    @Test func demoAndroidHasTheThreeCases() {
        let m = demoModel(runner: FakeCommandRunner())
        m.scan()
        #expect(m.androidRows.count == 2, "l'appareil de moins de 100 Mo est dans le pied de page")
        let inactive = m.androidRows.first { $0.isInactive }
        #expect((inactive?.daysSinceLastUse ?? 0) > 60)
        #expect(inactive.map { m.size(of: $0) ?? 0 } ?? 0 >= DeviceSuggestions.smallDeviceThreshold)
        #expect(inactive?.isPreSelected == true, "la règle le pré-sélectionnerait")
        #expect(m.androidSelected.isEmpty, "mais l'application ne pré-sélectionne pas Android avant SL11 : la démo ouvre Delete utilisable")
        let running = m.androidRows.first { $0.isRunning }
        #expect(running != nil, "un appareil en cours d'exécution")
        #expect(running.map { !m.androidSelected.contains($0.device.device.name) } == true)
        #expect(m.hiddenSmallCount == 3 + 1, "trois petits iOS et un petit Android")
        #expect(m.measuredSizeTotal == m.rows.reduce(0) { $0 + (m.size(of: $1) ?? 0) } + m.androidRows.reduce(0) { $0 + (m.size(of: $1) ?? 0) })
    }

    @Test func demoAndroidDevicesAreMadeUpAndDatesAreRelativeToNow() {
        let first = DemoData.androidEmulators(now: now)
        let later = DemoData.androidEmulators(now: now.addingTimeInterval(400 * 86_400))
        #expect(first.count == 3)
        #expect(first.map(\.device.name) == later.map(\.device.name))
        #expect(Set(first.map(\.device.name)).count == 3)
        for (a, b) in zip(first, later) {
            #expect(AndroidEmulatorScanner.isValidAVDName(a.device.name))
            if let x = a.device.lastUsed, let y = b.device.lastUsed { #expect(y.timeIntervalSince(x) == 400 * 86_400) }
            #expect(a.size == b.size)
        }
        #expect(first.filter { $0.size < DeviceSuggestions.smallDeviceThreshold }.count == 1)
        #expect(first.filter(\.device.isRunning).count == 1)
    }

    @Test func demoSourceHasNoRealAndroidPaths() throws {
        let text = try String(contentsOf: RepositoryRoot.url().appendingPathComponent("Sources/Soaro/DemoData.swift"), encoding: .utf8)
        #expect(!text.contains("/Users/") && !text.contains(".android"))
    }

    @Test func androidDeletionIsNeverOfferedInDemo() async {
        let runner = FakeCommandRunner()
        let measure = ScriptedMeasure([:])
        let confirm = RecordingConfirm(answer: true)
        let toasts = Toasts()
        let m = confirmingModel(runner: runner, measure: measure, confirm: confirm, toasts: toasts)
        m.scan()
        #expect(m.androidSelected.isEmpty, "rien d'Android n'est coché d'office")
        #expect(m.canDelete, "la démo ouvre Delete utilisable pour iOS")
        // Cocher une ligne Android (non en cours d'exécution) à la main désactive Delete : aucune confirmation, aucun effet.
        let checkable = try! #require(m.androidRows.first { !$0.isRunning })
        m.toggle(checkable)
        #expect(!m.canDelete)
        m.deleteSelected()
        #expect(confirm.asks.isEmpty, "aucune confirmation, aucun effet")
        #expect(toasts.messages.isEmpty)
        // Décochée : la suppression iOS de démo marche et ne touche pas aux lignes Android.
        m.toggle(checkable)
        let android = m.androidRows
        #expect(m.canDelete)
        m.deleteSelected()
        #expect(m.androidRows == android)
        #expect(runner.calls.isEmpty && measure.calls.isEmpty)
    }

    // MARK: Suppression en démo (SL9 T6)

    final class Toasts { var messages: [String] = [] }

    func confirmingModel(runner: CommandRunner, measure: ScriptedMeasure, confirm: RecordingConfirm, toasts: Toasts) -> SimulatorsModel {
        SimulatorsModel(runner: runner,
                        detect: { SimulatorToolDetection(devicesFolderExists: false, simctlPath: nil) },
                        locateTool: { _ in nil },
                        environment: [:], home: URL(fileURLWithPath: "/home-fake/user-x"), now: { self.now },
                        measure: { measure.measure($0) }, demo: true, confirm: confirm.handler,
                        notify: { toasts.messages.append($0) })
    }

    @Test func confirmedDeletionInDemoRemovesTheRowsAtOnceWithoutRunnerNorMeasureNorRescan() async {
        let runner = FakeCommandRunner()           // un appel non prévu fait échouer le test
        let measure = ScriptedMeasure([:])
        let confirm = RecordingConfirm(answer: true)
        let toasts = Toasts()
        let m = confirmingModel(runner: runner, measure: measure, confirm: confirm, toasts: toasts)
        m.scan()
        let chosen = m.rows.filter { m.selected.contains($0.device.device.udid) }
        let chosenIDs = Set(chosen.map(\.device.device.udid))
        let expectedFreed = chosen.reduce(UInt64(0)) { $0 + (m.size(of: $1) ?? 0) }
        let rowsBefore = m.rows.count
        #expect(chosen.count >= 2 && expectedFreed > 0)
        #expect(m.canDelete)

        m.deleteSelected()

        // Même confirmation que dans l'application, pour l'écran S3.
        #expect(confirm.asks.count == 1)
        #expect(confirm.asks.first?.title == "Delete the selected devices? (\(chosen.count))")
        #expect(confirm.asks.first?.message.hasPrefix(Format.fileBytes(expectedFreed)) == true)
        #expect(confirm.asks.first?.button == "Delete" && confirm.asks.first?.critical == true)
        // Tout de suite : rien à attendre.
        #expect(m.rows.count == rowsBefore - chosen.count)
        #expect(m.rows.allSatisfy { !chosenIDs.contains($0.device.device.udid) })
        #expect(m.selected.isDisjoint(with: chosenIDs))
        #expect(toasts.messages == ["\(Format.fileBytes(expectedFreed)) freed"])
        #expect(m.deleteTask == nil, "aucune tâche : rien n'est lancé")
        #expect(!m.isDeleting)
        #expect(m.phase == .listed, "pas de nouveau scan")
        await m.scanTask?.value
        #expect(runner.calls.isEmpty)
        #expect(measure.calls.isEmpty)
    }

    @Test func cancelledDeletionInDemoChangesNothing() {
        let runner = FakeCommandRunner()
        let measure = ScriptedMeasure([:])
        let confirm = RecordingConfirm(answer: false)
        let toasts = Toasts()
        let m = confirmingModel(runner: runner, measure: measure, confirm: confirm, toasts: toasts)
        m.scan()
        let rows = m.rows, selection = m.selected

        m.deleteSelected()

        #expect(confirm.asks.count == 1)
        #expect(m.rows == rows)
        #expect(m.selected == selection)
        #expect(toasts.messages.isEmpty)
        #expect(runner.calls.isEmpty && measure.calls.isEmpty)
    }

    @Test func demoDeletionNeverTouchesTheDiskNorTheDetection() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("soaro-demo-\(UUID().uuidString)")
        var detections = 0
        let m = SimulatorsModel(runner: FakeCommandRunner(), detect: { detections += 1; return SimulatorToolDetection(devicesFolderExists: false, simctlPath: nil) },
                                environment: [:], home: missing, now: { self.now }, demo: true, confirm: { _, _, _, _ in true }, notify: { _ in })
        m.scan()
        m.deleteSelected()
        #expect(m.rows.count < DemoData.simulators(now: now).filter { $0.size >= DeviceSuggestions.smallDeviceThreshold }.count, "la suppression de démo a bien eu lieu")
        #expect(detections == 0)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }
}
