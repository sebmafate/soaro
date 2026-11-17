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

    @Test(arguments: [
        (SimulatorToolDetection(devicesFolderExists: false, simctlPath: nil), false, false),
        (SimulatorToolDetection(devicesFolderExists: true, simctlPath: nil), false, true),
        (SimulatorToolDetection(devicesFolderExists: false, simctlPath: "/x/simctl"), false, true),
        (SimulatorToolDetection(devicesFolderExists: true, simctlPath: "/x/simctl"), false, true),
        (SimulatorToolDetection(devicesFolderExists: false, simctlPath: nil), true, true),
    ])
    func toolsRowVisibilityIsAPureFunctionOfDetectionAndDemo(detection: SimulatorToolDetection, demo: Bool, expected: Bool) {
        #expect(SimulatorToolDetection.showsToolsRow(detection: detection, demo: demo) == expected)
    }

    @Test func toolsRowIsHiddenUntilDetectionHasRun() {
        #expect(SimulatorToolDetection.showsToolsRow(detection: nil, demo: false) == false)
        #expect(SimulatorToolDetection.showsToolsRow(detection: nil, demo: true) == true)
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

    @Test func aScreenLeftDuringADeletionRescansWhenItEnds() throws {
        // Retour pendant la suppression : l'écran « non scanné » se relance à la fin du lot s'il est de nouveau affiché.
        let text = try source("Sources/Soaro/Views/SimulatorsView.swift")
        #expect(text.contains("onChange(of: model.isDeleting"))
    }

    @MainActor
    @Test func theDeleteRuleIsThePureFunctionOfTheModel() {
        #expect(SimulatorsModel.canDelete(phase: .listed, isMeasuring: false, selectedCount: 2, isDeleting: false))
        #expect(!SimulatorsModel.canDelete(phase: .listed, isMeasuring: true, selectedCount: 2, isDeleting: false))
        #expect(!SimulatorsModel.canDelete(phase: .listed, isMeasuring: false, selectedCount: 0, isDeleting: false))
        #expect(!SimulatorsModel.canDelete(phase: .listed, isMeasuring: false, selectedCount: 2, isDeleting: true))
        #expect(!SimulatorsModel.canDelete(phase: .listing, isMeasuring: false, selectedCount: 2, isDeleting: false))
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
