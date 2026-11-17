import Foundation
import Testing
@testable import Soaro

/// Clé d'une image système depuis `image.sysdir.1` (SL12a, T1) : fonctions PURES, aucun accès au disque.
@Suite(.serialized) struct AndroidSystemImageParsingTests {
    private func key(_ value: String?) -> AndroidSystemImageKey? { AndroidSystemImageScanner.imageKey(imageSysdir: value) }

    @Test func aRelativeValueWithATrailingSlashGivesTheKey() throws {
        let key = try #require(key("system-images/android-36/google_apis_playstore/arm64-v8a/"))
        #expect(key.path == "android-36/google_apis_playstore/arm64-v8a")
        #expect(key.version == "36")
        #expect(key.variant == "google_apis_playstore")
        #expect(key.abi == "arm64-v8a")
    }

    @Test func theTrailingSlashIsOptional() {
        #expect(key("system-images/android-36/google_apis_playstore/arm64-v8a")
                == key("system-images/android-36/google_apis_playstore/arm64-v8a/"))
    }

    @Test func aMinorVersionIsKept() throws {
        let key = try #require(key("system-images/android-36.1/google_apis/arm64-v8a/"))
        #expect(key.version == "36.1")
        #expect(key.path == "android-36.1/google_apis/arm64-v8a")
    }

    @Test func anAbsoluteValueGivesTheSameKey() throws {
        let key = try #require(key("/Users/test/Library/Android/sdk/system-images/android-34/default/arm64-v8a"))
        #expect(key.path == "android-34/default/arm64-v8a")
        #expect(key.version == "34")
    }

    @Test func invalidValuesGiveNil() {
        #expect(key("system-images/android-Baklava/google_apis/arm64-v8a/") == nil)
        #expect(key("system-images/android-36/google_apis/") == nil)
        #expect(key("system-images/android-36") == nil)
        #expect(key("system-images/android-36/../arm64-v8a/") == nil)
        #expect(key("system-images/android-36/google apis/arm64-v8a/") == nil)
        #expect(key("system-images/android-36/google_apis/arm 64/") == nil)
        #expect(key("system-images/android-36/google_apis/../") == nil)
        #expect(key("system-images/android-/google_apis/arm64-v8a/") == nil)
        #expect(key("system-images/android-36./google_apis/arm64-v8a/") == nil)
        #expect(key("images/android-36/google_apis/arm64-v8a/") == nil)
        #expect(key(nil) == nil)
        #expect(key("") == nil)
    }

    @Test func theVersionAgreesWithSystemVersionForEveryKey() {
        let values: [String?] = [
            "system-images/android-36/google_apis_playstore/arm64-v8a/", "system-images/android-36.1/google_apis/arm64-v8a",
            "/Users/test/Library/Android/sdk/system-images/android-34/default/arm64-v8a", "system-images/android-Baklava/x/y",
            "system-images/android-36/google_apis/", nil, "",
        ]
        for value in values {
            if let key = key(value) {
                #expect(AndroidEmulatorScanner.systemVersion(imageSysdir: value) == key.version, "\(value ?? "nil")")
            }
        }
    }

    @Test func theFirstSystemImagesSegmentWinsWhenThereAreTwo() throws {
        // Le premier `system-images` décide (même règle que `systemVersion`) ; le second est une simple donnée (ici l'ABI).
        let value = "system-images/android-36/default/system-images"
        let first = try #require(key(value))
        #expect(first.path == "android-36/default/system-images")
        #expect(AndroidEmulatorScanner.systemVersion(imageSysdir: value) == first.version)
        // Quand les trois segments qui suivent le premier ne font pas une clé, le second n'est PAS essayé : `nil`, comme `systemVersion`.
        let other = "/Users/test/system-images/Library/Android/sdk/system-images/android-34/default/arm64-v8a"
        #expect(key(other) == nil)
        #expect(AndroidEmulatorScanner.systemVersion(imageSysdir: other) == nil)
    }

    @Test func keysDifferingOnlyInCaseAreEqual() throws {
        let a = try #require(key("system-images/android-36/Google_APIs/ARM64-v8a/"))
        let b = try #require(key("system-images/android-36/google_apis/arm64-v8a/"))
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(Set([a, b]).count == 1)
    }

    @Test func keysOfOtherImagesAreDifferent() throws {
        let a = try #require(key("system-images/android-36/google_apis/arm64-v8a/"))
        let b = try #require(key("system-images/android-36.1/google_apis/arm64-v8a/"))
        #expect(a != b)
    }
}
