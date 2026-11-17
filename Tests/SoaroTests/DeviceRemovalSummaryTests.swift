import Foundation
import Testing
@testable import Soaro

/// Lot mixte iOS et Android et texte du toast (SL11 T4) : fonctions pures, locale passée, aucun disque.
/// Les attendus sont les textes anglais (clés du catalogue, aucune clé nouvelle).
@Suite(.serialized) struct DeviceRemovalSummaryTests {
    let locale = Locale(identifier: "en_US")
    static let gb: UInt64 = 1_000_000_000
    static let xcodeMessage = "Xcode’s simulator service did not answer. Try again in a moment."

    func freed(_ value: UInt64) -> String { "\(Format.fileBytes(value, locale: locale)) freed" }

    struct Run {
        let summary: DeviceRemovalSummary
        /// Les cibles essayées, dans l'ordre : `u1`… pour iOS, `Test_Avd_1`… pour Android.
        let tried: [String]
    }

    /// Fait tourner un lot : un résultat prévu par cible iOS (`u1`, `u2`…) puis par cible Android (`Test_Avd_1`…).
    /// `cancelAfter` : le bouton Retour arrive après ce nombre de cibles essayées.
    func batch(ios: [SimulatorRemovalResult], android: [SimulatorRemovalResult], cancelAfter: Int? = nil) -> Run {
        let iosTargets = ios.indices.map { "u\($0 + 1)" }
        let androidTargets = android.indices.map {
            AndroidRemovalTarget(name: "Test_Avd_\($0 + 1)", folder: URL(fileURLWithPath: "/Users/test/.android/avd/Test_Avd_\($0 + 1).avd"))
        }
        var tried: [String] = []
        let summary = DeviceRemovalSummary.run(
            iosTargets: iosTargets, androidTargets: androidTargets,
            isCancelled: { if let cancelAfter { return tried.count >= cancelAfter } else { return false } },
            removeIOS: { udid in
                tried.append(udid)
                return ios[iosTargets.firstIndex(of: udid)!]
            },
            removeAndroid: { target in
                tried.append(target.name)
                return android[androidTargets.firstIndex(of: target)!]
            })
        return Run(summary: summary, tried: tried)
    }

    // MARK: Textes (table)

    @Test func androidOnlyRemovedShowsTheFreedSpace() {
        let run = batch(ios: [], android: [.removed(freed: 4 * Self.gb), .removed(freed: Self.gb)])
        #expect(run.summary.toast(locale: locale) == freed(5 * Self.gb))
        #expect(run.tried == ["Test_Avd_1", "Test_Avd_2"])
    }

    @Test func oneAvdRunningAtActionTimeAloneShowsItsNameWithoutTheFreedPart() {
        let run = batch(ios: [], android: [.running(name: "Test Phone A")])
        #expect(run.summary.toast(locale: locale) == "“Test Phone A” is running: quit it first.")
    }

    @Test func oneIosRemovedAndOneAvdRunningShowsTheFreedPartThenTheName() {
        let run = batch(ios: [.removed(freed: 3 * Self.gb)], android: [.running(name: "Test Phone A")])
        #expect(run.summary.toast(locale: locale) == "\(freed(3 * Self.gb)) · “Test Phone A” is running: quit it first.")
    }

    @Test func oneIosRunningAndOneAvdRunningShowsTheCountNotAName() {
        let run = batch(ios: [.running(name: "Test Phone I")], android: [.running(name: "Test Phone A")])
        #expect(run.summary.toast(locale: locale) == "Devices that could not be removed: 2")
    }

    @Test func iosTimedOutThenOneAndroidRemovedStillTriesTheAndroidGroup() {
        let run = batch(ios: [.timedOut, .removed(freed: 9)], android: [.removed(freed: 2 * Self.gb)])
        #expect(run.tried == ["u1", "Test_Avd_1"], "le délai arrête le reste d'iOS mais pas Android")
        #expect(run.summary.toast(locale: locale) == "\(freed(2 * Self.gb)) · \(Self.xcodeMessage)")
    }

    @Test func iosTimedOutAndOneAndroidFailureShowsBothMessagesWithoutTheFreedPart() {
        let run = batch(ios: [.timedOut], android: [.failed])
        #expect(run.summary.toast(locale: locale) == "\(Self.xcodeMessage) · Devices that could not be removed: 1")
    }

    @Test func iosTimedOutAloneKeepsTheOldIosOnlyText() {
        let run = batch(ios: [.timedOut], android: [])
        #expect(run.summary.toast(locale: locale) == Self.xcodeMessage)
    }

    @Test func iosTimedOutAndAnAndroidAvdRunningCountsItAsNotRemoved() {
        let run = batch(ios: [.timedOut], android: [.running(name: "Test Phone A")])
        #expect(run.summary.toast(locale: locale) == "\(Self.xcodeMessage) · Devices that could not be removed: 1")
    }

    @Test func iosCouldNotCheckOnTwoTargetsDoesNotBlockTheAndroidGroup() {
        let run = batch(ios: [.couldNotCheck, .removed(freed: 1)], android: [.removed(freed: 2 * Self.gb)])
        #expect(run.tried == ["u1", "Test_Avd_1"])
        #expect(run.summary.toast(locale: locale) == "\(freed(2 * Self.gb)) · Devices that could not be removed: 2")
    }

    @Test func androidPsUnavailableOnTwoTargetsStopsThatGroupAndTheSecondIsNotTried() {
        let run = batch(ios: [], android: [.couldNotCheck, .removed(freed: Self.gb)])
        #expect(run.tried == ["Test_Avd_1"])
        #expect(run.summary.toast(locale: locale) == "Devices that could not be removed: 2")
    }

    @Test func androidFailureDoesNotStopTheNextAndroidTargetNorTheIosGroupBefore() {
        let run = batch(ios: [.removed(freed: Self.gb)], android: [.failed, .removed(freed: 2 * Self.gb)])
        #expect(run.tried == ["u1", "Test_Avd_1", "Test_Avd_2"])
        #expect(run.summary.toast(locale: locale) == "\(freed(3 * Self.gb)) · Devices that could not be removed: 1")
    }

    @Test func backAfterTheLastIosTargetLeavesTheAndroidTargetUntried() {
        let run = batch(ios: [.removed(freed: 3 * Self.gb)], android: [.removed(freed: Self.gb)], cancelAfter: 1)
        #expect(run.tried == ["u1"])
        #expect(run.summary.toast(locale: locale) == "\(freed(3 * Self.gb)) · Devices that could not be removed: 1")
    }

    @Test func backBeforeAnythingGivesAnEmptyToast() {
        let run = batch(ios: [.removed(freed: Self.gb)], android: [.removed(freed: Self.gb)], cancelAfter: 0)
        #expect(run.tried.isEmpty)
        #expect(run.summary.toast(locale: locale).isEmpty)
    }

    @Test func backInTheMiddleOfTheAndroidGroupCountsTheRestAsUntried() {
        let run = batch(ios: [], android: [.removed(freed: 2 * Self.gb), .removed(freed: Self.gb)], cancelAfter: 1)
        #expect(run.tried == ["Test_Avd_1"])
        #expect(run.summary.toast(locale: locale) == "\(freed(2 * Self.gb)) · Devices that could not be removed: 1")
    }

    @Test func everythingAlreadyGoneShowsZeroFreed() {
        let run = batch(ios: [.alreadyGone], android: [.alreadyGone])
        #expect(run.summary.toast(locale: locale) == freed(0))
        #expect(run.summary.toast(locale: locale) == "\(Format.fileBytes(0, locale: locale)) freed")
    }

    @Test func iosOnlyBatchGivesTheSameTextAsTheIosOnlySummary() {
        // Le comportement iOS seul ne change pas : même texte que `SimulatorRemovalSummary`.
        let results: [[SimulatorRemovalResult]] = [
            [.removed(freed: Self.gb)], [.running(name: "Test Phone I")], [.failed, .refused], [.timedOut],
            [.removed(freed: Self.gb), .running(name: "Test Phone I")], [.couldNotCheck, .failed],
        ]
        for ios in results {
            let targets = ios.indices.map { "u\($0 + 1)" }
            let old = SimulatorRemovalSummary.run(targets: targets, isCancelled: { false }) { ios[targets.firstIndex(of: $0)!] }
            #expect(batch(ios: ios, android: []).summary.toast(locale: locale) == old.toast(locale: locale), "\(ios)")
        }
    }

    @Test func theIosGroupAlwaysRunsBeforeTheAndroidGroup() {
        let run = batch(ios: [.removed(freed: 1), .removed(freed: 1)], android: [.removed(freed: 1), .removed(freed: 1)])
        #expect(run.tried == ["u1", "u2", "Test_Avd_1", "Test_Avd_2"])
    }
}
