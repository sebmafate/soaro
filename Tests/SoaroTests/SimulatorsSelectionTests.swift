import Foundation
import Testing
@testable import Soaro

/// Pré-sélection, sélection manuelle et menu de limite (T7).
@MainActor
@Suite(.serialized) struct SimulatorsSelectionTests {
    let now = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!
    let present = SimulatorToolDetection(devicesFolderExists: true, simctlPath: "/fake/simctl")
    let home = URL(fileURLWithPath: "/home-fake/user-x")
    static let args = ["simctl", "list", "devices", "-j"]

    static func udid(_ n: Int) -> String { String(format: "00000000-0000-4000-8000-%012d", n) }

    struct Spec {
        let n: Int
        let days: Double?
        var state = "Shutdown"
        var model: String? = nil
        var name: String? = nil
    }

    func json(_ specs: [Spec]) -> String {
        let formatter = ISO8601DateFormatter()
        let entries = specs.map { spec -> String in
            let date = spec.days.map { "\"lastUsedAt\": \"\(formatter.string(from: now.addingTimeInterval(-$0 * 86_400)))\"," } ?? ""
            return "{\"udid\": \"\(Self.udid(spec.n))\", \"name\": \"\(spec.name ?? "Device \(spec.n)")\", \(date) \"state\": \"\(spec.state)\", "
                + "\"deviceTypeIdentifier\": \"\(spec.model ?? "type-\(spec.n)")\"}"
        }
        return "{\"devices\": {\"com.apple.CoreSimulator.SimRuntime.iOS-26-2\": [\(entries.joined(separator: ","))]}}"
    }

    func runner(_ specs: [Spec]) -> FakeCommandRunner {
        let fake = FakeCommandRunner()
        fake.script(.finished(stdout: json(specs)), executable: "/usr/bin/xcrun", arguments: Self.args)
        return fake
    }

    func model(_ runner: CommandRunner, measure: ScriptedMeasure? = nil) -> SimulatorsModel {
        let measure = measure ?? ScriptedMeasure([:])
        return SimulatorsModel(runner: runner, detect: { self.present }, locateXcrun: { _ in "/usr/bin/xcrun" }, home: home,
                               now: { self.now }, measure: { measure.measure($0) }, demo: false, notify: { _ in })
    }

    /// Tous les appareils pèsent 500 Mo sauf indication contraire.
    func bigMeasure(_ specs: [Spec], overrides: [Int: UInt64] = [:], gated: Bool = false) -> ScriptedMeasure {
        var sizes: [String: UInt64] = [:]
        for spec in specs { sizes[Self.udid(spec.n)] = overrides[spec.n] ?? 500_000_000 }
        return ScriptedMeasure(sizes, gated: gated)
    }

    func run(_ m: SimulatorsModel) async { m.scan(); await m.scanTask?.value }

    func selectedNumbers(_ m: SimulatorsModel) -> Set<Int> { Set(m.selected.map { Int($0.suffix(12))! }) }

    // MARK: Pré-sélection à 59 / 60 / 61 jours

    @Test(arguments: [(59.0, false), (60.0, false), (60.99, false), (61.0, true)])
    func preSelectionAtTheDefaultLimitOf60Days(days: Double, expected: Bool) async {
        let specs = [Spec(n: 1, days: days)]
        let m = model(runner(specs), measure: bigMeasure(specs))
        await run(m)
        #expect((selectedNumbers(m) == [1]) == expected)
        #expect(m.limitDays == 60)
    }

    // MARK: Limite

    @Test func limitMenuIsRecomputedAtOnceWithoutRescanning() async {
        let specs = [Spec(n: 1, days: 10), Spec(n: 2, days: 45), Spec(n: 3, days: 90), Spec(n: 4, days: 200)]
        let fake = runner(specs)
        let measure = bigMeasure(specs)
        let m = model(fake, measure: measure)
        await run(m)
        #expect(selectedNumbers(m) == [3, 4])
        let callsBefore = (fake.calls.count, measure.calls.count)

        m.setLimit(30)
        #expect(selectedNumbers(m) == [2, 3, 4])
        m.setLimit(180)
        #expect(selectedNumbers(m) == [4])
        m.setLimit(60)
        #expect(selectedNumbers(m) == [3, 4])
        #expect(m.limitDays == 60)
        #expect(fake.calls.count == callsBefore.0, "aucun appel au lanceur")
        #expect(measure.calls.count == callsBefore.1, "aucune mesure de plus")
        #expect(m.phase == .listed)
    }

    @Test func aLimitChangeReplacesTheManualPicks() async {
        let specs = [Spec(n: 1, days: 10), Spec(n: 2, days: 90)]
        let m = model(runner(specs), measure: bigMeasure(specs))
        await run(m)
        m.toggle(m.rows.first { $0.device.device.udid == Self.udid(1) }!)    // coche à la main
        m.toggle(m.rows.first { $0.device.device.udid == Self.udid(2) }!)    // décoche la suggestion
        #expect(selectedNumbers(m) == [1])
        m.setLimit(90)
        #expect(selectedNumbers(m) == [], "la sélection devient exactement la suggestion de la nouvelle limite")
        m.setLimit(30)
        #expect(selectedNumbers(m) == [2])
    }

    @Test func scanAgainSelectsFromFreshDataWithTheCurrentLimit() async {
        let specs = [Spec(n: 1, days: 45)]
        let m = model(runner(specs), measure: bigMeasure(specs))
        await run(m)
        #expect(selectedNumbers(m) == [])
        m.setLimit(30)
        #expect(selectedNumbers(m) == [1])
        await run(m)
        #expect(selectedNumbers(m) == [1], "la limite choisie est gardée pendant la session")
        #expect(m.limitDays == 30)
    }

    @Test func limitMenuValues() {
        #expect(SimulatorsModel.limitChoices(defaultDays: 60) == [30, 60, 90, 180])
        #expect(SimulatorsModel.limitChoices(defaultDays: 30) == [30, 60, 90, 180])
        #expect(SimulatorsModel.limitChoices(defaultDays: 45) == [30, 45, 60, 90, 180])
        #expect(SimulatorsModel.limitChoices(defaultDays: 365) == [30, 60, 90, 180, 365])
        #expect(SimulatorsModel.limitChoices(defaultDays: 10) == [10, 30, 60, 90, 180])
        #expect(SimulatorsModel.limitChoices(defaultDays: DeviceSuggestions.defaultLimitDays).contains(DeviceSuggestions.defaultLimitDays))
    }

    @Test func theLimitIsNotRememberedBetweenSessions() throws {
        let url = RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Cleanup/SimulatorsModel.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("UserDefaults") && !text.contains("AppStorage"))
    }

    // MARK: Appareil en cours d'exécution

    @Test func aRunningDeviceIsNeverSelectedNorToggled() async {
        let specs = [Spec(n: 1, days: 300, state: "Booted"), Spec(n: 2, days: 300)]
        let m = model(runner(specs), measure: bigMeasure(specs))
        await run(m)
        #expect(selectedNumbers(m) == [2])
        let running = m.rows.first { $0.device.device.udid == Self.udid(1) }!
        m.toggle(running)
        #expect(selectedNumbers(m) == [2])
        for limit in [30, 90, 180, 60] {
            m.setLimit(limit)
            #expect(!m.selected.contains(Self.udid(1)), "limite \(limit)")
        }
    }

    // MARK: Pendant la mesure

    @Test func aToggleSurvivesASizeUpdate() async {
        let specs = [Spec(n: 1, days: 10), Spec(n: 2, days: 20)]
        let measure = bigMeasure(specs, gated: true)
        let m = model(runner(specs), measure: measure)
        m.scan()
        await measure.started.wait()     // la première mesure est en cours
        #expect(selectedNumbers(m) == [])
        m.toggle(m.rows.first { $0.device.device.udid == Self.udid(2) }!)
        #expect(selectedNumbers(m) == [2])
        measure.release.signal()
        await measure.started.wait()
        #expect(selectedNumbers(m) == [2], "la mesure d'un autre appareil ne change pas la sélection")
        measure.release.signal()
        await m.scanTask?.value
        #expect(selectedNumbers(m) == [2])
        m.toggle(m.rows.first { $0.device.device.udid == Self.udid(2) }!)
        #expect(selectedNumbers(m) == [])
    }

    @Test func aDeviceMeasuredSmallLeavesTheSelection() async {
        let specs = [Spec(n: 1, days: 100), Spec(n: 2, days: 100)]
        let measure = bigMeasure(specs, overrides: [1: 50_000_000], gated: true)
        let m = model(runner(specs), measure: measure)
        m.scan()
        await measure.started.wait()
        #expect(selectedNumbers(m) == [1, 2], "pré-sélection avant les tailles")
        measure.release.signal()
        await measure.started.wait()
        #expect(selectedNumbers(m) == [2], "le petit appareil sort de la sélection dès sa mesure")
        measure.release.signal()
        await m.scanTask?.value
        #expect(selectedNumbers(m) == [2])
        #expect(m.hiddenSmallCount == 1)
    }

    @Test func selectedSummaryCountsOnlyKnownSizes() async {
        let specs = [Spec(n: 1, days: 100), Spec(n: 2, days: 100)]
        let m = model(runner(specs), measure: bigMeasure(specs, overrides: [1: 300_000_000, 2: 700_000_000]))
        await run(m)
        #expect(m.selectedCount == 2)
        #expect(m.selectedSize == 1_000_000_000)
    }

    // MARK: Bandeau

    @Test func bannerShowsWhenRowsAreListedAndNothingIsPreSelected() async {
        let specs = [Spec(n: 1, days: 10), Spec(n: 2, days: 20)]
        let m = model(runner(specs), measure: bigMeasure(specs))
        await run(m)
        #expect(m.showsNothingToSuggest)
        m.setLimit(30)
        #expect(m.showsNothingToSuggest)          // 10 et 20 jours : toujours rien à 30
        m.toggle(m.rows[0])                         // choisir à la main ne retire pas le bandeau
        #expect(m.showsNothingToSuggest)
    }

    @Test func bannerStaysHiddenWhileTheSizesAreMeasured() async {
        // Règle : tant que les tailles arrivent, la pré-sélection est provisoire ; le bandeau n'apparaît qu'à la fin.
        let specs = [Spec(n: 1, days: 10), Spec(n: 2, days: 20)]
        let measure = bigMeasure(specs, gated: true)
        let m = model(runner(specs), measure: measure)
        m.scan()
        await measure.started.wait()
        #expect(m.isMeasuring)
        #expect(!m.showsNothingToSuggest)
        measure.release.signal()
        await measure.started.wait()
        #expect(!m.showsNothingToSuggest)
        measure.release.signal()
        await m.scanTask?.value
        #expect(m.showsNothingToSuggest)
    }

    @Test func bannerHidesWhenSomethingIsPreSelectedOrNothingIsListed() async {
        let specs = [Spec(n: 1, days: 100)]
        let m = model(runner(specs), measure: bigMeasure(specs))
        await run(m)
        #expect(!m.showsNothingToSuggest)

        let small = [Spec(n: 1, days: 100)]
        let m2 = model(runner(small), measure: bigMeasure(small, overrides: [1: 10_000]))
        await run(m2)
        #expect(m2.rows.isEmpty)
        #expect(!m2.showsNothingToSuggest, "aucune ligne listée : pas de bandeau")
    }

    // MARK: Textes (R12)

    @Test func nothingToSuggestAndFooterTexts() {
        let locale = Locale(identifier: "en_US")
        #expect(SimulatorPresentation.nothingToSuggest(limitDays: 60)
                == "Nothing to suggest at 60 days. Pick devices yourself, or lower the limit.")
        #expect(SimulatorPresentation.smallDevicesFooter(count: 0, size: 0, locale: locale) == nil)
        #expect(SimulatorPresentation.smallDevicesFooter(count: 3, size: 120_000_000, locale: locale)
                == "3 small devices (\(Format.fileBytes(120_000_000, locale: locale))) not shown.")
        #expect(SimulatorPresentation.explanationFooter(limitDays: 30)
                == "Devices inactive for more than 30 days, and older copies of the same model, are pre-selected. "
                + "A removed device takes its apps, data and snapshots with it; create a new one from Xcode or Android Studio.")
    }

    @Test func newStringsAreInTheCatalogInNineLanguagesWithoutVariations() throws {
        let catalog = try TranslationCatalog.loadCatalog(TranslationCatalogTests.localizable)
        let strings = try #require(catalog["strings"] as? [String: Any])
        let keys = ["Nothing to suggest at %lld days. Pick devices yourself, or lower the limit.",
                    "%lld small devices (%@) not shown.",
                    "Devices inactive for more than %lld days, and older copies of the same model, are pre-selected. "
                    + "A removed device takes its apps, data and snapshots with it; create a new one from Xcode or Android Studio."]
        for key in keys {
            let entry = try #require(strings[key] as? [String: Any], "clé absente : \(key)")
            #expect(entry["variations"] == nil)
            let localizations = try #require(entry["localizations"] as? [String: Any])
            for language in TranslationCatalog.requiredTranslations {
                let unit = try #require((localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any], "\(key) / \(language)")
                let value = try #require(unit["value"] as? String)
                #expect(TranslationCatalog.placeholders(in: value).byPosition.values.sorted()
                        == TranslationCatalog.placeholders(in: key).byPosition.values.sorted(), "\(language)")
            }
        }
    }
}
