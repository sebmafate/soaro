import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Soaro

/// SL21 : l'icône de batterie sur la carte de l'aperçu et dans l'onglet Batterie.

@MainActor @Suite struct BatteryCardsTests {
    private func read(_ path: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
    }

    @Test func theOverviewCardNoLongerUsesASystemBatterySymbol() throws {
        let source = try read("Sources/Soaro/Views/OverviewTab.swift")
        #expect(!source.contains("batterySymbol"))
        #expect(!source.contains("battery.100percent"))
        #expect(!source.contains("battery.75percent"))
        #expect(!source.contains("battery.50percent"))
        #expect(!source.contains("battery.25percent"))
        #expect(!source.contains("battery.0percent"))
        #expect(source.contains("BatteryGlyph("))
    }

    @Test func theBatteryTabHeaderUsesTheGlyphInsteadOfTheSystemIcons() throws {
        let source = try read("Sources/Soaro/Views/BatteryTab.swift")
        #expect(source.contains("BatteryGlyph("))
        #expect(!source.contains("\"battery.50percent\""))
        #expect(!source.contains("\"bolt.fill\""))
        #expect(!source.contains("\"powerplug.fill\""))
    }

    @Test func theGlyphIsHiddenFromVoiceOverBecauseTheTextSaysTheLevel() throws {
        let source = try read("Sources/Soaro/Views/BatteryGlyph.swift")
        #expect(source.contains(".accessibilityHidden(true)"))
        let overview = try read("Sources/Soaro/Views/OverviewTab.swift")
        // La carte réunit ses textes (titre, valeur, sous-titre « Charging · 48 min ») en un seul élément : niveau et charge sont dits.
        let components = try read("Sources/Soaro/Views/Components.swift")
        #expect(components.contains(".accessibilityElement(children: .combine)"))
        #expect(OverviewTab.batterySubtitle(DemoData.snapshot().battery!).hasPrefix("Charging"))
        _ = overview
    }

    @Test func theStatCardAcceptsACustomIconAndRenders() throws {
        let card = StatCard(title: "Battery", systemImage: "battery.100percent", value: "67%", subtitle: "Charging",
                            icon: AnyView(BatteryGlyph(percent: 67, charging: true, level: .normal, base: .primary, body: BatteryGlyphGeometry.cardBody)))
            .frame(width: 180)
        let renderer = ImageRenderer(content: card)
        let image = try #require(renderer.nsImage)
        #expect(image.size.width == 180 && image.size.height > 40)
    }

    @Test func demoBatteryIs67PercentCharging() throws {
        let b = try #require(DemoData.snapshot().battery)
        #expect(b.percent == 67 && b.isCharging)
        let list = MenuBarItem.items(for: DemoData.snapshot(), cpu: false, gpu: false, memory: false, disk: false, network: false, battery: true)
        #expect(list == [.battery(percent: 67, charging: true, level: .normal)])
    }
}
