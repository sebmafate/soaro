import Foundation
import Testing
@testable import Soaro

/// Bilan d'un lot de suppressions et texte du toast (SL9 T4) : fonctions pures, locale passée.
/// Les attendus sont les textes anglais (clés du catalogue), comme dans `SimulatorPresentationTests`.
@Suite(.serialized) struct SimulatorRemovalSummaryTests {
    let locale = Locale(identifier: "en_US")
    static let gb: UInt64 = 1_000_000_000

    /// Fait tourner le lot sur des cibles `u1`, `u2`… avec un résultat prévu par cible. Rend le bilan et les cibles essayées.
    func batch(_ results: [SimulatorRemovalResult], cancelAfter: Int? = nil) -> (summary: SimulatorRemovalSummary, tried: [String]) {
        let targets = results.indices.map { "u\($0 + 1)" }
        var tried: [String] = []
        let summary = SimulatorRemovalSummary.run(
            targets: targets,
            isCancelled: { if let cancelAfter { return tried.count >= cancelAfter } else { return false } },
            remove: { target in
                tried.append(target)
                return results[targets.firstIndex(of: target)!]
            })
        return (summary, tried)
    }

    func freed(_ value: UInt64) -> String { "\(Format.fileBytes(value, locale: locale)) freed" }

    // MARK: Textes (table)

    @Test func allRemovedShowsOnlyTheFreedSpace() {
        let (summary, tried) = batch([.removed(freed: 3 * Self.gb), .removed(freed: 2 * Self.gb)])
        #expect(summary.removedCount == 2)
        #expect(summary.freed == 5 * Self.gb)
        #expect(summary.failureCount == 0)
        #expect(!summary.timedOut)
        #expect(tried == ["u1", "u2"])
        #expect(summary.toast(locale: locale) == freed(5 * Self.gb))
    }

    @Test func oneRunningDeviceAloneShowsItsNameWithoutTheFreedPart() {
        let (summary, _) = batch([.running(name: "iPhone 15")])
        #expect(summary.removedCount == 0 && summary.failureCount == 1 && summary.runningNames == ["iPhone 15"])
        #expect(summary.toast(locale: locale) == "“iPhone 15” is running: quit it first.")
    }

    @Test func oneRunningPlusTwoRemovedKeepsTheFreedPartFirst() {
        let (summary, _) = batch([.removed(freed: 3 * Self.gb), .running(name: "iPhone 15"), .removed(freed: Self.gb)])
        #expect(summary.removedCount == 2 && summary.failureCount == 1)
        #expect(summary.toast(locale: locale) == "\(freed(4 * Self.gb)) · “iPhone 15” is running: quit it first.")
    }

    @Test func twoFailuresShowTheCountAndNoFreedPart() {
        let (summary, _) = batch([.failed, .refused])
        #expect(summary.failureCount == 2 && summary.removedCount == 0)
        #expect(summary.toast(locale: locale) == "Devices that could not be removed: 2")
    }

    @Test func runningPlusAnotherFailureShowsTheCountOfEveryDeviceNotRemoved() {
        let (summary, _) = batch([.running(name: "iPhone 15"), .failed])
        #expect(summary.failureCount == 2 && summary.runningNames == ["iPhone 15"])
        #expect(summary.toast(locale: locale) == "Devices that could not be removed: 2")
    }

    @Test func twoRunningDevicesShowTheCountNotNames() {
        let (summary, _) = batch([.running(name: "iPhone 15"), .running(name: "iPad")])
        #expect(summary.toast(locale: locale) == "Devices that could not be removed: 2")
    }

    @Test func aFailureAfterARemovalKeepsTheFreedPartThenTheCount() {
        let (summary, _) = batch([.removed(freed: 2 * Self.gb), .failed, .failed])
        #expect(summary.toast(locale: locale) == "\(freed(2 * Self.gb)) · Devices that could not be removed: 2")
    }

    @Test func aTimeoutAfterOneRemovalStopsTheBatchAndShowsTheDidNotAnswerText() {
        let (summary, tried) = batch([.removed(freed: 3 * Self.gb), .timedOut, .removed(freed: Self.gb), .removed(freed: Self.gb)])
        #expect(tried == ["u1", "u2"], "les appareils restants ne sont pas essayés")
        #expect(summary.timedOut)
        #expect(summary.removedCount == 1)
        #expect(summary.toast(locale: locale)
                == "\(freed(3 * Self.gb)) · Xcode’s simulator service did not answer. Try again in a moment.")
    }

    @Test func aTimeoutWithNothingRemovedShowsOnlyTheDidNotAnswerText() {
        let (summary, tried) = batch([.timedOut, .removed(freed: Self.gb)])
        #expect(tried == ["u1"])
        #expect(summary.toast(locale: locale) == "Xcode’s simulator service did not answer. Try again in a moment.")
    }

    @Test func aTimeoutWinsOverRunningAndFailureTexts() {
        let (summary, _) = batch([.running(name: "iPhone 15"), .failed, .timedOut])
        #expect(summary.toast(locale: locale) == "Xcode’s simulator service did not answer. Try again in a moment.")
    }

    @Test func couldNotCheckStopsTheBatchAndTheRemainingTargetsCountAsFailures() {
        let (summary, tried) = batch([.removed(freed: Self.gb), .couldNotCheck, .removed(freed: Self.gb), .removed(freed: Self.gb)])
        #expect(tried == ["u1", "u2"])
        #expect(summary.removedCount == 1)
        #expect(summary.failureCount == 3, "celui qui n'a pas pu être vérifié et les deux jamais essayés")
        #expect(!summary.timedOut)
        #expect(summary.toast(locale: locale) == "\(freed(Self.gb)) · Devices that could not be removed: 3")
    }

    @Test func couldNotCheckOnTheFirstTargetCountsEveryTargetAsAFailure() {
        let (summary, tried) = batch([.couldNotCheck, .failed, .failed])
        #expect(tried == ["u1"])
        #expect(summary.failureCount == 3)
        #expect(summary.toast(locale: locale) == "Devices that could not be removed: 3")
    }

    @Test func aDeviceAlreadyGoneIsNeitherARemovalNorAFailure() {
        let (summary, _) = batch([.alreadyGone, .removed(freed: Self.gb), .alreadyGone])
        #expect(summary.removedCount == 1 && summary.failureCount == 0)
        #expect(summary.toast(locale: locale) == freed(Self.gb))
    }

    @Test func allAlreadyGoneShowsZeroFreed() {
        let (summary, _) = batch([.alreadyGone, .alreadyGone])
        #expect(summary.removedCount == 0 && summary.failureCount == 0)
        #expect(summary.toast(locale: locale) == freed(0))
        #expect(summary.toast(locale: locale).contains(Format.fileBytes(0, locale: locale)))
    }

    @Test func aRemovalThatFreedNothingStillCountsAsRemoved() {
        let (summary, _) = batch([.removed(freed: 0)])
        #expect(summary.removedCount == 1)
        #expect(summary.toast(locale: locale) == freed(0))
    }

    // MARK: Annulation (bouton Retour)

    @Test func cancellationIsCheckedBeforeEachTargetAndTheUntriedOnesAreNotClaimedAsRemoved() {
        let (summary, tried) = batch([.removed(freed: Self.gb), .removed(freed: Self.gb), .removed(freed: Self.gb)], cancelAfter: 1)
        #expect(tried == ["u1"])
        #expect(summary.removedCount == 1)
        #expect(summary.untriedCount == 2)
        #expect(summary.failureCount == 0, "pas des échecs, mais pas supprimés non plus")
        #expect(summary.toast(locale: locale) == "\(freed(Self.gb)) · Devices that could not be removed: 2")
    }

    @Test func backBeforeAnyTargetAttemptsNothingAndHasNothingToSay() {
        let (summary, tried) = batch([.removed(freed: Self.gb), .removed(freed: Self.gb)], cancelAfter: 0)
        #expect(tried.isEmpty)
        #expect(summary.untriedCount == 2 && summary.attemptedCount == 0)
        #expect(summary.toast(locale: locale).isEmpty, "ni « Zero KB freed » ni un compte : rien n'a été tenté")
    }

    @Test func backAfterAFailureCountsTheFailedAndTheUntriedTogether() {
        let (summary, _) = batch([.failed, .removed(freed: Self.gb), .removed(freed: Self.gb)], cancelAfter: 1)
        #expect(summary.toast(locale: locale) == "Devices that could not be removed: 3")
    }

    @Test func backAfterARunningDeviceWithAnUntriedOneShowsTheCountNotTheName() {
        let (summary, _) = batch([.running(name: "iPhone 15"), .removed(freed: Self.gb)], cancelAfter: 1)
        #expect(summary.toast(locale: locale) == "Devices that could not be removed: 2")
    }

    @Test func backAfterOnlyAlreadyGoneDevicesDoesNotClaimSuccess() {
        let (summary, _) = batch([.alreadyGone, .removed(freed: Self.gb), .removed(freed: Self.gb)], cancelAfter: 1)
        #expect(summary.attemptedCount == 1)
        #expect(summary.toast(locale: locale) == "Devices that could not be removed: 2")
    }

    @Test func aTimeoutDoesNotCountTheUntriedAndAFullRunHasNone() {
        let (timedOut, _) = batch([.timedOut, .removed(freed: Self.gb)])
        #expect(timedOut.untriedCount == 0)
        let (full, _) = batch([.removed(freed: Self.gb), .failed])
        #expect(full.untriedCount == 0)
    }

    @Test func noTargetNeverCallsTheRemover() {
        let (summary, tried) = batch([])
        #expect(tried.isEmpty)
        #expect(summary.removedCount == 0)
    }

    // MARK: Catalogue

    @Test func theTwoNewKeysAreInTheCatalogInNineLanguagesWithMatchingPlaceholders() throws {
        let catalog = try TranslationCatalog.loadCatalog(TranslationCatalogTests.localizable)
        let strings = try #require(catalog["strings"] as? [String: Any])
        for key in ["“%@” is running: quit it first.", "Devices that could not be removed: %lld"] {
            let entry = try #require(strings[key] as? [String: Any], "clé absente : \(key)")
            #expect(entry["variations"] == nil)
            let localizations = try #require(entry["localizations"] as? [String: Any])
            #expect(Set(localizations.keys) == Set(TranslationCatalog.requiredTranslations))
            for language in TranslationCatalog.requiredTranslations {
                let unit = try #require((localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any], "\(key) / \(language)")
                let value = try #require(unit["value"] as? String)
                #expect(!value.isEmpty)
                #expect(TranslationCatalog.placeholders(in: value).byPosition == TranslationCatalog.placeholders(in: key).byPosition,
                        "\(key) / \(language)")
            }
        }
    }
}
