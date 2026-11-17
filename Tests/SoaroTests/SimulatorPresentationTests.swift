import Foundation
import Testing
@testable import Soaro

/// Texte d'une ligne de simulateur : fonctions pures, instant et locale explicites.
/// Les attendus sont les textes anglais (clés du catalogue) : le processus de test n'a pas de traductions chargées.
@Suite struct SimulatorPresentationTests {
    private let now = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!
    private let locale = Locale(identifier: "en_US")
    private let big: UInt64 = 500_000_000
    private let ios = "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
    private let phone = "com.apple.CoreSimulator.SimDeviceType.iPhone-17"

    private func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    private func dev(_ n: Int, name: String = "Device", days: Double?, size: UInt64? = nil, model: String? = nil,
                     runtime: String? = nil, state: String = "Shutdown", available: Bool = true) -> SizedSimulator {
        let runtimeID = runtime ?? ios
        return SizedSimulator(
            device: SimulatorDevice(udid: String(format: "00000000-0000-4000-8000-%012d", n), name: name,
                                    modelIdentifier: model ?? "model-\(n)", runtimeIdentifier: runtimeID,
                                    runtimeName: SimulatorScanner.runtimeName(runtimeID), state: state,
                                    isAvailable: available, lastUsed: days.map(ago)),
            size: size ?? big)
    }

    private func rows(_ devices: [SizedSimulator], limit: Int = 60) -> [DeviceSuggestions.Row] {
        DeviceSuggestions.suggest(devices, now: now, limitDays: limit).rows
    }

    private func row(_ n: Int, in rows: [DeviceSuggestions.Row]) -> DeviceSuggestions.Row {
        rows.first { Int($0.device.device.udid.suffix(12)) == n }!
    }

    private func reason(_ row: DeviceSuggestions.Row) -> String {
        SimulatorPresentation.reasonLine(for: row, now: now, locale: locale)
    }

    // MARK: Système

    @Test(arguments: [
        ("com.apple.CoreSimulator.SimRuntime.iOS-26-2", "iOS 26.2"),
        ("com.apple.CoreSimulator.SimRuntime.watchOS-11-2", "watchOS 11.2"),
        ("com.apple.CoreSimulator.SimRuntime.tvOS-18-2", "tvOS 18.2"),
        ("com.apple.CoreSimulator.SimRuntime.xrOS-2-2", "visionOS 2.2"),
        ("com.apple.CoreSimulator.SimRuntime.visionOS-2-2", "visionOS 2.2"),
        ("com.apple.CoreSimulator.SimRuntime.iOS-18", "iOS 18"),
    ])
    func systemLabelFromTheRuntimeIdentifier(identifier: String, expected: String) {
        #expect(SimulatorPresentation.systemLabel(runtimeIdentifier: identifier) == expected)
    }

    @Test(arguments: ["", "garbage", "com.apple.CoreSimulator.SimRuntime.", "com.apple.CoreSimulator.SimRuntime.iOS",
                      "com.example.Other.iOS-26-2", "com.apple.CoreSimulator.SimRuntime.iOS-26-beta"])
    func unparsableSystemIsUnknownNeverTheRawIdentifier(identifier: String) {
        let label = SimulatorPresentation.systemLabel(runtimeIdentifier: identifier)
        #expect(label == "Unknown system")
        #expect(!label.contains("com.apple"))
        #expect(!label.localizedCaseInsensitiveContains("runtime"))
    }

    // MARK: Raison d'une ligne sélectionnable

    @Test func inactiveForNDays() {
        #expect(reason(row(1, in: rows([dev(1, days: 66)]))) == "inactive for 66 d")
    }

    @Test func activeToday() {
        #expect(reason(row(1, in: rows([dev(1, days: 0)]))) == "active today")
        #expect(reason(row(1, in: rows([dev(1, days: 0.4)]))) == "active today")
    }

    @Test func oneDayIsInactiveForOneDay() {
        #expect(reason(row(1, in: rows([dev(1, days: 1)]))) == "inactive for 1 d")
    }

    @Test func unknownDate() {
        #expect(reason(row(1, in: rows([dev(1, days: nil)]))) == "activity unknown")
    }

    @Test func inactiveAndOlderCopyJoinWithAMiddleDot() {
        let r = rows([dev(1, name: "Kept Phone", days: 2, model: phone), dev(2, name: "Old Phone", days: 90, model: phone)])
        #expect(reason(row(2, in: r)) == "inactive for 90 d · older copy of “Kept Phone”, used 2 d ago")
    }

    @Test func olderCopyNamesTheKeptDeviceUsedNDaysAgo() {
        let r = rows([dev(1, name: "Kept Phone", days: 12, model: phone), dev(2, days: 30, model: phone)])
        #expect(reason(row(2, in: r)) == "inactive for 30 d · older copy of “Kept Phone”, used 12 d ago")
    }

    @Test func olderCopyNamesTheKeptDeviceUsedToday() {
        let r = rows([dev(1, name: "Kept Phone", days: 0, model: phone), dev(2, days: 20, model: phone)])
        #expect(reason(row(2, in: r)) == "inactive for 20 d · older copy of “Kept Phone”, used today")
    }

    @Test func olderCopyWhoseKeptDeviceIsRunning() {
        let r = rows([dev(1, name: "Kept Phone", days: 200, model: phone, state: "Booted"), dev(2, days: 5, model: phone)])
        #expect(reason(row(2, in: r)) == "inactive for 5 d · older copy of “Kept Phone”, which is running")
    }

    @Test func anUndatedCopyShowsActivityUnknown() {
        // Une copie sans date ne peut pas être « ancienne copie » (hors classement) ; elle montre « activity unknown ».
        let r = rows([dev(1, name: "Kept Phone", days: 3, model: phone), dev(2, days: nil, model: phone)])
        #expect(reason(row(2, in: r)) == "activity unknown")
    }

    @Test func deviceNamesAreVerbatim() {
        let r = rows([dev(1, name: "100 % %@ “x” <y>", days: 3, model: phone), dev(2, days: 10, model: phone)])
        #expect(reason(row(2, in: r)).contains("“100 % %@ “x” <y>”"))
    }

    @Test func unavailableDeviceAddsTheSystemNotInstalledPart() {
        let r = rows([dev(1, days: 70, available: false)])
        #expect(reason(row(1, in: r)) == "inactive for 70 d · unavailable: system not installed")
        let all = rows([dev(1, name: "Kept Phone", days: 2, model: phone), dev(2, days: 90, model: phone, available: false)])
        #expect(reason(row(2, in: all)) == "inactive for 90 d · older copy of “Kept Phone”, used 2 d ago · unavailable: system not installed")
    }

    @Test func availableDeviceHasNoUnavailablePart() {
        #expect(!reason(row(1, in: rows([dev(1, days: 70)]))).contains("unavailable"))
    }

    // MARK: Appareil en cours d'exécution

    @Test func runningRowUsesTheUnavailableVariantWithItsReason() {
        let r = rows([dev(1, days: 70, state: "Booted")])
        let running = row(1, in: r)
        #expect(SimulatorPresentation.unavailableReason(for: running) == "Running · quit it first")
        #expect(SimulatorPresentation.unavailableReason(for: row(1, in: rows([dev(1, days: 70)]))) == nil)
    }

    @Test func runningRowHasNoDaysPartInItsReasonLine() {
        let running = row(1, in: rows([dev(1, days: 70, state: "Booted")]))
        #expect(reason(running) == "")
    }

    // MARK: VoiceOver

    @Test func accessibilityLabelHasNameSystemSizeAndReason() {
        let r = row(1, in: rows([dev(1, name: "Phone A", days: 66, size: 1_200_000_000)]))
        let d = SimulatorPresentation.accessibility(name: "Phone A", row: r, size: 1_200_000_000, isOn: true, now: now, locale: locale)
        #expect(d.label == "Phone A, iOS 26.2, \(Format.fileBytes(1_200_000_000, locale: locale)), inactive for 66 d")
        #expect(d.value == "Selected")
    }

    @Test func accessibilityLabelOmitsTheSizeWhileUnknown() {
        let r = row(1, in: rows([dev(1, name: "Phone A", days: 66)]))
        let d = SimulatorPresentation.accessibility(name: "Phone A", row: r, size: nil, isOn: false, now: now, locale: locale)
        #expect(d.label == "Phone A, iOS 26.2, inactive for 66 d")
        #expect(d.value == "Not selected")
    }

    @Test func runningRowReadsRunningQuitItFirstNotSelectable() {
        let r = row(1, in: rows([dev(1, name: "Phone A", days: 66, state: "Booted")]))
        let d = SimulatorPresentation.accessibility(name: "Phone A", row: r, size: 500_000_000, isOn: false, now: now, locale: locale)
        #expect(d.label == "Phone A, iOS 26.2, \(Format.fileBytes(500_000_000, locale: locale))")
        #expect(d.value == "Running · quit it first, not selectable")
    }

    @Test func unknownSystemIsReadAsUnknownSystem() {
        let r = row(1, in: rows([dev(1, name: "Phone A", days: 66, runtime: "garbage")]))
        let d = SimulatorPresentation.accessibility(name: "Phone A", row: r, size: nil, isOn: true, now: now, locale: locale)
        #expect(d.label.hasPrefix("Phone A, Unknown system"))
    }

    @Test func sizeTextIsAnEllipsisWhileUnknown() {
        #expect(SimulatorPresentation.sizeText(nil, locale: locale) == "…")
        #expect(SimulatorPresentation.sizeText(1_200_000_000, locale: locale) == Format.fileBytes(1_200_000_000, locale: locale))
    }

    /// Les deux textes « older copy » (anglais brut de `--scan`, texte de l'écran) viennent du même appareil gardé : ils restent
    /// d'accord sur le nom, et `--scan` ajoute le système et l'UDID pour le contrôle sur 5 appareils.
    @Test func theScanReportAndTheScreenNameTheSameKeptDevice() {
        let r = rows([dev(1, name: "Kept Phone", days: 3, model: phone), dev(2, days: 30, model: phone)])
        let older = row(2, in: r)
        let kept = older.keptDevice!
        let scan = SimulatorScan(status: .ok, devices: r.map(\.device))
        let suggestions = DeviceSuggestions.suggest(scan.devices, now: now, limitDays: 60)
        let report = SimulatorReport.lines(scan: scan, suggestions: suggestions, locale: locale, limitDays: 60).joined(separator: "\n")
        #expect(report.contains("older copy of \(kept.device.name) (\(kept.device.runtimeName), \(kept.device.udid))"))
        #expect(reason(older).contains("older copy of “\(kept.device.name)”"))
    }

    // MARK: Vocabulaire et catalogue (R12)

    private let newKeys = [
        "older copy of “%@”, used %lld d ago",
        "older copy of “%@”, used today",
        "older copy of “%@”, which is running",
        "unavailable: system not installed",
        "Running · quit it first",
        "Unknown system",
    ]

    @Test func everyNewStringIsInTheCatalogInNineLanguagesWithItsPlaceholders() throws {
        let catalog = try TranslationCatalog.loadCatalog(TranslationCatalogTests.localizable)
        let strings = try #require(catalog["strings"] as? [String: Any])
        for key in newKeys {
            let entry = try #require(strings[key] as? [String: Any], "clé absente : \(key)")
            #expect(entry["variations"] == nil)
            let localizations = try #require(entry["localizations"] as? [String: Any])
            for language in TranslationCatalog.requiredTranslations {
                let unit = try #require((localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any], "\(key) / \(language)")
                let value = try #require(unit["value"] as? String)
                #expect(!value.isEmpty)
                #expect(TranslationCatalog.placeholders(in: value).byPosition.values.sorted()
                        == TranslationCatalog.placeholders(in: key).byPosition.values.sorted(), "\(key) / \(language)")
                #expect(!value.localizedCaseInsensitiveContains("runtime"))
            }
        }
    }

    @Test func theWordRuntimeNeverAppearsInTheEnglishTexts() {
        for key in newKeys { #expect(!key.localizedCaseInsensitiveContains("runtime")) }
    }

    // MARK: Noms dans la confirmation (SL11, ADR 0009 règle 2)

    @Test func theConfirmationNamesAreBulletLinesAfterABlankLine() {
        #expect(SimulatorPresentation.confirmationNames(["iPhone 15", "Test Phone A"]) == "\n\n• iPhone 15\n• Test Phone A")
        #expect(SimulatorPresentation.confirmationNames([]) == "")
    }

    @Test func theConfirmationNamesAreCappedAtEightThenOneEllipsisLine() {
        let eight = (1...8).map { "Test Device \($0)" }
        #expect(SimulatorPresentation.confirmationNames(eight) == "\n\n" + eight.map { "• \($0)" }.joined(separator: "\n"))
        let nine = eight + ["Test Device 9"]
        #expect(SimulatorPresentation.confirmationNames(nine) == "\n\n" + eight.map { "• \($0)" }.joined(separator: "\n") + "\n…")
        #expect(!SimulatorPresentation.confirmationNames(nine).contains("Test Device 9"))
    }

    @Test func aLongNameIsShortenedToSixtyCharactersAndAnEllipsis() {
        let sixty = String(repeating: "a", count: 60)
        #expect(SimulatorPresentation.confirmationNames([sixty]) == "\n\n• \(sixty)", "60 caractères : tel quel")
        #expect(SimulatorPresentation.confirmationNames([sixty + "b"]) == "\n\n• \(sixty)…")
        #expect(SimulatorPresentation.confirmationNames([String(repeating: "é", count: 500)]) == "\n\n• " + String(repeating: "é", count: 60) + "…")
    }

    @Test func controlAndDirectionalCharactersAreRemovedAndTabsAndBreaksBecomeSpaces() {
        // Tabulation, C0 (U+0007), C1 (U+0085 : saut de ligne), séparateurs U+2028 et U+2029, et tous les caractères de format :
        // marques de direction, isolats, espaces de largeur nulle, BOM, RLO.
        let hostile = "Test\tPhone\u{7}\u{85}A\u{2028}B\u{2029}C\u{202E}evil\u{202C}\u{200E}\u{200F}\u{2066}\u{2069}\u{200B}\u{200C}\u{200D}\u{FEFF}"
        #expect(SimulatorPresentation.confirmationNames([hostile]) == "\n\n• Test Phone A B Cevil")
        #expect(SimulatorPresentation.confirmationNames(["\u{202E}\u{200B}"]) == "", "un nom vide après nettoyage est omis")
        #expect(SimulatorPresentation.confirmationNames(["Test Phone A", "\u{FEFF}"]) == "\n\n• Test Phone A")
    }

    @Test func moreThanEightNamesStillCapAfterCleaningAndTheEllipsisLineIsPlain() {
        let names = (1...12).map { "Test\u{200B} Device \($0)" }
        let text = SimulatorPresentation.confirmationNames(names)
        #expect(text == "\n\n" + (1...8).map { "• Test Device \($0)" }.joined(separator: "\n") + "\n…")
    }

    @Test func aNameWithLineBreaksStaysOnOneLineAndOtherwiseVerbatim() {
        #expect(SimulatorPresentation.confirmationNames(["Test\nPhone\r\nA", "“Quoted” 100 %"]) == "\n\n• Test Phone A\n• “Quoted” 100 %")
    }
}
