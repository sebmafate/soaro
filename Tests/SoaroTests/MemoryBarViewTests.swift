import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Soaro

/// Rendu hors écran de la barre mémoire segmentée et de ses lignes (SL26 T3 à T6).
/// On lit les pixels d'une image produite par `ImageRenderer` à l'échelle 1 et 2.
@MainActor
@Suite struct MemoryBarViewTests {
    nonisolated private static let GB: UInt64 = 1_073_741_824
    nonisolated private static func gb(_ x: Double) -> UInt64 { UInt64((x * Double(GB)).rounded()) }

    /// Les chiffres de la capture de l'auteur : pression élevée, 6,41 Go de swap.
    nonisolated static let screenshot = MemoryStats(total: 16 * GB, app: gb(4.03), wired: gb(2.83), compressed: gb(5.8), cached: gb(2.45),
                                        swapUsed: gb(6.41), pressure: .warning)

    // MARK: Lecture des pixels

    struct Pixels {
        let width: Int, height: Int
        let bytes: [UInt8]
        func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let i = (y * width + x) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
        }
        func column(_ x: Int) -> [(r: Int, g: Int, b: Int)] { (0..<height).map { rgb(x, $0) } }
    }

    static func render<V: View>(_ view: V, scale: CGFloat, dark: Bool = false, increased: Bool = false,
                                size: CGSize? = nil) -> Pixels? {
        let background: Color = dark ? DesignTokens.darkReferenceBackground.color : .white
        let content = view
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.contrastIncreasedOverride, increased)
            .environment(\.displayScale, scale)
            .background(background)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        if let size { renderer.proposedSize = ProposedViewSize(size) }
        guard let image = renderer.cgImage else { return nil }
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Pixels(width: w, height: h, bytes: data)
    }

    static func bar(_ memory: MemoryStats?, width: CGFloat = 300) -> some View {
        MemoryBar(memory: memory).frame(width: width)
    }

    static func expected(_ kind: MemorySegmentKind, dark: Bool, increased: Bool = false) -> (r: Int, g: Int, b: Int) {
        let c = DesignTokens.memorySegment(kind, dark: dark, contrastIncreased: increased)
        return (Int((c.red * 255).rounded()), Int((c.green * 255).rounded()), Int((c.blue * 255).rounded()))
    }

    /// Piste attendue : jeton de piste composé sur le fond de référence.
    static func expectedTrack(dark: Bool) -> (r: Int, g: Int, b: Int) {
        let c = DesignTokens.memoryTrackOnReference(dark: dark)
        return (Int((c.red * 255).rounded()), Int((c.green * 255).rounded()), Int((c.blue * 255).rounded()))
    }

    static func near(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int), tolerance: Int = 3) -> Bool {
        abs(a.r - b.r) <= tolerance && abs(a.g - b.g) <= tolerance && abs(a.b - b.b) <= tolerance
    }

    static func luminance(_ p: (r: Int, g: Int, b: Int)) -> Double {
        DesignTokens.relativeLuminance(.init(red: Double(p.r) / 255, green: Double(p.g) / 255, blue: Double(p.b) / 255))
    }

    private static func layout(scale: Double, width: Double = 300, memory: MemoryStats = screenshot) -> MemoryBarLayout {
        MemoryBarLayout.make(memory: memory, trackWidth: width, scale: scale, gapPixels: MemoryBar.gapPixels)
    }

    // MARK: Couleurs aux bons endroits

    @Test(arguments: [1.0, 2.0], [false, true])
    func eachSegmentHasItsTokenColourAtItsCentre(scale: Double, dark: Bool) throws {
        let pixels = try #require(Self.render(Self.bar(Self.screenshot), scale: scale, dark: dark))
        #expect(pixels.width == Int(300 * scale))
        let layout = Self.layout(scale: scale)
        let mid = pixels.height / 2
        #expect(layout.segments.count == 4)
        for segment in layout.segments {
            let x = (segment.startPixel + segment.endPixel) / 2
            let got = pixels.rgb(x, mid)
            if segment.kind == .cached {
                // Le cache est un contour et un remplissage léger : le centre n'est pas la couleur pleine du jeton.
                #expect(!Self.near(got, Self.expected(.cached, dark: dark), tolerance: 6), "le cache ne doit pas être plein")
            } else {
                #expect(Self.near(got, Self.expected(segment.kind, dark: dark)), "\(segment.kind) x=\(x) échelle \(scale) : \(got)")
            }
        }
    }

    @Test(arguments: [1.0, 2.0])
    func theFreePartOfTheTrackIsTheTrackColour(scale: Double) throws {
        let pixels = try #require(Self.render(Self.bar(Self.screenshot), scale: scale))
        let layout = Self.layout(scale: scale)
        let end = layout.segments.last!.endPixel
        let x = (end + layout.trackPixels) / 2
        #expect(Self.near(pixels.rgb(x, pixels.height / 2), Self.expectedTrack(dark: false)))
    }

    @Test(arguments: [1.0, 2.0])
    func boundariesAreCrispOnWholePixels(scale: Double) throws {
        // Sur la ligne du milieu, chaque pixel est soit la couleur pleine d'un segment, soit la piste, soit le remplissage du cache :
        // aucun pixel intermédiaire (flou) entre deux segments voisins.
        let pixels = try #require(Self.render(Self.bar(Self.screenshot), scale: scale))
        let layout = Self.layout(scale: scale)
        let mid = pixels.height / 2
        for segment in layout.segments {
            let before = segment.startPixel - 1
            if before >= 0 {
                let p = pixels.rgb(before, mid)
                #expect(Self.near(p, Self.expectedTrack(dark: false)) || layout.segments.contains { $0.endPixel == segment.startPixel && $0.kind != segment.kind },
                        "pixel \(before) avant \(segment.kind) : \(p)")
            }
            if segment.kind != .cached {
                #expect(Self.near(pixels.rgb(segment.startPixel, mid), Self.expected(segment.kind, dark: false)), "premier pixel de \(segment.kind)")
                #expect(Self.near(pixels.rgb(segment.endPixel - 1, mid), Self.expected(segment.kind, dark: false)), "dernier pixel de \(segment.kind)")
            }
        }
        // Le pixel de séparation est la piste, pas un mélange.
        let first = layout.segments[0]
        if MemoryBar.gapPixels > 0 {
            #expect(Self.near(pixels.rgb(first.endPixel, mid), Self.expectedTrack(dark: false)))
        }
    }

    @Test(arguments: [1.0, 2.0])
    func theCacheIsLighterThanEveryUsedSegment(scale: Double) throws {
        for dark in [false, true] {
            let pixels = try #require(Self.render(Self.bar(Self.screenshot), scale: scale, dark: dark))
            let layout = Self.layout(scale: scale)
            let mid = pixels.height / 2
            let track = Self.luminance(Self.expectedTrack(dark: dark))
            func distance(_ kind: MemorySegmentKind) -> Double {
                let s = layout.segments.first { $0.kind == kind }!
                return abs(Self.luminance(pixels.rgb((s.startPixel + s.endPixel) / 2, mid)) - track)
            }
            // « Plus léger » : plus près de la piste que les segments pleins (en clair comme en sombre).
            for used in [MemorySegmentKind.app, .wired, .compressed] {
                #expect(distance(.cached) < distance(used), "dark=\(dark) échelle \(scale) : le cache doit être plus léger que \(used)")
            }
            // Mais pas invisible : un contour d'un pixel de la couleur du jeton marque ses bords.
            let cache = layout.segments.first { $0.kind == .cached }!
            #expect(Self.near(pixels.rgb(cache.startPixel, mid), Self.expected(.cached, dark: dark)), "contour gauche du cache")
            #expect(Self.near(pixels.rgb(cache.endPixel - 1, mid), Self.expected(.cached, dark: dark)), "contour droit du cache")
        }
    }

    @Test func increasedContrastDrawsTheStrongerColours() throws {
        for dark in [false, true] {
            let pixels = try #require(Self.render(Self.bar(Self.screenshot), scale: 2, dark: dark, increased: true))
            let layout = Self.layout(scale: 2)
            let s = layout.segments[0]
            #expect(Self.near(pixels.rgb((s.startPixel + s.endPixel) / 2, pixels.height / 2), Self.expected(.app, dark: dark, increased: true)))
        }
    }

    @Test func theBarIsNotTintedByThePressureLevel() throws {
        var calm = Self.screenshot; calm.pressure = .normal
        var critical = Self.screenshot; critical.pressure = .critical
        let a = try #require(Self.render(Self.bar(calm), scale: 2))
        let b = try #require(Self.render(Self.bar(critical), scale: 2))
        #expect(a.bytes == b.bytes)
    }

    @Test func theBarIsNotTintedByTheUsedFractionEither() throws {
        // L'ancienne barre était verte, orange ou rouge selon la part utilisée. Les segments gardent leurs couleurs à 95 %.
        let heavy = MemoryStats(total: 16 * Self.GB, app: Self.gb(9), wired: Self.gb(3), compressed: Self.gb(3.4), cached: 0, swapUsed: 0, pressure: .normal)
        let pixels = try #require(Self.render(Self.bar(heavy), scale: 2))
        let layout = Self.layout(scale: 2, memory: heavy)
        let s = layout.segments[0]
        #expect(Self.near(pixels.rgb((s.startPixel + s.endPixel) / 2, pixels.height / 2), Self.expected(.app, dark: false)))
    }

    @Test(arguments: [nil, 0])
    func noTotalDrawsAnEmptyTrack(total: UInt64?) throws {
        let memory = total.map { MemoryStats(total: $0, app: Self.GB, wired: Self.GB, compressed: Self.GB, cached: Self.GB, swapUsed: 0, pressure: .normal) }
        let pixels = try #require(Self.render(Self.bar(memory), scale: 2))
        let mid = pixels.height / 2
        for x in stride(from: 10, to: pixels.width - 10, by: 37) {
            #expect(Self.near(pixels.rgb(x, mid), Self.expectedTrack(dark: false)), "x=\(x)")
        }
    }

    @Test(arguments: [1.0, 2.0])
    func theTrackFillsTheFrameFromItsFirstToItsLastPixelWithNothingBeyond(scale: Double) throws {
        // Les bouts de la piste tombent sur des pixels entiers : premier et dernier pixel de l'image sont la piste, pleins
        // (pas de demi-pixel mélangé au fond), sur une ligne qui ne touche pas les coins arrondis.
        let width: CGFloat = scale == 2 ? 300.5 : 300      // 601 px à 2x : un nombre impair de pixels
        let pixels = try #require(Self.render(Self.bar(nil, width: width), scale: scale))
        #expect(pixels.width == Int(width * scale))
        let mid = pixels.height / 2
        #expect(Self.near(pixels.rgb(0, mid), Self.expectedTrack(dark: false), tolerance: 1))
        #expect(Self.near(pixels.rgb(pixels.width - 1, mid), Self.expectedTrack(dark: false), tolerance: 1))
        #expect(MemoryBarLayout.make(memory: nil, trackWidth: Double(width), scale: scale).trackPixels == pixels.width)
    }

    @Test func theBarHasAWholePointHeight() throws {
        let pixels = try #require(Self.render(Self.bar(Self.screenshot), scale: 2))
        #expect(pixels.height == Int(MemoryBar.height) * 2)
        #expect(MemoryBar.height == MemoryBar.height.rounded())
    }

    // MARK: Légende

    private static func row(_ kind: MemorySegmentKind) -> some View {
        MemoryRow("Apps", "4 GB", legend: kind).frame(width: 300)
    }

    @Test(arguments: [MemorySegmentKind.app, .wired, .compressed], [false, true])
    func theLegendDotHasTheSegmentColour(kind: MemorySegmentKind, dark: Bool) throws {
        let pixels = try #require(Self.render(Self.row(kind), scale: 2, dark: dark))
        let got = pixels.rgb(Int(MemoryRow.dotSize), pixels.height / 2)         // centre du point (à 3,5 pt = 7 px)
        #expect(Self.near(got, Self.expected(kind, dark: dark)), "\(kind) dark=\(dark) : \(got)")
    }

    @Test(arguments: [false, true])
    func theCacheLegendDotIsTheSameRingAndLightFillAsItsSegment(dark: Bool) throws {
        let pixels = try #require(Self.render(Self.row(.cached), scale: 4, dark: dark))
        let y = pixels.height / 2
        let centre = pixels.rgb(Int(MemoryRow.dotSize * 4 / 2), y)
        let ring = pixels.rgb(1, y)
        let token = Self.expected(.cached, dark: dark)
        #expect(!Self.near(centre, token, tolerance: 6), "le centre du point du cache est le remplissage léger")
        let background: (r: Int, g: Int, b: Int) = dark ? (30, 30, 30) : (255, 255, 255)
        #expect(Self.luminance(centre) != Self.luminance(background), "le point du cache n'est pas vide")
        #expect(abs(ring.r - token.r) < abs(ring.r - background.r) || abs(ring.g - token.g) < abs(ring.g - background.g),
                "le bord du point est plus proche de la couleur du jeton que du fond : \(ring)")
    }

    @Test func theLegendDotIsDrawnWithTheSameColourFunctionAsTheBar() throws {
        let source = try SourceText.read("Sources/Soaro/Views/MemoryBar.swift")
        #expect(source.contains("MemorySegmentStyle.color("))
        // Une seule fonction de couleur : ni la barre ni les lignes n'ont de couleur codée en dur pour les segments.
        let bar = try SourceText.typeBody("struct MemoryBar:", in: "Sources/Soaro/Views/MemoryBar.swift")
        let row = try SourceText.typeBody("struct MemoryRow:", in: "Sources/Soaro/Views/MemoryBar.swift")
        for body in [bar, row] {
            #expect(!body.contains(".blue") && !body.contains(".purple") && !body.contains(".teal") && !body.contains("Color(.sRGB"))
        }
    }

    // MARK: Alignement des libellés

    /// Première colonne de pixels (à partir de `from`) qui n'est pas le fond, sur toute la hauteur.
    private static func firstInkColumn(_ p: Pixels, from: Int, background: (r: Int, g: Int, b: Int)) -> Int? {
        (from..<p.width).first { x in p.column(x).contains { !near($0, background, tolerance: 8) } }
    }

    @Test(arguments: [1.0, 2.0])
    func labelsStartAtTheSameXWithOrWithoutALegendDot(scale: Double) throws {
        let slot = Int((MemoryRow.dotSize + MemoryRow.dotSpacing) * scale)
        func start(_ view: some View) throws -> Int {
            let p = try #require(Self.render(view.frame(width: 300), scale: scale))
            return try #require(Self.firstInkColumn(p, from: slot - 1, background: (255, 255, 255)))
        }
        let withDot = try start(MemoryRow("Apps", "4 GB", legend: .app))
        let withoutDot = try start(MemoryRow("Apps", "4 GB"))
        let level = try start(MemoryRow("Apps", "4 GB", valueDot: .orange))
        #expect(withDot == withoutDot, "libellé avec point : \(withDot), sans : \(withoutDot)")
        #expect(level == withoutDot)
    }

    @Test func everyRowOfTheSectionReservesTheSameLeadingSlot() throws {
        let section = try SourceText.typeBody("struct MemorySection:", in: "Sources/Soaro/Views/MemoryBar.swift")
        #expect(section.components(separatedBy: "MemoryRow(").count - 1 == 6, "six lignes : pression, 4 catégories, swap")
        #expect(!section.contains("KeyValueRow("), "les lignes de la mémoire passent toutes par MemoryRow pour garder le même gabarit")
    }

    // MARK: Accessibilité

    @Test func theValueListsEachCategoryWithItsSizeThenTheTotal() {
        let value = MemoryBarAccessibility.value(for: Self.screenshot)
        for (label, bytes) in [("Apps", Self.screenshot.app), ("System (wired)", Self.screenshot.wired),
                               ("Compressed", Self.screenshot.compressed), ("Cached (reclaimable)", Self.screenshot.cached)] {
            #expect(value.contains("\(String(localized: String.LocalizationValue(label))) \(Format.bytes(bytes))"), "\(label) absent de « \(value) »")
        }
        #expect(value.hasSuffix(String(localized: "of \(Format.bytes(Self.screenshot.total))")))
        // L'ordre est celui de la barre.
        let positions = ["Apps", "System (wired)", "Compressed", "Cached (reclaimable)"].map { value.range(of: String(localized: String.LocalizationValue($0)))!.lowerBound }
        #expect(positions == positions.sorted())
    }

    @Test func theValueSkipsEmptyCategories() {
        let m = MemoryStats(total: 8 * Self.GB, app: 2 * Self.GB, wired: Self.GB, compressed: 0, cached: 0, swapUsed: 0, pressure: .normal)
        let value = MemoryBarAccessibility.value(for: m)
        #expect(!value.contains(String(localized: "Compressed")))
        #expect(!value.contains(String(localized: "Cached (reclaimable)")))
        #expect(value.contains(Format.bytes(2 * Self.GB)))
    }

    @Test func theValueNeverMentionsSwapOrPressure() {
        let value = MemoryBarAccessibility.value(for: Self.screenshot)
        #expect(!value.contains(Format.bytes(Self.screenshot.swapUsed)))
        #expect(!value.contains(String(localized: "Swap used")))
    }

    @Test func aMissingOrEmptyMemoryHasAnUnavailableValue() {
        #expect(MemoryBarAccessibility.value(for: nil) == String(localized: "Unavailable"))
        let none = MemoryStats(total: 0, app: 0, wired: 0, compressed: 0, cached: 0, swapUsed: 0, pressure: .normal)
        #expect(MemoryBarAccessibility.value(for: none) == String(localized: "Unavailable"))
    }

    @Test func theLabelIsMemoryUsage() {
        #expect(MemoryBarAccessibility.label == String(localized: "Memory usage"))
    }

    @Test func theComposerJoinsPartsWithCommasAndEndsWithTheTotal() {
        let text = MemoryBarAccessibility.compose(parts: [("Apps", "4 GB"), ("Compressed", "1 GB")], total: "16 GB", ofTotal: { "of \($0)" })
        #expect(text == "Apps 4 GB, Compressed 1 GB, of 16 GB")
    }

    @Test func theBarIsOneAccessibilityElementWithLabelAndValue() throws {
        let body = try SourceText.typeBody("struct MemoryBar:", in: "Sources/Soaro/Views/MemoryBar.swift")
        #expect(body.contains(".accessibilityElement(children: .ignore)"))
        #expect(body.contains(".accessibilityLabel(MemoryBarAccessibility.label)"))
        #expect(body.contains(".accessibilityValue(MemoryBarAccessibility.value(for: memory))"))
    }

    @Test func theBarHasNoAnimationSoReduceMotionIsRespected() throws {
        let source = try SourceText.read("Sources/Soaro/Views/MemoryBar.swift")
        for forbidden in [".animation(", "withAnimation", ".transition(", "TimelineView"] {
            #expect(!source.contains(forbidden), "\(forbidden) interdit : la barre se met à jour toutes les 3 s sans animation")
        }
    }

    // MARK: Niveau de pression

    @Test func thePressureDotAppearsNextToThePercentageOnlyAboveNormal() {
        #expect(MemorySection.pressureIndicator(for: .normal) == nil)
        #expect(MemorySection.pressureIndicator(for: .warning) == .orange)
        #expect(MemorySection.pressureIndicator(for: .critical) == .red)
    }

    @Test func thePressureRowKeepsItsDotsAsBefore() {
        #expect(MemorySection.pressureRowColor(.normal) == .green)
        #expect(MemorySection.pressureRowColor(.warning) == .orange)
        #expect(MemorySection.pressureRowColor(.critical) == .red)
        #expect(MemorySection.swapColor(swapUsed: 3_000_000_000) == .orange)
        #expect(MemorySection.swapColor(swapUsed: 2_999_999_999) == nil)
    }

    // MARK: Sources

    @Test func theMemorySectionNoLongerUsesASingleTintedProgressView() throws {
        let tab = try SourceText.read("Sources/Soaro/Views/PerformanceTab.swift")
        let section = try SourceText.typeBody("struct MemorySection:", in: "Sources/Soaro/Views/MemoryBar.swift")
        #expect(tab.contains("MemorySection("))
        #expect(!section.contains("ProgressView"))
        #expect(!section.contains("loadColor"))
        // Le disque garde sa barre de progression teintée : seule la mémoire a changé.
        #expect(tab.contains("ProgressView(value: s.disk.usedFraction)"))
        let memoryFunction = tab.components(separatedBy: "// MARK: GPU").first!.components(separatedBy: "// MARK: Mémoire").last!
        #expect(!memoryFunction.contains("ProgressView"))
        #expect(!memoryFunction.contains("loadColor(m.usedFraction)"))
    }

    @Test func theOverviewMemoryCardIsUntouched() throws {
        let overview = try SourceText.read("Sources/Soaro/Views/OverviewTab.swift")
        #expect(overview.contains("title: \"Memory\", systemImage: \"memorychip\", value: Format.percent(s.memory.usedFraction)"))
        #expect(overview.contains("tint: loadColor(s.memory.usedFraction), history: state.memoryHistory"))
        #expect(!overview.contains("MemoryBar"))
        #expect(!overview.contains("MemorySection"))
        // La carte Aperçu utilise `StatCard`, que cette tranche ne modifie pas.
        let components = try SourceText.read("Sources/Soaro/Views/Components.swift")
        #expect(!components.contains("MemoryBar") && !components.contains("MemorySegment"))
    }

    @Test func theBarReadsTheDisplayScaleFromTheEnvironment() throws {
        let body = try SourceText.typeBody("struct MemoryBar:", in: "Sources/Soaro/Views/MemoryBar.swift")
        #expect(body.contains("@Environment(\\.displayScale)"))
        #expect(body.contains("MemoryBarLayout.make("))
    }

    @Test func theNewKeysAreInTheCatalogInNineLanguages() throws {
        let catalog = try TranslationCatalog.loadCatalog("Sources/Soaro/Resources/Localizable.xcstrings")
        let strings = try #require(catalog["strings"] as? [String: Any])
        for key in ["Memory usage", "of %@"] {
            let entry = try #require(strings[key] as? [String: Any], "\(key) absent du catalogue")
            let languages = Set((entry["localizations"] as? [String: Any] ?? [:]).keys)
            for language in TranslationCatalog.requiredTranslations { #expect(languages.contains(language), "\(key) / \(language)") }
        }
    }
}

/// Lecture de source pour les gardes (même approche que `SupportingTextStyleTests`).
enum SourceText {
    static func read(_ path: String) throws -> String {
        try String(contentsOf: RepositoryRoot.url().appendingPathComponent(path), encoding: .utf8)
    }

    /// Corps d'un type de premier niveau : de sa déclaration à l'accolade fermante en colonne 0.
    static func typeBody(_ declaration: String, in path: String) throws -> String {
        let text = try read(path)
        let start = try #require(text.range(of: declaration), "\(declaration) introuvable dans \(path)")
        let end = text.range(of: "\n}\n", range: start.upperBound..<text.endIndex)?.upperBound ?? text.endIndex
        return String(text[start.lowerBound..<end])
    }
}
