import AppKit
import Foundation
import Testing
@testable import Soaro

/// Écran « Simulators and emulators » (T10) : route, rangée de la liste des outils, textes, règles de sources.
@Suite struct SimulatorsScreenTests {
    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func catalogEntry(_ key: String) throws -> [String: Any] {
        let catalog = try TranslationCatalog.loadCatalog(TranslationCatalogTests.localizable)
        let strings = try #require(catalog["strings"] as? [String: Any])
        return try #require(strings[key] as? [String: Any], "clé absente du catalogue : \(key)")
    }

    // MARK: Route

    @Test func theRouteExistsWithTitleSubtitleAndSymbol() throws {
        let route = try #require(CleanupRoute(rawValue: "simulators"))
        #expect(route == .simulators)
        #expect(route.title == "Simulators and emulators")
        #expect(route.subtitle == "iOS Simulators and Android emulators")
        #expect(route.systemImage == "ipad.and.iphone")
        #expect(NSImage(systemSymbolName: route.systemImage, accessibilityDescription: nil) != nil, "le symbole existe sur ce système")
        _ = try catalogEntry("Simulators and emulators")
        _ = try catalogEntry("iOS Simulators and Android emulators")
    }

    @Test func allTheNewScreenStringsAreInTheCatalogInNineLanguages() throws {
        let keys = ["Simulators and emulators", "iOS Simulators and Android emulators", "iOS Simulators", "Devices: %lld · %@",
                    "Measuring sizes…", "Inactive for more than", "%lld days", "Deleting…"]
        for key in keys {
            let entry = try catalogEntry(key)
            #expect(entry["variations"] == nil)
            let localizations = try #require(entry["localizations"] as? [String: Any])
            for language in TranslationCatalog.requiredTranslations {
                let unit = try #require((localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any], "\(key) / \(language)")
                let value = try #require(unit["value"] as? String)
                #expect(!value.isEmpty)
                #expect(TranslationCatalog.placeholders(in: value).byPosition.values.sorted()
                        == TranslationCatalog.placeholders(in: key).byPosition.values.sorted(), "\(key) / \(language)")
            }
        }
    }

    // MARK: Rangée de la liste des outils (S1)

    private let sdk = AndroidSDKLocation(path: "/Users/test/Library/Android/sdk", source: .defaultLocation)

    @Test(arguments: [
        (SimulatorToolDetection(devicesFolderExists: false, simctlPath: nil), false, false),
        (SimulatorToolDetection(devicesFolderExists: true, simctlPath: nil), false, true),
        (SimulatorToolDetection(devicesFolderExists: false, simctlPath: "/x/simctl"), false, true),
        (SimulatorToolDetection(devicesFolderExists: true, simctlPath: "/x/simctl"), false, true),
        (SimulatorToolDetection(devicesFolderExists: false, simctlPath: nil), true, true),
    ])
    func toolsRowVisibilityIsAPureFunctionOfDetectionAndDemo(detection: SimulatorToolDetection, demo: Bool, expected: Bool) {
        #expect(SimulatorToolDetection.showsToolsRow(detection: detection, androidSDK: nil, demo: demo) == expected)
    }

    @Test func theRowIsVisibleWhenOnlyTheAndroidSdkIsFound() {
        let none = SimulatorToolDetection(devicesFolderExists: false, simctlPath: nil)
        #expect(SimulatorToolDetection.showsToolsRow(detection: none, androidSDK: sdk, demo: false), "iOS absent, SDK trouvé : visible")
        #expect(!SimulatorToolDetection.showsToolsRow(detection: none, androidSDK: nil, demo: false), "les deux absents : cachée")
        #expect(SimulatorToolDetection.showsToolsRow(detection: none, androidSDK: nil, demo: true), "démo : visible")
        #expect(SimulatorToolDetection.showsToolsRow(detection: SimulatorToolDetection(devicesFolderExists: true, simctlPath: nil),
                                                     androidSDK: nil, demo: false), "iOS présent, pas de SDK : visible")
    }

    @Test func toolsRowIsHiddenUntilDetectionHasRun() {
        #expect(SimulatorToolDetection.showsToolsRow(detection: nil, androidSDK: nil, demo: false) == false)
        #expect(SimulatorToolDetection.showsToolsRow(detection: nil, androidSDK: nil, demo: true) == true)
        #expect(SimulatorToolDetection.showsToolsRow(detection: nil, androidSDK: sdk, demo: false) == true,
                "le SDK Android suffit même si la détection iOS n'a pas fini")
    }

    @Test func toolsListPutsTheRowBetweenInactiveProjectsAndUninstall() {
        #expect(CleanupRoute.toolRoutes(showSimulators: true) == [.largeFiles, .devProjects, .simulators, .uninstaller, .startup])
        #expect(CleanupRoute.toolRoutes(showSimulators: false) == [.largeFiles, .devProjects, .uninstaller, .startup])
    }

    // MARK: Texte d'en-tête

    @Test func headerSummaryReadsDevicesCountAndSize() {
        let locale = Locale(identifier: "en_US")
        #expect(SimulatorPresentation.headerSummary(count: 12, size: 31_400_000_000, locale: locale)
                == "Devices: 12 · \(Format.fileBytes(31_400_000_000, locale: locale))")
    }

    // MARK: Règles de sources

    @Test func theRealRunnerIsBuiltOnlyInDiagnosticsAndTheCleanupTab() throws {
        let sources = RepositoryRoot.url().appendingPathComponent("Sources")
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(files.count > 20)
        let allowed: Set<String> = ["Diagnostics.swift", "CleanupTab.swift", "RealCommandRunner.swift"]
        var found: Set<String> = []
        for file in files where try String(contentsOf: file, encoding: .utf8).contains("RealCommandRunner(") {
            found.insert(file.lastPathComponent)
        }
        #expect(found.isSubset(of: allowed), "RealCommandRunner( trouvé hors de l'endroit prévu : \(found.subtracting(allowed))")
        #expect(found.contains("CleanupTab.swift") && found.contains("Diagnostics.swift"))
    }

    @Test func theNewScreenUsesTheSupportingTextTokenAndNoFixedStyle() throws {
        let text = try source("Sources/Soaro/Views/SimulatorsView.swift")
        for forbidden in [".secondary", ".tertiary", ".quaternary", ".font(.system", "keyboardShortcut", "defaultAction",
                          "withAnimation", ".animation(", ".transition(", "onSubmit", "onKeyPress", "Process", "URLSession"] {
            #expect(!text.contains(forbidden), "\(forbidden) ne doit pas apparaître dans SimulatorsView.swift")
        }
        #expect(text.contains("supportingText"))
        #expect(!text.contains("supportingTextColor"), "le style existant `supportingText()` est réutilisé, pas recalculé")
        #expect(!text.contains("LocalizedStringKey"), "un texte déjà traduit s'affiche tel quel (jamais lu comme du Markdown)")
        #expect(!text.contains("revealInFinder"), "pas de « Show in Finder » dans le nouvel écran")
    }

    @Test func theDeleteButtonIsLiveBoundToTheModelAndBusyWhileDeleting() throws {
        let text = try source("Sources/Soaro/Views/SimulatorsView.swift")
        #expect(text.contains("destructive: true"), "la barre est teintée « danger »")
        #expect(text.contains("enabled: model.canDelete"))
        #expect(text.contains("busy: model.isDeleting"))
        #expect(text.contains("model.deleteSelected()"))
        #expect(text.contains("Deleting…"))
        #expect(!text.contains("enabled: false"))
        #expect(!text.contains("action: {}"))
        #expect(!text.contains("Delete disabled"), "l'ancien commentaire « Delete désactivé » est mis à jour")
    }

    @Test func theLimitMenuAndScanAgainAreDisabledWhileDeleting() throws {
        let text = try source("Sources/Soaro/Views/SimulatorsView.swift")
        #expect(text.contains(".disabled(model.isDeleting)"), "le menu de limite")
        #expect(text.contains(".disabled(!model.canScanAgain)"), "« Scan again » (canScanAgain est faux pendant une suppression)")
    }

    @Test func theRescanAfterABatchLivesInTheModelNotInTheView() throws {
        // Le scan demandé pendant une suppression est retenu et relancé par le modèle (testé dans SimulatorsDeletionTests).
        let text = try source("Sources/Soaro/Views/SimulatorsView.swift")
        #expect(!text.contains("onChange(of: model.isDeleting"))
        #expect(text.contains("model.progressMessage"), "« Deleting… » pendant une suppression, même sur un écran rouvert")
    }

    @MainActor
    @Test func theDeleteRuleIsThePureFunctionOfTheModel() {
        #expect(SimulatorsModel.canDelete(phase: .listed, androidPhase: .hidden, isMeasuring: false, selectedCount: 2, androidSelectedCount: 0, isDeleting: false))
        #expect(!SimulatorsModel.canDelete(phase: .listed, androidPhase: .hidden, isMeasuring: true, selectedCount: 2, androidSelectedCount: 0, isDeleting: false))
        #expect(!SimulatorsModel.canDelete(phase: .listed, androidPhase: .hidden, isMeasuring: false, selectedCount: 0, androidSelectedCount: 0, isDeleting: false))
        #expect(!SimulatorsModel.canDelete(phase: .listed, androidPhase: .hidden, isMeasuring: false, selectedCount: 2, androidSelectedCount: 0, isDeleting: true))
        #expect(!SimulatorsModel.canDelete(phase: .listing, androidPhase: .hidden, isMeasuring: false, selectedCount: 2, androidSelectedCount: 0, isDeleting: false))
    }

    // MARK: Disposition de l'écran (SL10 T11)

    typealias Phase = SimulatorsModel.Phase
    typealias Layout = SimulatorsScreen.Layout

    @Test(arguments: [
        (Phase.notScanned, Phase.notScanned), (.listing, .listing), (.listed, .listing), (.listing, .listed),
        (.listed, .notScanned), (.hidden, .listing), (.notScanned, .hidden), (.failed(.couldNotRead), .listing),
    ])
    func aSpinnerWhileEitherGroupIsNotScannedOrListing(ios: Phase, android: Phase) {
        #expect(SimulatorsScreen.layout(ios: ios, android: android) == .spinner)
    }

    @Test(arguments: [(Phase.hidden, Phase.hidden), (.hidden, .empty), (.empty, .hidden), (.empty, .empty)])
    func nothingFoundWhenBothGroupsAreHiddenOrEmpty(ios: Phase, android: Phase) {
        #expect(SimulatorsScreen.layout(ios: ios, android: android) == .nothingFound)
    }

    @Test(arguments: [(Phase.failed(.couldNotRead), Phase.hidden), (.failed(.notAnswering), .empty)])
    func theOnlyFailedGroupTakesTheWholeScreenForIos(ios: Phase, android: Phase) {
        #expect(SimulatorsScreen.layout(ios: ios, android: android) == .failedOnly(.ios))
    }

    @Test(arguments: [(Phase.hidden, Phase.failed(.couldNotRead)), (.empty, .failed(.couldNotRead))])
    func theOnlyFailedGroupTakesTheWholeScreenForAndroid(ios: Phase, android: Phase) {
        #expect(SimulatorsScreen.layout(ios: ios, android: android) == .failedOnly(.android))
    }

    @Test func aFailedGroupBesideAListedOneStaysASection() {
        #expect(SimulatorsScreen.layout(ios: .listed, android: .failed(.couldNotRead)) == .sections(ios: .listed, android: .failed))
        #expect(SimulatorsScreen.layout(ios: .failed(.couldNotRead), android: .listed) == .sections(ios: .failed, android: .listed))
        #expect(SimulatorsScreen.layout(ios: .failed(.couldNotRead), android: .failed(.couldNotRead)) == .sections(ios: .failed, android: .failed))
    }

    @Test func listedGroupsAreSectionsInTheOrderIosThenAndroid() {
        #expect(SimulatorsScreen.layout(ios: .listed, android: .listed) == .sections(ios: .listed, android: .listed))
        #expect(SimulatorsScreen.layout(ios: .listed, android: .hidden) == .sections(ios: .listed, android: .absent))
        #expect(SimulatorsScreen.layout(ios: .listed, android: .empty) == .sections(ios: .listed, android: .absent))
        #expect(SimulatorsScreen.layout(ios: .hidden, android: .listed) == .sections(ios: .absent, android: .listed))
        #expect(SimulatorsScreen.layout(ios: .empty, android: .listed) == .sections(ios: .absent, android: .listed))
    }

    @Test func theActionBarShowsWhenAtLeastOneGroupIsListed() {
        #expect(SimulatorsScreen.showsActionBar(.sections(ios: .listed, android: .absent)))
        #expect(SimulatorsScreen.showsActionBar(.sections(ios: .absent, android: .listed)))
        #expect(SimulatorsScreen.showsActionBar(.sections(ios: .failed, android: .listed)))
        #expect(!SimulatorsScreen.showsActionBar(.sections(ios: .failed, android: .failed)))
        #expect(!SimulatorsScreen.showsActionBar(.spinner))
        #expect(!SimulatorsScreen.showsActionBar(.nothingFound))
        #expect(!SimulatorsScreen.showsActionBar(.failedOnly(.android)))
    }

    @Test func theExplanationFooterIsOnlyUnderTheIosGroupWhenItIsListed() {
        typealias S = SimulatorsScreen.Section
        #expect(SimulatorsScreen.footers(ios: .listed, android: .absent) == .init(explanationUnderIos: true, smallCountUnder: .ios))
        #expect(SimulatorsScreen.footers(ios: .listed, android: .listed) == .init(explanationUnderIos: true, smallCountUnder: .android))
        #expect(SimulatorsScreen.footers(ios: .listed, android: .failed) == .init(explanationUnderIos: true, smallCountUnder: .android))
        // Android seul : plus d'explication (« are pre-selected » serait faux), le décompte des petits appareils reste.
        #expect(SimulatorsScreen.footers(ios: .absent, android: .listed) == .init(explanationUnderIos: false, smallCountUnder: .android))
        // Un groupe iOS en échec n'explique rien non plus.
        #expect(SimulatorsScreen.footers(ios: .failed, android: .listed) == .init(explanationUnderIos: false, smallCountUnder: .android))
        #expect(SimulatorsScreen.footers(ios: .absent, android: .absent) == .init(explanationUnderIos: false, smallCountUnder: nil))
    }

    @Test func theViewUsesTheFooterRuleAndReusesOnlyExistingStrings() throws {
        let text = try source("Sources/Soaro/Views/SimulatorsView.swift")
        #expect(text.contains("SimulatorsScreen.footers(ios:"))
        #expect(text.contains("SimulatorPresentation.explanationFooter"))
        #expect(text.contains("SimulatorPresentation.smallDevicesFooter"))
    }

    @MainActor
    @Test func theDeleteRuleAcceptsACheckedAndroidRowInEitherCombination() {
        #expect(SimulatorsModel.canDelete(phase: .listed, androidPhase: .listed, isMeasuring: false, selectedCount: 1, androidSelectedCount: 0, isDeleting: false))
        #expect(SimulatorsModel.canDelete(phase: .listed, androidPhase: .listed, isMeasuring: false, selectedCount: 1, androidSelectedCount: 1, isDeleting: false), "SL11")
        #expect(SimulatorsModel.canDelete(phase: .hidden, androidPhase: .listed, isMeasuring: false, selectedCount: 0, androidSelectedCount: 1, isDeleting: false), "Android seul")
    }

    @Test func theScreenShowsBothSectionsInOrderAndTheAndroidRowReadsNameThenApi() throws {
        let text = try source("Sources/Soaro/Views/SimulatorsView.swift")
        #expect(text.contains("SectionHeader(title: \"iOS Simulators\")"))
        #expect(text.contains("SectionHeader(title: \"Android emulators\")"))
        #expect(text.contains("SimulatorsScreen.layout(ios: model.phase, android: model.androidPhase)"))
        #expect(text.contains("AndroidEmulatorPresentation.systemLabel"))
        let ios = try #require(text.range(of: "SectionHeader(title: \"iOS Simulators\")"))
        let android = try #require(text.range(of: "SectionHeader(title: \"Android emulators\")"))
        #expect(ios.lowerBound < android.lowerBound, "iOS d'abord, puis Android")
    }

    @Test func theToolsRowLooksForTheSdkOffTheMainActorWithTheRealEnvironment() throws {
        let text = try source("Sources/Soaro/Views/CleanupTab.swift")
        #expect(text.contains("ToolLocator.androidSDK(environment: ProcessInfo.processInfo.environment"))
        #expect(text.contains("showsToolsRow(detection: simulatorDetection, androidSDK: androidSDK"))
        #expect(text.contains("Task.detached"))
    }

    @Test func theViewNoLongerSaysDeleteIsDisabled() throws {
        let text = try source("Sources/Soaro/Views/SimulatorsView.swift")
        #expect(!text.contains("lecture seule"), "l'écran n'est plus en lecture seule")
    }

    @Test func screenshotsScriptCoversTheNewTool() throws {
        #expect(try source("scripts/make-screenshots.sh").contains("cleanup:simulators"))
    }

    @Test func noStringLiteralOfTheScreenUsesTheWordRuntime() throws {
        // Le mot ne doit pas apparaître dans un texte affiché (les identifiants du code, eux, le portent).
        let text = try source("Sources/Soaro/Views/SimulatorsView.swift")
        let literals = try NSRegularExpression(pattern: #""[^"\n]*""#)
        let ns = text as NSString
        for match in literals.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            #expect(!ns.substring(with: match.range).localizedCaseInsensitiveContains("runtime"), "\(ns.substring(with: match.range))")
        }
    }
}
