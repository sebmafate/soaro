import SwiftUI

extension Severity {
    var color: Color {
        switch self {
        case .info: .blue
        case .warning: .orange
        case .critical: .red
        }
    }

    var symbol: String {
        switch self {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}

/// Couleur d'une jauge selon sa charge (0...1) : vert → orange → rouge.
func loadColor(_ fraction: Double) -> Color {
    switch fraction {
    case ..<0.6: .green
    case ..<0.85: .orange
    default: .red
    }
}

/// Couleur d'un niveau où « bas » est mauvais (batterie, santé).
func levelColor(_ fraction: Double) -> Color {
    switch fraction {
    case ..<0.2: .red
    case ..<0.4: .orange
    default: .green
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color
    /// Si défini, l'échelle s'adapte aux valeurs (débits) avec ce plancher ; sinon 0...1.
    var autoScaleFloor: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let points = normalizedPoints(in: geo.size)
            ZStack {
                if points.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                        points.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: points.last!.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))

                    Path { p in
                        p.move(to: points[0])
                        points.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let scale = autoScaleFloor.map { max(values.max() ?? 0, $0) } ?? 1
        let step = size.width / CGFloat(max(values.count - 1, 1))
        return values.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step, y: size.height * (1 - CGFloat(min(max(value / scale, 0), 1))))
        }
    }
}

struct StatCard: View {
    let title: LocalizedStringKey
    let systemImage: String
    let value: String
    var valueSize: CGFloat = 24
    let subtitle: String
    var tint: Color = .green
    /// Barre de progression (si pas d'historique).
    var fraction: Double? = nil
    var history: [Double]? = nil
    var autoScaleFloor: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)

            Text(value)
                .font(.system(size: valueSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Group {
                if let history {
                    Sparkline(values: history, color: tint, autoScaleFloor: autoScaleFloor)
                } else if let fraction {
                    ProgressView(value: min(max(fraction, 0), 1)).tint(tint)
                } else {
                    Color.clear
                }
            }
            .frame(height: 22)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    /// La case « Select all » de la section, avant le titre ; `nil` : l'en-tête ne change pas.
    var selectAll: SelectAllControl? = nil

    var body: some View {
        if let selectAll {
            HStack(spacing: 6) {
                SelectAllCheckbox(control: selectAll)
                titleText
            }
            .padding(.top, 4)
        } else {
            titleText.padding(.top, 4)
        }
    }

    private var titleText: some View {
        Text(title)
            .textCase(.uppercase)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct KeyValueRow: View {
    let label: LocalizedStringKey
    let value: String
    var color: Color? = nil

    init(_ label: LocalizedStringKey, _ value: String, color: Color? = nil) {
        self.label = label
        self.value = value
        self.color = color
    }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            if let color { Circle().fill(color).frame(width: 7, height: 7) }
            Text(value).monospacedDigit()
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }
}

/// Un cadre pour regrouper une section.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(flatOpacity: 0.4)
    }
}

/// Une barre verticale par cœur CPU ; les cœurs d'efficacité sont étiquetés E, les autres P.
struct CoreBars: View {
    let cpu: CPUStats

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(cpu.perCore.enumerated()), id: \.offset) { index, load in
                VStack(spacing: 3) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                        RoundedRectangle(cornerRadius: 3).fill(loadColor(load))
                            .frame(height: max(2, 44 * load))
                    }
                    .frame(height: 44)
                    Text(cpu.coreLabel(index))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Load per core")
        .accessibilityValue(cpu.perCore.map { Format.percent($0) }.joined(separator: ", "))
    }
}

extension CPUStats {
    /// « E0, E1, P0 … P7 » : numérotation par type de cœur.
    func coreLabel(_ index: Int) -> String {
        index < efficiencyCores ? "E\(index)" : "P\(index - efficiencyCores)"
    }
}

struct EmptyHint: View {
    private let content: Text
    let systemImage: String
    /// `true` : jeton « texte de soutien » (écran des simulateurs) ; `false` : `.secondary` comme avant.
    let supporting: Bool

    /// Texte du catalogue (clé littérale).
    init(text: LocalizedStringKey, systemImage: String = "info.circle", supporting: Bool = false) {
        self.content = Text(text)
        self.systemImage = systemImage
        self.supporting = supporting
    }

    /// Texte déjà traduit ou calculé : affiché tel quel, jamais lu comme du Markdown ni cherché dans le catalogue.
    init(verbatim: String, systemImage: String = "info.circle", supporting: Bool = false) {
        self.content = Text(verbatim: verbatim)
        self.systemImage = systemImage
        self.supporting = supporting
    }

    var body: some View {
        Group {
            if supporting {
                Label { content } icon: { Image(systemName: systemImage) }.supportingText()
            } else {
                Label { content } icon: { Image(systemName: systemImage) }.foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppIconView: View {
    let path: String?
    var body: some View {
        if let path {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
        } else {
            Image(systemName: "terminal").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Lignes partagées

struct RecommendationRow: View {
    let rec: Recommendation
    let onAction: (RecommendedAction) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: rec.severity.symbol)
                .foregroundStyle(rec.severity.color)
                .font(.title3)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(rec.title).font(.callout.weight(.semibold))
                Text(rec.detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = rec.action, let label = rec.actionLabel {
                    Button(label) { onAction(action) }
                        .controlSize(.small)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .cardBackground(tint: rec.severity.color)
    }
}

struct AdviceRow: View {
    let advice: Advice
    let onAction: (Advice.Action) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: advice.systemImage)
                .foregroundStyle(.teal)
                .font(.title3)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(advice.title).font(.callout.weight(.semibold))
                Text(advice.detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let action = advice.action, let label = advice.actionLabel {
                        Button(label) { onAction(action) }.controlSize(.small)
                    }
                    Button("Dismiss", action: onDismiss)
                        .controlSize(.small)
                        .buttonStyle(.borderless)
                        .help("Do not show this tip again")
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .cardBackground(flatOpacity: 0.4)
    }
}

struct ProcessRow: View {
    let group: ProcessGroup
    let sort: ProcessSort
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            AppIconView(path: group.appPath).frame(width: 20, height: 20)
            Text(group.name).font(.callout).lineLimit(1)
            Spacer()
            column("\(Int(group.cpu)) %", highlighted: sort == .cpu, width: 50)
            column(Format.bytes(group.memory), highlighted: sort == .memory, width: 64)
            column(Format.rate(group.ioWriteRate + group.ioReadRate), highlighted: sort == .disk, width: 72)
            Button(action: onQuit) { Image(systemName: "xmark.circle") }
                .buttonStyle(.borderless)
                .opacity(group.canQuit ? 1 : 0)
                .disabled(!group.canQuit)
                .help("Quit \(group.name)")
        }
        .font(.caption.monospacedDigit())
        .padding(.vertical, 3)
    }

    private func column(_ text: String, highlighted: Bool, width: CGFloat) -> some View {
        Text(text)
            .foregroundStyle(highlighted ? .primary : .tertiary)
            .frame(width: width, alignment: .trailing)
            .lineLimit(1)
    }
}

struct CleanupRow: View {
    let kind: CleanupKind
    let size: UInt64?
    let busy: Bool
    let onClean: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.systemImage).frame(width: 20).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title).font(.callout)
                Text(kind.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Text(size.map { Format.fileBytes($0) } ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help(size == nil && kind == .trash
                          ? "macOS protects the Trash: its size cannot be read without “Full Disk Access”, but Soaro can still empty it."
                          : "")
                Button("Clean", action: onClean)
                    .controlSize(.small)
                    .disabled(kind != .trash && (size ?? 0) == 0)
            }
        }
        .padding(.vertical, 3)
    }
}
