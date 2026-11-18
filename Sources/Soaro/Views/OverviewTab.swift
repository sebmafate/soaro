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
                    subtitle: String(localized: "User \(Format.percent(s.cpu.user)) · System \(Format.percent(s.cpu.system))"),
                    tint: loadColor(s.cpu.total), history: state.cpuHistory
                )
                StatCard(
                    title: "Memory", systemImage: "memorychip", value: Format.percent(s.memory.usedFraction),
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
                    title: "Disk", systemImage: "internaldrive", value: Format.percent(s.disk.usedFraction),
                    subtitle: String(localized: "\(Format.fileBytes(s.disk.available)) free"),
                    tint: loadColor(s.disk.usedFraction), fraction: s.disk.usedFraction
                )
                if let net = s.network {
                    StatCard(
                        title: "Network", systemImage: "network", value: "↓ " + Format.rate(net.downRate), valueSize: 15,
                        subtitle: "↑ " + Format.rate(net.upRate),
                        tint: .blue, history: state.netDownHistory, autoScaleFloor: 50_000
                    )
                }
                if let b = s.battery { Self.batteryCard(b, thresholds: PressureThresholds.load().battery) }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 90)
        }
    }

    /// La carte « Battery » : l'icône dessinée (SL21, SL24 : la même image nette que le libellé de la barre de menus), le niveau, l'état de charge.
    static func batteryCard(_ b: BatteryStats, thresholds: LevelThresholds) -> some View {
        StatCard(
            title: "Battery", systemImage: "", value: Format.percent(b.percent / 100),
            subtitle: batterySubtitle(b),
            tint: BatteryGlyphColors.barTint(for: b, thresholds: thresholds), fraction: b.percent / 100,
            icon: AnyView(BatteryGlyphImage(percent: b.percent, power: b.powerState, level: .battery(b, thresholds: thresholds), body: BatteryGlyphGeometry.cardBody))
        )
    }

    static func batterySubtitle(_ b: BatteryStats) -> String {
        if b.isCharging { return b.minutesRemaining.map { String(localized: "Charging · \(Format.minutes($0))") } ?? String(localized: "Charging") }
        if b.isPluggedIn { return b.isFullyCharged ? String(localized: "Charged · plugged in") : String(localized: "On power adapter") }
        return b.minutesRemaining.map { String(localized: "\(Format.minutes($0)) left") } ?? String(localized: "On battery")
    }

    // MARK: Recommandations

    @ViewBuilder private var recommendations: some View {
        SectionHeader(title: "Recommendations")
        if state.recommendations.isEmpty {
            Label("Nothing to report: your Mac is in good shape.", systemImage: "checkmark.seal.fill")
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
            SectionHeader(title: "Settings tips")
            ForEach(state.advice) { item in
                AdviceRow(advice: item, onAction: { state.perform($0) }, onDismiss: { state.dismissAdvice(item) })
            }
        }
    }

    // MARK: Processus

    @ViewBuilder private var processes: some View {
        HStack {
            SectionHeader(title: "Top consumers")
            Spacer()
            Picker("Sort", selection: $sort) {
                ForEach(ProcessSort.allCases) { Text($0.title).tag($0) }
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
            Text("Loading…").font(.caption).foregroundStyle(.supportingText)
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
