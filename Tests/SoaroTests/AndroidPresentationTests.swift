import Foundation
import Testing
@testable import Soaro

/// Texte d'une ligne d'émulateur Android (R16, R12) : fonctions pures, locale explicite.
/// Les attendus sont les textes anglais (clés du catalogue) : le processus de test n'a pas de traductions chargées.
@Suite struct AndroidPresentationTests {
    private let now = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!
    private let locale = Locale(identifier: "en_US")
    private let big: UInt64 = 500_000_000

    private func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    private func row(days: Double?, running: Bool = false, version: String? = "36", name: String = "Test_Phone_A",
                     display: String = "Test Phone A", size: UInt64? = nil) -> DeviceSuggestions.AndroidRow {
        let device = AndroidDevice(name: name, displayName: display, systemVersion: version,
                                   folder: URL(fileURLWithPath: "/Users/test/.android/avd/\(name).avd"),
                                   lastUsed: days.map(ago), lastUsedSource: nil, isRunning: running)
        return DeviceSuggestions.suggestAndroid([SizedAndroidDevice(device: device, size: size ?? big)], now: now, limitDays: 60).rows[0]
    }

    @Test func systemLabelFromTheVersion() {
        #expect(AndroidEmulatorPresentation.systemLabel(version: "36", locale: locale) == "API 36")
        #expect(AndroidEmulatorPresentation.systemLabel(version: "36.1", locale: locale) == "API 36.1")
    }

    @Test func noVersionIsUnknownSystem() {
        #expect(AndroidEmulatorPresentation.systemLabel(version: nil, locale: locale) == "Unknown system")
    }

    @Test func reasonLines() {
        #expect(AndroidEmulatorPresentation.reasonLine(for: row(days: 61), locale: locale) == "inactive for 61 d")
        #expect(AndroidEmulatorPresentation.reasonLine(for: row(days: 0), locale: locale) == "active today")
        #expect(AndroidEmulatorPresentation.reasonLine(for: row(days: 0.4), locale: locale) == "active today")
        #expect(AndroidEmulatorPresentation.reasonLine(for: row(days: nil), locale: locale) == "activity unknown")
    }

    @Test func aRunningRowHasAnEmptyReasonAndTheUnavailableText() {
        let running = row(days: 200, running: true)
        #expect(AndroidEmulatorPresentation.reasonLine(for: running, locale: locale) == "")
        #expect(AndroidEmulatorPresentation.unavailableReason(for: running) == "Running · quit it first")
        #expect(AndroidEmulatorPresentation.unavailableReason(for: row(days: 200)) == nil)
    }

    @Test func accessibilityHasNameSystemSizeAndReason() {
        let description = AndroidEmulatorPresentation.accessibility(row: row(days: 66, size: 1_200_000_000), size: 1_200_000_000,
                                                                    isOn: true, locale: locale)
        #expect(description.label == "Test Phone A, API 36, \(Format.fileBytes(1_200_000_000, locale: locale)), inactive for 66 d")
        #expect(description.value == "Selected")
    }

    @Test func accessibilityOmitsAnUnknownSize() {
        let description = AndroidEmulatorPresentation.accessibility(row: row(days: 10), size: nil, isOn: false, locale: locale)
        #expect(description.label == "Test Phone A, API 36, inactive for 10 d")
        #expect(description.value == "Not selected")
    }

    @Test func aRunningRowIsReadAsNotSelectable() {
        let description = AndroidEmulatorPresentation.accessibility(row: row(days: 5, running: true), size: big, isOn: false, locale: locale)
        #expect(description.value == "Running · quit it first, not selectable")
        #expect(description.value.hasSuffix("not selectable"))
    }

    @Test func groupStrings() {
        #expect(AndroidEmulatorPresentation.sectionTitle == "Android emulators")
        #expect(AndroidEmulatorPresentation.couldNotReadMessage == "Could not read the Android emulators.")
    }

    @Test func deviceNamesAreVerbatimAndTheWordRuntimeNeverAppears() {
        let odd = row(days: 70, name: "Test_Phone_A", display: "100 % %@ “x” <y>")
        let description = AndroidEmulatorPresentation.accessibility(row: odd, size: big, isOn: true, locale: locale)
        #expect(description.label.hasPrefix("100 % %@ “x” <y>, "))
        for text in [AndroidEmulatorPresentation.systemLabel(version: nil, locale: locale), AndroidEmulatorPresentation.sectionTitle,
                     AndroidEmulatorPresentation.couldNotReadMessage, description.label, description.value] {
            #expect(!text.localizedCaseInsensitiveContains("runtime"))
        }
    }

    @Test func theThreeNewKeysAreInTheCatalogInNineLanguages() throws {
        let url = RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Resources/Localizable.xcstrings")
        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: Any])
        for key in ["API %@", "Android emulators", "Could not read the Android emulators."] {
            let entry = try #require(strings[key] as? [String: Any], "\(key)")
            let localizations = try #require(entry["localizations"] as? [String: Any])
            #expect(Set(localizations.keys) == Set(TranslationCatalog.requiredTranslations), "\(key)")
        }
    }
}
