import AppKit
import SwiftUI
import Testing
@testable import Soaro

/// SL23, étape 1 : le libellé est une image dessinée à l'échelle de l'écran où elle s'affiche, jamais à celle de `NSScreen.main`.
/// Ici : des rendus hors écran à des échelles explicites (1, 2, 3). Un vrai écran 1x à côté d'un écran Retina se juge à la main.
@MainActor @Suite(.serialized) struct MenuBarScaleTests {
    private static let rich: [MenuBarItem] = [.stacked(label: "CPU", value: "43%"), .stacked(label: "RAM", value: "61%"),
                                              .pair(top: "↑ 99 KB/s", bottom: "↓ 13 KB/s"), .battery(percent: 67, power: .charging)]

    private func label(_ items: [MenuBarItem] = rich, compact: Bool = true, dark: Bool = false) throws -> NSImage {
        try #require(MenuBarRenderer.image(severity: nil, compact: compact, items: items, darkBar: dark, increasedContrast: false))
    }

    // MARK: l'échelle vient du contexte de dessin

    @Test func theScaleIsReadFromTheDrawingContext() throws {
        func context(scale: CGFloat, flipped: Bool = false) throws -> CGContext {
            let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            if flipped { context.translateBy(x: 0, y: 8); context.scaleBy(x: 1, y: -1) }
            context.scaleBy(x: scale, y: scale)
            return context
        }
        for scale in [1, 2, 3] as [CGFloat] {
            #expect(MenuBarRenderer.pixelScale(of: try context(scale: scale)) == Int(scale))
            #expect(MenuBarRenderer.pixelScale(of: try context(scale: scale, flipped: true)) == Int(scale), "contexte à l'envers : même échelle")
        }
        #expect(MenuBarRenderer.pixelScale(of: try context(scale: 0.5)) == 1, "jamais moins d'un pixel par point")
        #expect(MenuBarRenderer.pixelScale(of: try context(scale: 1.5)) == 2)
    }

    @Test func theLabelDoesNotAskTheMainScreenForItsScale() throws {
        let text = try String(contentsOf: RepositoryRoot.url().appendingPathComponent("Sources/Soaro/Views/MenuBarWidgets.swift"), encoding: .utf8)
        let source = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        #expect(!source.contains("NSScreen"), "NSScreen.main est l'écran de la fenêtre active, pas celui de la barre de menus")
        #expect(!source.contains("NSScreen.main") && !source.contains("NSScreen.screens"))
    }

    // MARK: une image, plusieurs échelles

    @Test func theSameImageIsDrawnAtEachScaleWithTheSameSizeInPoints() throws {
        let image = try label()
        let size = image.size
        #expect(size.height == 22)
        for scale in [1, 2, 3] as [CGFloat] {
            let ink = try GlyphInk(image: image, scale: scale)
            #expect(ink.width == Int((size.width * scale).rounded()) && ink.height == Int(22 * scale), "\(scale)x")
            #expect(ink.alpha(ink.width / 2, ink.height / 2) >= 0, "dessiné")
        }
        #expect(image.size == size, "dessiner à d'autres échelles ne change pas la taille en points")
    }

    @Test func eachScaleIsDrawnForItAndNotStretched() throws {
        let image = try label()
        let one = try GlyphInk(image: image, scale: 1), two = try GlyphInk(image: image, scale: 2)
        // Le 1x agrandi d'un facteur 2 (pixels doublés) est ce qu'on verrait si l'image était dessinée une fois à 1x : le vrai 2x en diffère.
        var different = 0, inked = 0
        for y in 0..<two.height { for x in 0..<two.width {
            let a = two.alpha(x, y), b = one.alpha(x / 2, y / 2)
            if a > 0.05 || b > 0.05 { inked += 1; if abs(a - b) > 0.25 { different += 1 } }
        } }
        #expect(inked > 400)
        #expect(Double(different) / Double(inked) > 0.10, "le 2x n'est pas le 1x agrandi : \(different) pixels sur \(inked) diffèrent")
        // Et l'inverse : le 1x n'est pas le 2x réduit en pixels.
        var different1 = 0, inked1 = 0
        for y in 0..<one.height { for x in 0..<one.width {
            let a = one.alpha(x, y)
            let avg = (two.alpha(2 * x, 2 * y) + two.alpha(2 * x + 1, 2 * y) + two.alpha(2 * x, 2 * y + 1) + two.alpha(2 * x + 1, 2 * y + 1)) / 4
            if a > 0.05 || avg > 0.05 { inked1 += 1; if abs(a - avg) > 0.25 { different1 += 1 } }
        } }
        #expect(Double(different1) / Double(inked1) > 0.05, "le 1x n'est pas le 2x réduit : \(different1) sur \(inked1)")
    }

    @Test func drawingAtSeveralScalesKeepsOneCachedImageAndOneInstancePerContent() throws {
        let first = try label()
        _ = try GlyphInk(image: first, scale: 1)
        _ = try GlyphInk(image: first, scale: 2)
        _ = try GlyphInk(image: first, scale: 3)
        #expect(try label() === first, "le cache ne dépend pas de l'échelle : même contenu, même image, à toutes les échelles")
        let other = try label([.stacked(label: "CPU", value: "44%")])
        #expect(other !== first, "une valeur change : une autre image")
        #expect(try label([.stacked(label: "CPU", value: "44%")]) === other)
    }

    @Test func theCacheKeyCoversEveryDisplayedValue() throws {
        let base = try label()
        #expect(try label(dark: true) === base, "tout est normal : image modèle, la couleur de la barre n'y entre pas")
        let coloured: [MenuBarItem] = [.stacked(label: "CPU", value: "70%", level: .medium)]
        let light = try label(coloured), dark = try label(coloured, dark: true)
        #expect(light !== dark, "une image colorée dépend de la barre claire ou sombre")
        let inline = try label(coloured, compact: false)
        #expect(inline !== light, "le style")
        let severity = try #require(MenuBarRenderer.image(severity: .warning, compact: true, items: coloured, darkBar: false, increasedContrast: false))
        #expect(severity !== dark && severity !== light, "le badge d'alerte")
        let contrast = try #require(MenuBarRenderer.image(severity: nil, compact: true, items: Self.rich, darkBar: false, increasedContrast: true))
        let plain = try label()
        #expect(plain !== contrast, "le contraste renforcé")
    }

    // MARK: le vrai bouton de la barre de menus

    @Test func theDynamicImageIsSetUntouchedOnAButtonThatAlreadyCarriesAnImage() throws {
        let image = try label()
        let flattened = NSImage(size: image.size)
        let carrying = NSButton(), alreadyOurs = NSButton(), empty = NSButton()
        carrying.image = flattened
        alreadyOurs.image = image
        let updated = MenuBarRenderer.install(image, on: [carrying, alreadyOurs, empty])
        #expect(updated == 1)
        #expect(carrying.image === image, "la même instance, pas une copie : AppKit la redessine à l'échelle de l'écran du bouton")
        #expect(alreadyOurs.image === image)
        #expect(empty.image == nil, "un bouton sans image (SwiftUI y héberge une vue) n'est pas touché")
        #expect(MenuBarRenderer.install(image, on: [carrying, alreadyOurs, empty]) == 0, "rien à refaire la seconde fois")
    }

    @Test func theLabelInstallsTheImageOnTheStatusButtonsAndKeepsTheSwiftUIFallback() throws {
        let source = try String(contentsOf: RepositoryRoot.url().appendingPathComponent("Sources/Soaro/SoaroApp.swift"), encoding: .utf8)
        #expect(source.contains("MenuBarRenderer.installOnStatusBarButtons("))
        #expect(source.contains("Image(nsImage: image)"), "le libellé SwiftUI reste, en repli")
        #expect(source.contains("Image(systemName: \"water.waves\")"))
    }
}
