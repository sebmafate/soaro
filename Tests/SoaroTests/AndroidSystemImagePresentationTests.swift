import Foundation
import Testing
@testable import Soaro

/// Texte d'une ligne d'image système Android (SL12a, T4) : fonctions pures, locale explicite.
/// Les attendus sont les textes anglais (clés du catalogue) : le processus de test n'a pas de traductions chargées.
@Suite struct AndroidSystemImagePresentationTests {
    private let locale = Locale(identifier: "en_US")

    private func device(_ name: String, display: String) -> AndroidDevice {
        AndroidDevice(name: name, displayName: display, systemVersion: "36",
                      folder: URL(fileURLWithPath: "/Users/test/.android/avd/\(name).avd"), lastUsed: nil, lastUsedSource: nil)
    }

    private func image(_ usage: AndroidSystemImage.Usage, path: String = "android-36/google_apis_playstore/arm64-v8a") -> AndroidSystemImage {
        let key = AndroidSystemImageScanner.imageKey(imageSysdir: "system-images/\(path)")!
        return AndroidSystemImage(key: key, folder: URL(fileURLWithPath: "/Users/test/Library/Android/sdk/system-images/\(path)"), usage: usage)
    }

    @Test func sectionTitleAndFailureMessage() {
        #expect(AndroidSystemImagePresentation.sectionTitle == "Android system images")
        #expect(AndroidSystemImagePresentation.couldNotReadMessage == "Could not read the Android system images.")
    }

    @Test func theTitleIsTheApiLabel() {
        #expect(AndroidSystemImagePresentation.title(image: image(.notUsed), locale: locale) == "API 36")
        #expect(AndroidSystemImagePresentation.title(image: image(.notUsed, path: "android-36.1/google_apis/arm64-v8a"), locale: locale) == "API 36.1")
    }

    @Test func theDetailIsVariantAndAbiVerbatim() {
        #expect(AndroidSystemImagePresentation.detail(image: image(.notUsed)) == "google_apis_playstore · arm64-v8a")
    }

    @Test func eachUsageLineIsExact() {
        let a = device("Test_Phone_A", display: "Test Phone A")
        #expect(AndroidSystemImagePresentation.usageLine(image: image(.usedBy([a])), locale: locale) == "used by Test Phone A")
        #expect(AndroidSystemImagePresentation.usageLine(image: image(.notUsed), locale: locale) == "not used by any listed device")
        #expect(AndroidSystemImagePresentation.usageLine(image: image(.cannotTell), locale: locale) == "cannot tell whether a device uses it")
    }

    @Test func twoUsersAreJoinedWithACommaInTheGivenOrder() {
        let users = [device("Test_Phone_A", display: "Test Phone A"), device("Test_Tablet_B", display: "Test Tablet B")]
        #expect(AndroidSystemImagePresentation.usageLine(image: image(.usedBy(users)), locale: locale) == "used by Test Phone A, Test Tablet B")
    }

    @Test func aDisplayNameWithPercentOrStarIsShownVerbatim() {
        let odd = device("Test_Phone_A", display: "100% %@ Phone *")
        #expect(AndroidSystemImagePresentation.usageLine(image: image(.usedBy([odd])), locale: locale) == "used by 100% %@ Phone *")
    }

    @Test func theFooterText() {
        #expect(AndroidSystemImagePresentation.incompleteFooter
                == "Some virtual devices could not be read or are kept in another folder, so Soaro cannot tell whether these images are in use.")
    }

    @Test func theAccessibilityLabelWithASize() {
        let a = device("Test_Phone_A", display: "Test Phone A")
        let label = AndroidSystemImagePresentation.accessibilityLabel(image: image(.usedBy([a])), size: 3_200_000_000, locale: locale)
        #expect(label == "API 36, google_apis_playstore, arm64-v8a, \(Format.fileBytes(3_200_000_000, locale: locale)), used by Test Phone A")
    }

    @Test func theAccessibilityLabelOmitsAnUnknownSize() {
        let label = AndroidSystemImagePresentation.accessibilityLabel(image: image(.notUsed), size: nil, locale: locale)
        #expect(label == "API 36, google_apis_playstore, arm64-v8a, not used by any listed device")
    }

    @Test func theAccessibilityLabelHasNoSelectionValue() {
        let label = AndroidSystemImagePresentation.accessibilityLabel(image: image(.cannotTell), size: 1_000_000, locale: locale)
        #expect(!label.contains("Selected"))
        #expect(!label.contains("Not selected"))
    }

    @Test func theSizeTextIsEllipsisWhileUnknown() {
        #expect(SimulatorPresentation.sizeText(nil, locale: locale) == "…")
    }

    @Test func theSixNewKeysAreInTheCatalogInNineLanguages() throws {
        let url = RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Resources/Localizable.xcstrings")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: [String: Any]])
        let keys = ["Android system images", "Could not read the Android system images.", "used by %@", "not used by any listed device",
                    "cannot tell whether a device uses it",
                    "Some virtual devices could not be read or are kept in another folder, so Soaro cannot tell whether these images are in use."]
        for key in keys {
            let localizations = try #require(strings[key]?["localizations"] as? [String: Any], "\(key)")
            for language in TranslationCatalog.requiredTranslations {
                #expect(localizations[language] != nil, "\(key) / \(language)")
            }
        }
    }
}
