import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import Soaro

/// SL22 : la liste de Réglages que l'on réordonne (poignées, actions d'accessibilité, menu contextuel), l'aperçu au-dessus, les textes.
/// Le glisser réel à la souris, VoiceOver et la vraie barre de menus ne se testent pas hors écran : voir la section « Not verified » de PLAN.md.
@Suite struct MenuBarOrderSettingsSourceTests {
    private func read(_ path: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
    }

    /// Le texte de la section « In the menu bar » (jusqu'à la section suivante).
    private func menuBarSection() throws -> String {
        let source = try read("Sources/Soaro/Views/SettingsView.swift")
        let start = try #require(source.range(of: "Section(\"In the menu bar\")"))
        let end = try #require(source.range(of: "Section(\"Value colors\")"))
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func settingsSource() throws -> String { try read("Sources/Soaro/Views/SettingsView.swift") }

    @Test func thePreviewIsInTheSectionAboveTheListAndBelowTheStylePicker() throws {
        let section = try menuBarSection()
        let picker = try #require(section.range(of: "Picker(\"Style\""))
        let preview = try #require(section.range(of: "MenuBarPreview("))
        let list = try #require(section.range(of: "ForEach("))
        #expect(picker.lowerBound < preview.lowerBound, "le style juste au-dessus de l'aperçu qu'il change")
        #expect(preview.lowerBound < list.lowerBound, "l'aperçu est AU-DESSUS de la liste")
    }

    @Test func thePreviewReadsTheSameSettingsAndDataAsTheRealLabel() throws {
        let source = try settingsSource()
        for needle in ["MenuBarItem.items(", "order: MenuBarOrder(parsing:", "state.snapshot", "DemoData.snapshot()", "MenuBarFlag.countryCode(", "thresholds: thresholds",
                       "compact: compact", "state.worstSeverity"] {
            #expect(source.contains(needle), "SettingsView ne contient pas \(needle)")
        }
    }

    @Test func eachRowHasAHandleADragSourceAndADropTarget() throws {
        let section = try menuBarSection() + (try settingsSource())
        #expect(section.contains("line.3.horizontal"), "la poignée")
        #expect(section.contains(".draggable("))
        #expect(section.contains(".dropDestination(for: MenuBarMeasureDrag.self"))
        #expect(section.contains("Drag to change the order"), "l'aide de la poignée")
    }

    @Test func theRowsAreNotReorderedWithOnMoveWhichNeedsAListNotAForm() throws {
        // Une Form groupée n'est pas une liste de lignes (NSTableView) : .onMove n'y a rien à quoi s'accrocher. Voir PLAN.md, SL22.
        #expect(!(try settingsSource()).contains(".onMove"))
    }

    @Test func eachRowOffersMoveUpAndMoveDownToVoiceOverAndToTheMouse() throws {
        let source = try settingsSource()
        #expect(source.contains(".accessibilityAction(named: \"Move up\")"))
        #expect(source.contains(".accessibilityAction(named: \"Move down\")"))
        #expect(source.contains(".contextMenu"))
        #expect(source.contains("Button(\"Move up\")") && source.contains("Button(\"Move down\")"))
        #expect(source.contains(".accessibilityValue(MenuBarOrder.positionText("), "la position, « 2 of 6 », est la valeur de la poignée")
        #expect(source.contains(".accessibilityLabel(Text(measure.title))") && source.contains(".accessibilityHint("), "le nom de la mesure et l'aide")
        #expect(source.contains("MenuBarOrder.positionText("))
        #expect(source.contains("AccessibilityNotification.Announcement"))
    }

    @Test func theToggleKeepsItsOwnAccessibilityValueSoItsOnOffStateIsNotOverwritten() throws {
        let section = try menuBarSection() + (try settingsSource())
        #expect(!section.contains("accessibilityElement(children: .combine)"), "combiner la ligne écraserait la valeur de l'interrupteur par « 2 of 6 »")
        #expect(section.contains("Toggle(isOn: isOn(measure))"))
    }

    @Test func noAnimatedReorderingWhenReduceMotionIsOn() throws {
        let source = try settingsSource()
        #expect(source.contains("accessibilityReduceMotion"))
        #expect(source.contains("MenuBarOrder.reorderAnimation(reduceMotion:"))
    }

    @Test func aMoveWritesTheNewOrderThroughTheSetting() throws {
        let source = try settingsSource()
        #expect(source.contains("@AppStorage(SettingsKey.menuBarOrder)"))
        #expect(source.contains("MenuBarOrder.edit(stored:"))
    }

    @Test func theBatteryRowStillExistsOnlyWithABattery() throws {
        let source = try settingsSource()
        #expect(source.contains("visible(hasBattery: state.hasBattery)"))
    }

    @Test func theSixTogglesStillWriteTheSameKeys() throws {
        let source = try settingsSource()
        for key in ["menuBarCPU", "menuBarGPU", "menuBarMemory", "menuBarDisk", "menuBarBattery", "menuBarNetwork", "menuBarCompact"] {
            #expect(source.contains("@AppStorage(SettingsKey.\(key))"), Comment(rawValue: key))
        }
    }

    @Test func noKeyboardShortcutAndNoKeyPressHandlerIsAdded() throws {
        for path in ["Sources/Soaro/Views/SettingsView.swift", "Sources/Soaro/Views/MenuBarPreview.swift", "Sources/Soaro/Views/MenuBarOrder.swift"] {
            let source = try read(path)
            for forbidden in ["keyboardShortcut", "defaultAction", "onKeyPress", "onSubmit"] {
                #expect(!source.contains(forbidden), "\(forbidden) dans \(path)")
            }
        }
    }

    @Test func theDragTypeIsDeclaredInTheAppInfoPlist() throws {
        #expect(UTType.menuBarMeasure.identifier == "app.soaro.menu-bar-measure")
        let script = try read("scripts/build-app.sh")
        #expect(script.contains("UTExportedTypeDeclarations"))
        #expect(script.contains("app.soaro.menu-bar-measure"))
        #expect(script.contains("public.data"))
    }

    @Test func noNetworkAndNoFileAccessInTheNewFiles() throws {
        for path in ["Sources/Soaro/Views/MenuBarPreview.swift", "Sources/Soaro/Views/MenuBarOrder.swift"] {
            let source = try read(path)
            for word in ["URLSession", "NWConnection", "Process(", "FileManager", "Data(contentsOf", "refreshPublicIP"] {
                #expect(!source.contains(word), "\(path) mentionne \(word)")
            }
        }
    }
}

@Suite struct MenuBarOrderBehaviourTests {
    @Test func theDragPayloadRoundTripsForEveryMeasureAndCarriesOnlyTheId() throws {
        for measure in MenuBarMeasure.allCases {
            let data = try JSONEncoder().encode(MenuBarMeasureDrag(measure: measure))
            #expect(try JSONDecoder().decode(MenuBarMeasureDrag.self, from: data).measure == measure)
            #expect(String(decoding: data, as: UTF8.self).contains(measure.rawValue))
        }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(MenuBarMeasureDrag.self, from: Data("{\"measure\":\"nonsense\"}".utf8)) }
    }

    @Test func noReorderAnimationWithReduceMotionAndOneWithout() {
        #expect(MenuBarOrder.reorderAnimation(reduceMotion: true) == nil)
        #expect(MenuBarOrder.reorderAnimation(reduceMotion: false) != nil)
    }

    @Test func theAnnouncementNamesTheRowAndItsNewPosition() {
        #expect(MenuBarOrder.announcement(title: "CPU load", index: 1, of: 6) == "CPU load, 2 of 6")
        #expect(MenuBarOrder.announcement(title: "Battery level", index: 4, of: 5) == "Battery level, 5 of 5")
    }

    @Test func everyMeasureHasATitleAndAShortName() {
        for measure in MenuBarMeasure.allCases {
            #expect(!measure.title.isEmpty && !measure.shortName.isEmpty)
        }
        #expect(MenuBarMeasure.cpu.title == "CPU load" && MenuBarMeasure.network.title == "Network speed")
    }

    @Test func aMoveFromTheVisibleListNeverLandsOnAHiddenBatteryRow() {
        // Sans batterie, la ligne n'existe pas : monter la ligne juste sous elle doit changer l'ordre visible.
        var order = MenuBarOrder(parsing: "cpu,battery,gpu,memory,disk,network")
        let shown = Set(order.visible(hasBattery: false))
        order.moveUp(.gpu, among: shown)
        #expect(order.visible(hasBattery: false) == [.gpu, .cpu, .memory, .disk, .network])
        order.moveDown(.gpu, among: shown)
        #expect(order.visible(hasBattery: false) == [.cpu, .gpu, .memory, .disk, .network])
        #expect(order.measures.contains(.battery), "la batterie garde sa place pour son retour")
    }
}

/// Les nouveaux textes sont dans le catalogue, dans les neuf langues (l'anglais est la clé), avec les mêmes marqueurs de format.
/// Écrits avec l'aide d'une IA, comme ceux des tranches précédentes : à relire par l'auteur.
@Suite struct MenuBarOrderStringsTests {
    static let newKeys = [
        "Preview",
        "Nothing selected: only the Soaro icon shows",
        "Menu bar preview: %@",
        "Move up",
        "Move down",
        "%lld of %lld",
        "Drag to change the order",
        "Drag the handles to change the order. The Soaro icon always comes first.",
    ]

    @Test func everyNewKeyIsInTheCatalogInEveryLanguageWithMatchingMarkers() throws {
        let strings = try DockerStringsTests.catalogStrings()
        for key in Self.newKeys {
            let entry = strings[key] as? [String: Any]
            #expect(entry != nil, "clé absente du catalogue : \(key.debugDescription)")
            let localizations = entry?["localizations"] as? [String: Any] ?? [:]
            for language in TranslationCatalog.requiredTranslations {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String ?? ""
                #expect(!value.isEmpty, "\(key.debugDescription) / \(language)")
                #expect(unit?["state"] as? String == "translated", "\(key.debugDescription) / \(language)")
                #expect(TranslationCatalog.placeholderProblems(source: key, translation: value).isEmpty, "\(key.debugDescription) / \(language)")
                #expect((localizations[language] as? [String: Any])?["variations"] == nil)
                if language != "en", key != "%lld of %lld" { #expect(value != key, "\(key.debugDescription) / \(language) : pas traduit") }
            }
        }
    }

    @Test func theProductNameStaysSoaroInTheTextsThatNameIt() throws {
        let strings = try DockerStringsTests.catalogStrings()
        for key in Self.newKeys where key.contains("Soaro") {
            let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            for language in TranslationCatalog.requiredTranslations {
                let value = ((localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String ?? ""
                #expect(value.contains("Soaro"), "\(key.debugDescription) / \(language)")
            }
        }
    }

    @Test func theNewKeysAreTheOnesTheSourcesUse() throws {
        let root = RepositoryRoot.url()
        let used = try ["Sources/Soaro/Views/SettingsView.swift", "Sources/Soaro/Views/MenuBarPreview.swift", "Sources/Soaro/Views/MenuBarOrder.swift"]
            .map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }.joined(separator: "\n")
        for needle in ["\"Preview\"", "\"Nothing selected: only the Soaro icon shows\"", "\"Menu bar preview: \\(list)\"", "\"Move up\"", "\"Move down\"",
                       "\"\\(index + 1) of \\(count)\"", "\"Drag to change the order\"",
                       "\"Drag the handles to change the order. The Soaro icon always comes first.\""] {
            #expect(used.contains(needle), "\(needle) n'est plus dans les sources : la clé du catalogue serait orpheline")
        }
    }
}
