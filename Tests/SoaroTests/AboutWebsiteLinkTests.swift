import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Soaro

/// SL18 : dans Réglages > À propos, un lien vers le site (soaro.app) avec le logo de l'app.
/// L'app n'envoie rien : `Link` ouvre le navigateur, comme « Buy me a coffee ». La lecture par VoiceOver
/// et la navigation au clavier se vérifient à la main ; ici, les constantes, le choix de l'adresse et la forme du code.
@Suite struct AboutWebsiteLinkTests {
    // MARK: Adresses

    @Test func theWebsiteIsTheSiteRootAndTheVisibleTextIsTheDomain() {
        #expect(SupportLink.website.absoluteString == "https://soaro.app")
        #expect(SupportLink.websiteFrench.absoluteString == "https://soaro.app/fr/")
        #expect(SupportLink.websiteText == "soaro.app")
    }

    @Test func theCoffeeLinkIsUntouched() {
        #expect(SupportLink.url.absoluteString == "https://buymeacoffee.com/sebmafate")
    }

    @Test(arguments: ["fr", "fr-FR", "fr_CA", "FR", "fr-Latn-FR"])
    func aFrenchAppLanguageLinksToTheFrenchPage(language: String) {
        #expect(SupportLink.websiteURL(preferredLanguages: [language]) == SupportLink.websiteFrench)
    }

    @Test(arguments: ["en", "en-US", "de", "es", "it", "ja", "ko", "pt-BR", "zh-Hans", "frisian", "fra", ""])
    func anyOtherLanguageLinksToTheEnglishRoot(language: String) {
        // « frisian » et « fra » commencent par « fr » sans être du français.
        #expect(SupportLink.websiteURL(preferredLanguages: [language]) == SupportLink.website)
    }

    @Test func onlyTheFirstLanguageCountsAndNoLanguageMeansEnglish() {
        #expect(SupportLink.websiteURL(preferredLanguages: ["de", "fr"]) == SupportLink.website)
        #expect(SupportLink.websiteURL(preferredLanguages: ["fr", "en"]) == SupportLink.websiteFrench)
        #expect(SupportLink.websiteURL(preferredLanguages: []) == SupportLink.website)
    }

    @Test func theFrenchPageExistsOnTheSite() {
        let page = RepositoryRoot.url().appendingPathComponent("site/fr/index.html")
        #expect(FileManager.default.fileExists(atPath: page.path), "SupportLink.websiteFrench pointe vers un dossier absent de site/")
    }

    // MARK: Taille et accessibilité

    @Test func theLogoIsBetween36And40PointsAndTheRowAtLeast24() {
        #expect((36...40).contains(WebsiteLinkRow.logoSize))
        #expect(WebsiteLinkRow.minimumHeight >= 24)
        #expect(WebsiteLinkRow.minimumHeight >= WebsiteLinkRow.logoSize)
    }

    @MainActor @Test func theRowIsAtLeast24PointsHighAndAsWideAsItsContainer() {
        let host = NSHostingView(rootView: WebsiteLinkRow(url: SupportLink.website).frame(width: 380))
        let size = host.fittingSize
        #expect(size.height >= 24)
        #expect(size.height >= WebsiteLinkRow.logoSize)
        #expect(size.width == 380)
    }

    @Test func theRowIsOneLinkWithAHiddenLogoAndALabel() throws {
        let source = try Self.source("Sources/Soaro/Views/WebsiteLinkRow.swift")
        #expect(source.contains("Link(destination: url)"))
        #expect(source.contains(".accessibilityHidden(true)"), "le logo est décoratif")
        #expect(source.contains(".accessibilityLabel("))
        #expect(source.contains(".accessibilityHint(Text(\"Website\"))"))
        #expect(source.contains("Text(verbatim: SupportLink.websiteText)"))
        #expect(source.contains(".contentShape(Rectangle())"), "toute la ligne est cliquable")
        #expect(!source.contains("URLSession"))
    }

    @Test func theSettingsAboutSectionShowsTheRowBeforeTheCoffeeLinkAndKeepsTheCoffeeLink() throws {
        let source = try Self.source("Sources/Soaro/Views/SettingsView.swift")
        let about = try #require(source.range(of: "Section(\"About\")"))
        let tail = String(source[about.upperBound...])
        let website = try #require(tail.range(of: "WebsiteLinkRow(url: SupportLink.websiteURL("))
        let coffee = try #require(tail.range(of: "Link(destination: SupportLink.url)"))
        #expect(website.lowerBound < coffee.lowerBound)
        #expect(tail.contains("Label(\"Buy me a coffee\", systemImage: \"cup.and.saucer.fill\")"))
        #expect(tail.contains("Soaro is free and open source. Supporting it is optional."))
    }

    @Test func theAppLanguageDecidesTheAddressThroughThePureFunction() throws {
        let source = try Self.source("Sources/Soaro/Views/SettingsView.swift")
        #expect(source.contains("SupportLink.websiteURL(preferredLanguages: Bundle.main.preferredLocalizations)"))
    }

    // MARK: Texte nouveau

    @Test func theWebsiteHintIsInTheCatalogInNineLanguages() throws {
        let strings = try DockerStringsTests.catalogStrings()
        let entry = strings["Website"] as? [String: Any]
        #expect(entry != nil, "clé absente du catalogue : « Website »")
        let localizations = entry?["localizations"] as? [String: Any] ?? [:]
        for language in TranslationCatalog.requiredTranslations {
            let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
            #expect((unit?["value"] as? String ?? "").isEmpty == false, "« Website » / \(language)")
            #expect(unit?["state"] as? String == "translated", "« Website » / \(language)")
        }
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
    }
}
