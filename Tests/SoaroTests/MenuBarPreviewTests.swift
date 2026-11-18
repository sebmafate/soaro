import AppKit
import SwiftUI
import Testing
@testable import Soaro

/// SL22 : l'aperçu de la barre de menus dans les Réglages. Même vue (`MenuBarWidgetsView`) et mêmes données que le libellé réel,
/// dessinés directement sur une bande qui imite la barre (une image « modèle » n'est teintée que par macOS dans la vraie barre).
/// Ici : rendus hors écran lus en pixels. La vraie barre de menus et le toucher se vérifient à la main.
@MainActor @Suite(.serialized) struct MenuBarPreviewRenderTests {
    private static let scale: CGFloat = 2

    private static let orange = MenuBarItem.stacked(label: "CPU", value: "70%", level: .medium)
    private static let red = MenuBarItem.stacked(label: "RAM", value: "85%", level: .high)
    private static let scarlet = MenuBarItem.stacked(label: "SSD", value: "97%", level: .critical)
    private static let plain = MenuBarItem.stacked(label: "CPU", value: "43%")
    private static let pair = MenuBarItem.pair(top: "↑ 99 KB/s", bottom: "↓ 13 KB/s")

    private func strip(_ items: [MenuBarItem], compact: Bool = true, dark: Bool = false, severity: Severity? = nil,
                       width: CGFloat = 400) throws -> GlyphInk {
        let view = MenuBarPreviewStrip(items: items, compact: compact, severity: severity)
            .environment(\.colorScheme, dark ? .dark : .light)
            .frame(width: width)
        let renderer = ImageRenderer(content: view)
        renderer.scale = Self.scale
        return try GlyphInk(cg: try #require(renderer.cgImage), scale: Self.scale)
    }

    private func isOrange(_ p: (r: Double, g: Double, b: Double, a: Double)) -> Bool { p.r > 0.9 && p.g > 0.45 && p.g < 0.7 && p.b < 0.2 }
    private func isRed(_ p: (r: Double, g: Double, b: Double, a: Double)) -> Bool { p.r > 0.9 && p.g > 0.2 && p.g < 0.35 && p.b > 0.15 && p.b < 0.32 }
    private func isFlagBlue(_ p: (r: Double, g: Double, b: Double, a: Double)) -> Bool { p.b > 0.5 && p.r < 0.3 && p.g < 0.5 }
    private func isScarlet(_ p: (r: Double, g: Double, b: Double, a: Double)) -> Bool { p.r > 0.95 && p.g > 0.08 && p.g < 0.19 && p.b < 0.06 }

    /// Première colonne (en points) où apparaissent au moins `minimum` pixels de cette couleur.
    private func firstColumn(of ink: GlyphInk, minimum: Int = 4, where match: ((r: Double, g: Double, b: Double, a: Double)) -> Bool) -> CGFloat? {
        var count = 0
        for x in 0..<ink.width {
            for y in 0..<ink.height where match(ink.pixel(x, y)) { count += 1 }
            if count >= minimum { return CGFloat(x) / ink.scale }
        }
        return nil
    }

    // MARK: Géométrie et fond

    @Test func theStripIsAboutThirtyPointsHighAndRounded() throws {
        for dark in [false, true] {
            let ink = try strip([Self.plain], dark: dark)
            #expect(ink.height == Int(MenuBarPreviewStrip.height * Self.scale))
            #expect((28...30).contains(MenuBarPreviewStrip.height), "environ 28 à 30 pt")
            #expect(ink.alpha(ink.width / 2, ink.height / 2) > 0.99)
            #expect(ink.alpha(0, 0) < 0.1, "coin arrondi : transparent dans l'angle")
            #expect(ink.alpha(ink.width - 1, ink.height - 1) < 0.1)
        }
    }

    @Test func theStripFollowsLightAndDark() throws {
        let light = try strip([], dark: false), dark = try strip([], dark: true)
        let l = light.pixel(light.width - 20, light.height / 2), d = dark.pixel(dark.width - 20, dark.height / 2)
        #expect(l.r > 0.8 && l.g > 0.8 && l.b > 0.8, "bande claire : \(l)")
        #expect(d.r < 0.3 && d.g < 0.3 && d.b < 0.3, "bande sombre : \(d)")
        #expect(MenuBarPreviewStrip.baseColor(dark: true) == .white && MenuBarPreviewStrip.baseColor(dark: false) == .black)
    }

    // MARK: Couleur de base : blanc sur bande sombre, noir sur bande claire

    @Test func theBrandAndTheValuesAreWhiteOnADarkStripAndBlackOnALightOne() throws {
        for compact in [true, false] {
            let dark = try strip([Self.plain], compact: compact, dark: true)
            let light = try strip([Self.plain], compact: compact, dark: false)
            let brandBox = 6..<Int(40 * Self.scale)
            var brightest = 0.0, darkest = 1.0
            for x in brandBox { for y in 0..<dark.height { brightest = max(brightest, dark.pixel(x, y).r) } }
            for x in brandBox { for y in 0..<light.height { darkest = min(darkest, light.pixel(x, y).r) } }
            #expect(brightest > 0.97, "compact \(compact) : le glyphe est blanc sur la bande sombre")
            #expect(darkest < 0.03, "compact \(compact) : le glyphe est noir sur la bande claire")
        }
    }

    // MARK: Ordre, de gauche à droite

    @Test func theItemsAppearLeftToRightInTheGivenOrderForEveryPermutation() throws {
        // Trois blocs que leur couleur distingue : un orange, un rouge, le bloc réseau avec son drapeau (le bleu du drapeau suédois (le français a du rouge, qui se confondrait avec le rouge d'une valeur)).
        let blocks: [[MenuBarItem]] = [[Self.orange], [Self.red], [Self.pair, .flag(countryCode: "SE")]]
        let permutations = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        for dark in [false, true] {
            for compact in [true, false] {
                for permutation in permutations {
                    let ink = try strip(permutation.flatMap { blocks[$0] }, compact: compact, dark: dark)
                    let found: [(Int, CGFloat)] = try [
                        (0, try #require(firstColumn(of: ink, where: isOrange), "orange absent")),
                        (1, try #require(firstColumn(of: ink, where: isRed), "rouge absent")),
                        (2, try #require(firstColumn(of: ink, where: isFlagBlue), "drapeau absent")),
                    ]
                    let seen = found.sorted { $0.1 < $1.1 }.map(\.0)
                    #expect(seen == permutation, "compact \(compact), dark \(dark) : lu \(seen), voulu \(permutation)")
                }
            }
        }
    }

    @Test func aCriticalValueIsAScarletPillInThePreviewToo() throws {
        let ink = try strip([Self.scarlet], dark: false)
        var solid = 0
        for x in 0..<ink.width { for y in 0..<ink.height where isScarlet(ink.pixel(x, y)) { solid += 1 } }
        #expect(solid > 200, "la pastille écarlate : \(solid) pixels")
    }

    @Test func theBrandIsAlwaysFirst() throws {
        let ink = try strip([Self.orange, Self.red], dark: false)
        let orangeX = try #require(firstColumn(of: ink, where: isOrange))
        var firstInk: CGFloat?
        for x in 0..<ink.width where firstInk == nil {
            let p = (0..<ink.height).map { ink.pixel(x, $0) }
            if p.contains(where: { $0.r < 0.1 && $0.g < 0.1 && $0.b < 0.1 && $0.a > 0.9 }) { firstInk = CGFloat(x) / ink.scale }
        }
        #expect((firstInk ?? 99) < orangeX - 10, "le glyphe d'Soaro est à gauche de tout")
    }

    // MARK: Même dessin que le vrai libellé

    private func labelImage(_ items: [MenuBarItem], compact: Bool, dark: Bool, severity: Severity? = nil) throws -> GlyphInk {
        let image = try #require(MenuBarRenderer.image(severity: severity, compact: compact, items: items, darkBar: dark, increasedContrast: false))
        #expect(!image.isTemplate, "ces éléments portent une couleur : l'image porte ses couleurs")
        return try Self.ink(of: image)
    }

    /// Les pixels de l'image du libellé à l'échelle 2, par un dessin explicite (la demande d'un `CGImage` à une taille donnée ne garantit pas la taille rendue).
    private static func ink(of image: NSImage) throws -> GlyphInk {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * scale), pixelsHigh: Int(image.size.height * scale),
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return try GlyphInk(cg: try #require(rep.cgImage), scale: scale)
    }

    /// Compare la forme de l'encre du libellé réel avec celle de l'aperçu, à la place où l'aperçu le pose (12 pt à gauche, centré dans la bande).
    /// Pas pixel pour pixel : le texte sur fond transparent (libellé) et sur fond opaque (aperçu) n'est pas lissé de la même façon.
    /// Un pixel d'encre = un pixel qui s'écarte du fond ; chaque pixel d'encre d'un côté doit avoir un pixel d'encre à moins de `tolerance` pixels (à 2x) de l'autre. En une ligne, le texte déborde
    /// de moins d'un point sur 300 entre la vue posée dans la bande et celle de l'image : tolérance de 2 pixels.
    private func compare(_ items: [MenuBarItem], compact: Bool, dark: Bool, severity: Severity? = nil, tolerance: Int = 1) throws -> (precision: Double, recall: Double) {
        let preview = try strip(items, compact: compact, dark: dark, severity: severity)
        let label = try labelImage(items, compact: compact, dark: dark, severity: severity)
        let originX = Int(MenuBarPreviewStrip.horizontalPadding * Self.scale)
        let originY = Int(((MenuBarPreviewStrip.height - 22) / 2) * Self.scale)
        let background = preview.pixel(preview.width - 16, preview.height / 2)
        func isInk(_ p: (r: Double, g: Double, b: Double, a: Double)) -> Bool {
            max(abs(p.r - background.r), abs(p.g - background.g), abs(p.b - background.b)) > 0.3
        }
        func nearInk(_ ink: GlyphInk, _ x: Int, _ y: Int, label: Bool) -> Bool {
            for dy in -tolerance...tolerance { for dx in -tolerance...tolerance {
                let p = label ? ink.pixel(x + dx, y + dy) : ink.pixel(x + dx + originX, y + dy + originY)
                // Sur le libellé (transparent) : de l'encre est un pixel opaque ; sur l'aperçu : un pixel qui s'écarte du fond.
                if label ? p.a > 0.5 : isInk(p) { return true }
            } }
            return false
        }
        var labelInk = 0, labelMatched = 0, previewInk = 0, previewMatched = 0
        for y in 0..<label.height {
            for x in 0..<label.width {
                if label.alpha(x, y) > 0.5 { labelInk += 1; if nearInk(preview, x, y, label: false) { labelMatched += 1 } }
                if isInk(preview.pixel(x + originX, y + originY)) { previewInk += 1; if nearInk(label, x, y, label: true) { previewMatched += 1 } }
            }
        }
        #expect(labelInk > 200 && previewInk > 200, "de l'encre des deux côtés : \(labelInk), \(previewInk)")
        return (Double(previewMatched) / Double(max(previewInk, 1)), Double(labelMatched) / Double(max(labelInk, 1)))
    }

    @Test func theItemsAreDrawnLikeTheRealLabelInBothStylesAndOnBothStrips() throws {
        // Six éléments tiennent en compact ; en une ligne ils débordent de la bande (cas rétréci, testé à part) : on en met moins.
        let compactItems: [MenuBarItem] = [Self.orange, Self.red, Self.pair, .flag(countryCode: "FR"), .battery(percent: 67, power: .charging), Self.scarlet]
        let lineItems: [MenuBarItem] = [Self.orange, Self.red, Self.pair, .flag(countryCode: "FR")]
        for (compact, items) in [(true, compactItems), (false, lineItems)] {
            for dark in [false, true] {
                let result = try compare(items, compact: compact, dark: dark, tolerance: compact ? 1 : 2)
                #expect(result.precision > 0.93, "compact \(compact), dark \(dark) : \(result.precision) de l'encre de l'aperçu est dans le libellé")
                #expect(result.recall > 0.93, "compact \(compact), dark \(dark) : \(result.recall) de l'encre du libellé est dans l'aperçu")
            }
        }
    }

    @Test func theBatteryInSingleLineIsDrawnLikeTheRealLabelToo() throws {
        for dark in [false, true] {
            let result = try compare([Self.orange, .battery(percent: 67, power: .charging)], compact: false, dark: dark, tolerance: 2)
            #expect(result.precision > 0.93 && result.recall > 0.93, "dark \(dark) : \(result)")
        }
    }

    @Test func aDifferentOrderIsNotTheSameImage() throws {
        let a = try strip([Self.orange, Self.red, Self.scarlet]), b = try strip([Self.scarlet, Self.red, Self.orange])
        var different = 0
        for y in 0..<a.height { for x in 0..<a.width { let p = a.pixel(x, y), q = b.pixel(x, y); if abs(p.r - q.r) + abs(p.g - q.g) + abs(p.b - q.b) > 0.3 { different += 1 } } }
        #expect(different > 100, "\(different) pixels")
    }

    // MARK: Batterie, drapeau, couleurs des seuils, alerte

    @Test func theBatteryGlyphAndTheFlagAreDrawn() throws {
        let without = try strip([Self.plain], dark: false)
        let withBattery = try strip([Self.plain, .battery(percent: 67, power: .onBattery)], dark: false)
        let withFlag = try strip([Self.plain, Self.pair, .flag(countryCode: "FR")], dark: false)
        let withoutFlag = try strip([Self.plain, Self.pair], dark: false)
        func inkRight(of ink: GlyphInk, from x0: CGFloat) -> Int {
            var n = 0
            for x in Int(x0 * Self.scale)..<ink.width { for y in 0..<ink.height where ink.pixel(x, y).r < 0.5 { n += 1 } }
            return n
        }
        #expect(inkRight(of: withBattery, from: 90) > inkRight(of: without, from: 90) + 60, "icône et pourcentage de batterie")
        func blueish(_ ink: GlyphInk) -> Int {
            var n = 0
            for x in 0..<ink.width { for y in 0..<ink.height { let p = ink.pixel(x, y); if p.b > 0.5 && p.r < 0.3 && p.g < 0.4 { n += 1 } } }
            return n
        }
        #expect(blueish(withFlag) > blueish(withoutFlag) + 8, "le bleu du drapeau suédois (le français a du rouge, qui se confondrait avec le rouge d'une valeur) : \(blueish(withFlag)) contre \(blueish(withoutFlag))")
    }

    @Test func aWarningBadgeSitsNextToTheBrandLikeInTheRealLabel() throws {
        let plain = try strip([Self.plain], dark: false)
        let warned = try strip([Self.plain], dark: false, severity: .warning)
        var different = 0
        for y in 0..<plain.height { for x in 0..<plain.width / 3 where abs(plain.pixel(x, y).r - warned.pixel(x, y).r) > 0.3 { different += 1 } }
        #expect(different > 8, "le point d'alerte à droite du glyphe")
        let result = try compare([Self.orange], compact: true, dark: false, severity: .warning)
        #expect(result.precision > 0.93 && result.recall > 0.93, "avec le point d'alerte aussi : \(result)")
    }

    // MARK: Contenu : mêmes données que le libellé, seuils compris

    private func snapshot(cpu: Double) -> SystemSnapshot {
        var snapshot = DemoData.snapshot()
        snapshot.cpu = CPUStats(user: cpu, system: 0)
        return snapshot
    }

    @Test func theItemsComeFromTheSameFunctionAndFollowTheThresholds() throws {
        let s = snapshot(cpu: 0.55)
        var custom = PressureThresholds.default
        custom.load = LevelThresholds(medium: 50, high: 80, critical: 95)
        let byDefault = MenuBarItem.items(for: s, cpu: true, gpu: false, memory: false, disk: false, network: false, battery: false, thresholds: .default)
        let changed = MenuBarItem.items(for: s, cpu: true, gpu: false, memory: false, disk: false, network: false, battery: false, thresholds: custom)
        #expect(byDefault.first?.level == .normal && changed.first?.level == .medium)
        let normalInk = try strip(byDefault, dark: false), mediumInk = try strip(changed, dark: false)
        #expect(firstColumn(of: normalInk, where: isOrange) == nil, "55 % reste normal avec les seuils par défaut")
        #expect(firstColumn(of: mediumInk, where: isOrange) != nil, "55 % passe en orange quand le seuil est à 50")
    }

    // MARK: Aucun élément

    @Test func withNothingSelectedOnlyTheBrandAndTheExplanationShow() throws {
        #expect(MenuBarPreviewStrip.emptyText == "Nothing selected: only the Soaro icon shows")
        let empty = try strip([], dark: false)
        func inkBeyond(_ ink: GlyphInk, from x0: CGFloat, to x1: CGFloat = 385) -> Int {
            var n = 0
            for x in Int(x0 * Self.scale)..<Int(x1 * Self.scale) { for y in 0..<ink.height where ink.pixel(x, y).r < 0.7 { n += 1 } }
            return n
        }
        #expect(inkBeyond(empty, from: 40) > 80, "le texte d'explication")
        let notEmpty = try strip([Self.plain], dark: false, width: 600)
        #expect(inkBeyond(notEmpty, from: 150, to: 585) == 0, "avec un élément, pas de texte d'explication : \(inkBeyond(notEmpty, from: 150, to: 585))")
        #expect(MenuBarPreviewStrip.showsEmptyText(items: []) && !MenuBarPreviewStrip.showsEmptyText(items: [Self.plain]))
    }

    // MARK: Trop large pour la bande : tout reste visible

    @Test func sixItemsInSingleLineShrinkToFitTheStripInsteadOfBeingCut() throws {
        let items: [MenuBarItem] = [.stacked(label: "CPU", value: "43%"), .stacked(label: "GPU", value: "22%"), .stacked(label: "RAM", value: "61%"),
                                     .stacked(label: "SSD", value: "83%"), Self.pair, .flag(countryCode: "FR"), .battery(percent: 100, power: .charging)]
        let width: CGFloat = 330
        let view = MenuBarPreviewStrip(items: items, compact: false, severity: nil)
            .environment(\.colorScheme, .light)
            .frame(width: width, height: MenuBarPreviewStrip.height)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: MenuBarPreviewStrip.height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        for _ in 0..<8 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)); host.layoutSubtreeIfNeeded() }
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let cg = try #require(rep.cgImage)
        let ink = try GlyphInk(cg: cg, scale: CGFloat(cg.width) / width)
        // Tout est là, jusqu'au dernier élément (le drapeau est l'avant-dernier : le bleu de la France le prouve), et rien ne touche le bord droit.
        var lastInk = 0, blue = 0
        for x in 0..<ink.width {
            for y in 0..<ink.height {
                let p = ink.pixel(x, y)
                if p.a > 0.5 && p.r + p.g + p.b < 1.5 { lastInk = max(lastInk, x) }
                if p.b > 0.5 && p.r < 0.3 && p.g < 0.5 { blue += 1 }
            }
        }
        let lastPoint = CGFloat(lastInk) / ink.scale
        #expect(blue > 8, "le drapeau (6e élément) est visible : \(blue) pixels bleus")
        #expect(lastPoint < width - 8, "l'encre va jusqu'à \(lastPoint) pt sur \(width) : une marge reste à droite")
        #expect(lastPoint > width * 0.85, "et le contenu remplit la bande : \(lastPoint) pt")
        window.orderOut(nil)
    }
}

/// Le texte de l'aperçu : phrase d'accessibilité et état vide.
@Suite struct MenuBarPreviewDescriptionTests {
    @Test func theLabelListsTheShownMeasuresInOrder() {
        let items: [MenuBarItem] = [.battery(percent: 5, power: .onBattery), .stacked(label: "CPU", value: "1%"), .stacked(label: "RAM", value: "1%")]
        let label = MenuBarPreview.accessibilityLabel(for: items)
        #expect(label.hasPrefix("Menu bar preview: "))
        let positions = ["Battery", "CPU", "Memory"].map { label.range(of: $0)?.lowerBound }
        #expect(positions.allSatisfy { $0 != nil })
        #expect(positions[0]! < positions[1]! && positions[1]! < positions[2]!, Comment(rawValue: label))
    }

    @Test func theFlagIsNotAMeasureAndNetworkIsNamedOnce() {
        let label = MenuBarPreview.accessibilityLabel(for: [.pair(top: "a", bottom: "b"), .flag(countryCode: "FR"), .stacked(label: "SSD", value: "9%")])
        #expect(label.components(separatedBy: "Network").count == 2, Comment(rawValue: label))
        #expect(label.contains("Disk"))
        #expect(!label.contains("FR"))
    }

    @Test func anEmptyPreviewSaysSo() {
        #expect(MenuBarPreview.accessibilityLabel(for: []) == MenuBarPreviewStrip.emptyText)
    }
}
