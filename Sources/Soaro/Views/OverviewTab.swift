import SwiftUI

struct OverviewTab: View {
    @EnvironmentObject private var state: AppState
    @State private var sort: ProcessSort = .cpu

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            gauges
            recommendations
            adviceSection
            processes
        }
    }

    // MARK: Jauges

    @ViewBuilder private var gauges: some View {
        if let s = state.snapshot {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
            LazyVGrid(columns: columns, spacing: 8) {
                StatCard(
                    title: "CPU", systemImage: "cpu", value: Format.percent(s.cpu.total),
                    subtitle: "Util. \(Format.percent(s.cpu.user)) · Sys. \(Format.percent(s.cpu.system))",
                    tint: loadColor(s.cpu.total), history: state.cpuHistory
                )
                StatCard(
                    title: "Mémoire", systemImage: "memorychip", value: Format.percent(s.memory.usedFraction),
                    subtitle: "\(Format.bytes(s.memory.used)) / \(Format.bytes(s.memory.total))",
                    tint: loadColor(s.memory.usedFraction), history: state.memoryHistory
                )
                if let gpu = s.gpu {
                    StatCard(
                        title: "GPU", systemImage: "display", value: Format.percent(gpu.utilization),
                        subtitle: s.sensors?.gpu.map { "\(Int($0)) °C · \(Format.bytes(gpu.memoryUsed))" } ?? Format.bytes(gpu.memoryUsed),
                        tint: loadColor(gpu.utilization), history: state.gpuHistory
                    )
                }
                StatCard(
                    title: "Disque", systemImage: "internaldrive", value: Format.percent(s.disk.usedFraction),
                    subtitle: "\(Format.fileBytes(s.disk.available)) libres",
                    tint: loadColor(s.disk.usedFraction), fraction: s.disk.usedFraction
                )
                if let net = s.network {
                    StatCard(
                        title: "Réseau", systemImage: "network", value: "↓ " + Format.rate(net.downRate), valueSize: 15,
                        subtitle: "↑ " + Format.rate(net.upRate),
                        tint: .blue, history: state.netDownHistory, autoScaleFloor: 50_000
                    )
                }
                if let b = s.battery {
                    StatCard(
                        title: "Batterie", systemImage: Self.batterySymbol(b), value: Format.percent(b.percent / 100),
                        subtitle: Self.batterySubtitle(b),
                        tint: b.isPluggedIn ? .green : levelColor(b.percent / 100), fraction: b.percent / 100
                    )
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 90)
        }
    }

    static func batterySymbol(_ b: BatteryStats) -> String {
        if b.isCharging { return "battery.100percent.bolt" }
        switch b.percent {
        case ..<15: return "battery.0percent"
        case ..<40: return "battery.25percent"
        case ..<65: return "battery.50percent"
        case ..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    static func batterySubtitle(_ b: BatteryStats) -> String {
        if b.isCharging { return b.minutesRemaining.map { "En charge · \(Format.minutes($0))" } ?? "En charge" }
        if b.isPluggedIn { return b.isFullyCharged ? "Chargée · secteur" : "Sur secteur" }
        return b.minutesRemaining.map { "\(Format.minutes($0)) restantes" } ?? "Sur batterie"
    }

    // MARK: Recommandations

    @ViewBuilder private var recommendations: some View {
        SectionHeader(title: "Recommandations")
        if state.recommendations.isEmpty {
            Label("Rien à signaler : votre Mac est en bonne forme.", systemImage: "checkmark.seal.fill")
                .font(.callout)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(state.recommendations) { rec in
                RecommendationRow(rec: rec) { action in state.perform(action) }
            }
        }
    }

    // MARK: Conseils

    @ViewBuilder private var adviceSection: some View {
        if !state.advice.isEmpty {
            SectionHeader(title: "Conseils de réglage")
            ForEach(state.advice) { item in
                AdviceRow(advice: item, onAction: { state.perform($0) }, onDismiss: { state.dismissAdvice(item) })
            }
        }
    }

    // MARK: Processus

    @ViewBuilder private var processes: some View {
        HStack {
            SectionHeader(title: "Plus gourmandes")
            Spacer()
            Picker("Tri", selection: $sort) {
                ForEach(ProcessSort.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
        }
        ProcessList(sort: sort)
    }
}

struct ProcessList: View {
    @EnvironmentObject private var state: AppState
    let sort: ProcessSort
    var count = 5

    var body: some View {
        let list = state.top(by: sort, count: count)
        if list.isEmpty {
            Text("Chargement…").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 2) {
                ForEach(list) { group in
                    ProcessRow(group: group, sort: sort) {
                        if let path = group.appPath { state.quitApp(path: path, name: group.name) }
                    }
                }
            }
        }
    }
}
