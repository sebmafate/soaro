import Foundation
import Testing
@testable import Soaro

/// Accessibilité (DESIGN.md partie 2) : les couleurs définies gardent leur contraste.
/// On vérifie les constantes du jeu de jetons, pas les pixels rendus.
@Suite struct ContrastTests {
    private typealias Tokens = DesignTokens

    // MARK: Fonction de calcul

    @Test func blackOnWhiteIs21To1() {
        #expect(abs(Tokens.contrastRatio(.black, on: .white) - 21) < 0.001)
    }

    @Test func identicalColorsAre1To1() {
        #expect(abs(Tokens.contrastRatio(.white, on: .white) - 1) < 0.001)
    }

    @Test func grey767676OnWhiteIsAbout4Point54() {
        let grey = Tokens.RGB(hex: 0x767676)
        #expect(abs(Tokens.contrastRatio(grey, on: .white) - 4.54) < 0.01)
    }

    @Test func alphaIsCompositedOntoTheBackground() {
        // Noir à 50 % sur blanc = gris moyen (0.5, 0.5, 0.5).
        let half = Tokens.contrastRatio(.black, alpha: 0.5, on: .white)
        let grey = Tokens.contrastRatio(Tokens.RGB(red: 0.5, green: 0.5, blue: 0.5), on: .white)
        #expect(abs(half - grey) < 0.001)
        // Alpha 1 = couleur opaque.
        #expect(abs(Tokens.contrastRatio(.black, alpha: 1, on: .white) - 21) < 0.001)
    }

    @Test func contrastIsSymmetric() {
        let a = Tokens.contrastRatio(Tokens.dangerFill, on: .white)
        let b = Tokens.contrastRatio(.white, on: Tokens.dangerFill)
        #expect(abs(a - b) < 0.0001)
    }

    // MARK: Bouton destructeur

    @Test func whiteOnDangerFillMeetsAAAndMatchesTheDesignRatio() {
        let ratio = Tokens.contrastRatio(.white, on: Tokens.dangerFill)
        #expect(ratio >= 4.5)
        #expect(abs(ratio - 4.98) <= 0.02)
    }

    @Test func whiteOnIncreasedDangerFillMeetsAAAndMatchesTheDesignRatio() {
        let ratio = Tokens.contrastRatio(.white, on: Tokens.dangerFillIncreasedContrast)
        #expect(ratio >= 4.5)
        #expect(abs(ratio - 6.57) <= 0.02)
    }

    @Test func dangerFillHexValues() {
        #expect(Tokens.dangerFill == Tokens.RGB(hex: 0xD32F2F))
        #expect(Tokens.dangerFillIncreasedContrast == Tokens.RGB(hex: 0xB71C1C))
    }

    @Test func dangerFillStandsOutFromBothReferenceBackgrounds() {
        for background in [Tokens.lightReferenceBackground, Tokens.darkReferenceBackground] {
            #expect(Tokens.contrastRatio(Tokens.dangerFill, on: background) >= 3)
        }
    }

    @Test func increasedDangerFillStandsOutFromTheLightBackground() {
        #expect(Tokens.contrastRatio(Tokens.dangerFillIncreasedContrast, on: Tokens.lightReferenceBackground) >= 3)
        // Sur le fond sombre de référence, #B71C1C donne environ 2,5 : 1 (< 3 : 1). Ce rapport n'est pas
        // exigé par le brief ; il est signalé à l'auteur dans le rapport de SL3, pas masqué ici.
    }

    @Test func dangerFillOnDarkReferenceIsAbout3Point35() {
        let ratio = Tokens.contrastRatio(Tokens.dangerFill, on: Tokens.darkReferenceBackground)
        #expect(abs(ratio - 3.35) <= 0.02)
    }

    @Test func increasedContrastSelectsTheDeeperRed() {
        #expect(Tokens.dangerFill(contrastIncreased: true) == Tokens.RGB(hex: 0xB71C1C))
        #expect(Tokens.dangerFill(contrastIncreased: false) == Tokens.RGB(hex: 0xD32F2F))
    }

    // MARK: Texte secondaire (text-supporting)

    @Test func supportingTextAlphaIsAbsolute() {
        #expect(Tokens.supportingTextAlpha(contrastIncreased: false) == 0.56)
        #expect(Tokens.supportingTextAlpha(contrastIncreased: true) == 0.70)
    }

    @Test(arguments: [false, true])
    func supportingTextMeetsAAOnBothReferenceBackgrounds(increased: Bool) {
        let alpha = Tokens.supportingTextAlpha(contrastIncreased: increased)
        let onLight = Tokens.contrastRatio(Tokens.supportingTextBase(dark: false), alpha: alpha, on: Tokens.lightReferenceBackground)
        let onDark = Tokens.contrastRatio(Tokens.supportingTextBase(dark: true), alpha: alpha, on: Tokens.darkReferenceBackground)
        #expect(onLight >= 4.5)
        #expect(onDark >= 4.5)
    }

    @Test func supportingTextMatchesTheDesignRatios() {
        let light = Tokens.contrastRatio(.black, alpha: 0.56, on: Tokens.lightReferenceBackground)
        let dark = Tokens.contrastRatio(.white, alpha: 0.56, on: Tokens.darkReferenceBackground)
        #expect(abs(light - 4.95) <= 0.05)
        #expect(abs(dark - 6.1) <= 0.1)
    }

    @Test func supportingTextIsPureBlackInLightAndPureWhiteInDark() {
        #expect(Tokens.supportingTextBase(dark: false) == .black)
        #expect(Tokens.supportingTextBase(dark: true) == .white)
    }

    @Test func referenceBackgrounds() {
        #expect(Tokens.lightReferenceBackground == .white)
        #expect(Tokens.darkReferenceBackground == Tokens.RGB(hex: 0x1E1E1E))
    }
}
