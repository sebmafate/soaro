import SwiftUI

// MARK: - Couleur d'un segment depuis l'environnement

/// Une seule fonction de couleur pour la barre et pour les points de légende : les deux se résolvent depuis les
/// mêmes jetons (`DesignTokens.memorySegment`), selon le thème et « Augmenter le contraste ».
enum MemorySegmentStyle {
    static func color(_ kind: MemorySegmentKind, dark: Bool, increased: Bool) -> Color {
        DesignTokens.memorySegment(kind, dark: dark, contrastIncreased: increased).color
    }

    static func color(_ kind: MemorySegmentKind, in environment: EnvironmentValues) -> Color {
        color(kind, dark: environment.colorScheme == .dark, increased: contrastIncreased(in: environment))
    }

    /// Piste : le jeton de piste, à son opacité absolue.
    static func trackColor(dark: Bool) -> Color {
        let base = DesignTokens.memoryTrackBase(dark: dark)
        return Color(.sRGB, red: base.red, green: base.green, blue: base.blue, opacity: DesignTokens.memoryTrackAlpha(dark: dark))
    }

    /// « Augmenter le contraste » du système, sauf si un test impose la valeur (`colorSchemeContrast` est en lecture seule).
    static func contrastIncreased(_ system: ColorSchemeContrast, override: Bool?) -> Bool {
        override ?? (system == .increased)
    }

    static func contrastIncreased(in environment: EnvironmentValues) -> Bool {
        contrastIncreased(environment.colorSchemeContrast, override: environment.contrastIncreasedOverride)
    }
}

private struct ContrastIncreasedOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// Pour les tests de rendu seulement : `colorSchemeContrast` ne peut pas être posé à la main. `nil` dans l'application.
    var contrastIncreasedOverride: Bool? {
        get { self[ContrastIncreasedOverrideKey.self] }
        set { self[ContrastIncreasedOverrideKey.self] = newValue }
    }
}

// MARK: - Accessibilité

enum MemoryBarAccessibility {
    static var label: String { String(localized: "Memory usage") }

    /// « Apps 4 GB, System (wired) 2.8 GB, Compressed 5.8 GB, Cached (reclaimable) 2.5 GB, of 16 GB ».
    /// Les catégories vides sont omises, comme les segments ; le swap et la pression ne sont pas dans la barre.
    static func value(for memory: MemoryStats?) -> String {
        guard let memory, memory.total > 0 else { return String(localized: "Unavailable") }
        let parts: [(label: String, size: String)] = [
            (String(localized: "Apps"), memory.app),
            (String(localized: "System (wired)"), memory.wired),
            (String(localized: "Compressed"), memory.compressed),
            (String(localized: "Cached (reclaimable)"), memory.cached),
        ].filter { $0.1 > 0 }.map { ($0.0, Format.bytes($0.1)) }
        return compose(parts: parts, total: Format.bytes(memory.total), ofTotal: { String(localized: "of \($0)") })
    }

    static func compose(parts: [(label: String, size: String)], total: String, ofTotal: (String) -> String) -> String {
        (parts.map { "\($0.label) \($0.size)" } + [ofTotal(total)]).joined(separator: ", ")
    }
}

// MARK: - La barre

/// Barre d'usage de la mémoire découpée par genre d'usage (SL26). Largeurs proportionnelles à la RAM totale ;
/// frontières sur des pixels entiers de l'écran (`displayScale`) ; aucune animation : elle se met à jour toutes les 3 s.
/// Un seul élément d'accessibilité ; la couleur n'est jamais le seul indice (les lignes dessous donnent les chiffres).
struct MemoryBar: View {
    static let height: CGFloat = 8
    static let cornerRadius: CGFloat = 2
    static let gapPixels = MemoryBarLayout.defaultGapPixels

    let memory: MemoryStats?

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.contrastIncreasedOverride) private var contrastOverride

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            draw(in: &context, size: size)
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MemoryBarAccessibility.label)
        .accessibilityValue(MemoryBarAccessibility.value(for: memory))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let scale = displayScale > 0 ? displayScale : 1
        let layout = MemoryBarLayout.make(memory: memory, trackWidth: size.width, scale: scale, gapPixels: Self.gapPixels)
        guard layout.trackPixels > 0 else { return }
        let dark = colorScheme == .dark
        let increased = MemorySegmentStyle.contrastIncreased(contrast, override: contrastOverride)
        let pixel = 1 / scale

        func x(_ pixels: Int) -> CGFloat { CGFloat(pixels) * pixel }
        let track = CGRect(x: 0, y: 0, width: x(layout.trackPixels), height: size.height)
        context.fill(Path(roundedRect: track, cornerRadius: Self.cornerRadius), with: .color(MemorySegmentStyle.trackColor(dark: dark)))

        // Les segments sont rognés par la piste : seuls ses deux bouts sont arrondis, les frontières restent nettes.
        context.clip(to: Path(roundedRect: track, cornerRadius: Self.cornerRadius))
        for segment in layout.segments {
            let rect = CGRect(x: x(segment.startPixel), y: 0, width: x(segment.width), height: size.height)
            let color = MemorySegmentStyle.color(segment.kind, dark: dark, increased: increased)
            if segment.kind == .cached {
                // Cache libérable : contour d'un pixel et remplissage léger, pour montrer qu'il n'est pas « utilisé ».
                context.fill(Path(rect), with: .color(color.opacity(DesignTokens.memoryCacheFillAlpha)))
                let edges = [
                    CGRect(x: rect.minX, y: 0, width: rect.width, height: pixel),
                    CGRect(x: rect.minX, y: size.height - pixel, width: rect.width, height: pixel),
                    CGRect(x: rect.minX, y: 0, width: pixel, height: size.height),
                    CGRect(x: rect.maxX - pixel, y: 0, width: pixel, height: size.height),
                ]
                for edge in edges { context.fill(Path(edge), with: .color(color)) }
            } else {
                context.fill(Path(rect), with: .color(color))
            }
        }
    }
}

// MARK: - Point de légende

/// Point de légende d'une ligne : même couleur que son segment (le cache : même contour et même remplissage léger).
struct MemoryLegendDot: View {
    let kind: MemorySegmentKind
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.contrastIncreasedOverride) private var contrastOverride

    var body: some View {
        let color = MemorySegmentStyle.color(kind, dark: colorScheme == .dark,
                                             increased: MemorySegmentStyle.contrastIncreased(contrast, override: contrastOverride))
        Group {
            if kind == .cached {
                Circle().fill(color.opacity(DesignTokens.memoryCacheFillAlpha))
                    .overlay(Circle().strokeBorder(color, lineWidth: 1))
            } else {
                Circle().fill(color)
            }
        }
        .frame(width: MemoryRow.dotSize, height: MemoryRow.dotSize)
        .accessibilityHidden(true)
    }
}

// MARK: - Ligne

/// Ligne de la section Mémoire. Même mise en page que `KeyValueRow`, avec un emplacement réservé avant le libellé :
/// les libellés restent alignés que la ligne ait un point de légende ou non.
struct MemoryRow: View {
    static let dotSize: CGFloat = 7
    static let dotSpacing: CGFloat = 6

    let label: LocalizedStringKey
    let value: String
    var valueDot: Color?
    var legend: MemorySegmentKind?

    init(_ label: LocalizedStringKey, _ value: String, valueDot: Color? = nil, legend: MemorySegmentKind? = nil) {
        self.label = label
        self.value = value
        self.valueDot = valueDot
        self.legend = legend
    }

    var body: some View {
        HStack {
            HStack(spacing: Self.dotSpacing) {
                Group {
                    if let legend { MemoryLegendDot(kind: legend) } else { Color.clear }
                }
                .frame(width: Self.dotSize, height: Self.dotSize)
                Text(label).foregroundStyle(.supportingText)
            }
            Spacer()
            if let valueDot { Circle().fill(valueDot).frame(width: Self.dotSize, height: Self.dotSize) }
            Text(value).monospacedDigit()
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Section

/// La section Mémoire de l'onglet Performances : en-tête (utilisé / total, pourcentage), barre segmentée, lignes.
///
/// Le niveau de pression ne teinte plus la barre (elle l'était selon la part utilisée, pas selon la pression) :
/// il se lit dans la ligne « Pression » (inchangée) et, au-dessus de « normal », par un point de sa couleur
/// devant le pourcentage. Le texte du pourcentage garde la couleur du texte (le orange sur fond clair n'atteint pas 4,5 : 1).
struct MemorySection: View {
    let memory: MemoryStats

    static func pressureRowColor(_ pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    /// Couleur du point devant le pourcentage : rien tant que la pression est normale.
    static func pressureIndicator(for pressure: MemoryPressure) -> Color? {
        pressure == .normal ? nil : pressureRowColor(pressure)
    }

    static func swapColor(swapUsed: UInt64) -> Color? {
        swapUsed >= 3_000_000_000 ? .orange : nil
    }

    var body: some View {
        let m = memory
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Memory")
            Card {
                HStack {
                    Text("\(Format.bytes(m.used)) / \(Format.bytes(m.total))").font(.caption.monospacedDigit())
                    Spacer()
                    HStack(spacing: 5) {
                        if let level = Self.pressureIndicator(for: m.pressure) {
                            Circle().fill(level).frame(width: MemoryRow.dotSize, height: MemoryRow.dotSize)
                        }
                        Text(Format.percent(m.usedFraction)).font(.caption.monospacedDigit())
                    }
                    .help(Self.pressureIndicator(for: m.pressure) == nil ? "" : "\(String(localized: "Pressure")): \(m.pressure.label)")
                }
                MemoryBar(memory: m)
                MemoryRow("Pressure", m.pressure.label, valueDot: Self.pressureRowColor(m.pressure))
                MemoryRow("Apps", Format.bytes(m.app), legend: .app)
                MemoryRow("System (wired)", Format.bytes(m.wired), legend: .wired)
                MemoryRow("Compressed", Format.bytes(m.compressed), legend: .compressed)
                MemoryRow("Cached (reclaimable)", Format.bytes(m.cached), legend: .cached)
                MemoryRow("Swap used", Format.bytes(m.swapUsed), valueDot: Self.swapColor(swapUsed: m.swapUsed))
            }
        }
    }
}
