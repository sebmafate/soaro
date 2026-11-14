import Charts
import SwiftUI

struct HistoryTab: View {
    @EnvironmentObject private var state: AppState
    @State private var metric: HistoryMetric = .cpu
    @State private var range: HistoryRange = .day
    @State private var rows: [HistoryRow] = []
    @State private var loaded = false

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    private struct Series: Identifiable {
        let name: String
        let color: Color
        let points: [Point]
        var id: String { name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controls
            if state.history == nil {
                EmptyHint(text: "History is unavailable (the database cannot be opened).", systemImage: "exclamationmark.triangle")
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else if rows.count < 2 {
                EmptyHint(text: "Not enough data yet: a measurement is saved every 30 seconds.", systemImage: "hourglass")
            } else {
                chart
                summary
            }
            Text("Kept for 30 days, on this Mac only (~/Library/Application Support/Soaro).")
                .font(.caption2).foregroundStyle(.secondary)
        }
        // Recharge à chaque changement de choix, puis toutes les 30 s tant que l'onglet est ouvert.
        .task(id: "\(metric.rawValue)-\(range.rawValue)") {
            while !Task.isCancelled {
                if let store = state.history { rows = await store.query(range: range) }
                loaded = true
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    // MARK: Contrôles

    private var controls: some View {
        VStack(spacing: 8) {
            Picker("Measurement", selection: $metric) {
                ForEach(HistoryMetric.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Period", selection: $range) {
                ForEach(HistoryRange.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: Données

    private var series: [Series] {
        func make(_ name: String, _ color: Color, _ value: (HistoryRow) -> Double?) -> Series {
            Series(name: name, color: color, points: rows.compactMap { row in value(row).map { Point(date: row.timestamp, value: $0) } })
        }
        switch metric {
        case .cpu: return [make("CPU", .blue) { $0.cpu.map { $0 * 100 } }]
        case .memory: return [make(String(localized: "Memory"), .purple) { $0.memory.map { $0 * 100 } }]
        case .gpu: return [make("GPU", .green) { $0.gpu.map { $0 * 100 } }]
        case .network: return [make(String(localized: "Download"), .blue) { $0.netDown }, make(String(localized: "Upload"), .orange) { $0.netUp }]
        case .disk: return [make(String(localized: "Read"), .teal) { $0.diskRead }, make(String(localized: "Write"), .pink) { $0.diskWrite }]
        case .battery: return [make(String(localized: "Battery"), .green) { $0.battery }]
        case .temperature: return [make(String(localized: "CPU temperature"), .red) { $0.cpuTemp }]
        case .power: return [make(String(localized: "Power draw"), .orange) { $0.power }]
        }
    }

    private var isPercent: Bool { [.cpu, .memory, .gpu, .battery].contains(metric) }

    private func label(_ value: Double) -> String {
        switch metric {
        case .cpu, .memory, .gpu, .battery: "\(Int(value.rounded())) %"
        case .network, .disk: Format.rate(value)
        case .temperature: "\(Int(value.rounded())) °C"
        case .power: String(format: "%.0f W", value)
        }
    }

    // MARK: Graphique

    @ViewBuilder private var chart: some View {
        let series = self.series
        let allPoints = series.flatMap(\.points)
        if allPoints.isEmpty {
            EmptyHint(text: "No data for “\(metric.title)” in this period (sensor unavailable?).", systemImage: "questionmark.circle")
        } else {
            Chart {
                ForEach(series) { s in
                    ForEach(s.points) { p in
                        if series.count == 1 {
                            AreaMark(x: .value("Time", p.date), y: .value(s.name, p.value))
                                .foregroundStyle(s.color.opacity(0.18))
                                .interpolationMethod(.monotone)
                        }
                        LineMark(x: .value("Time", p.date), y: .value(s.name, p.value), series: .value("Series", s.name))
                            .foregroundStyle(s.color)
                            .interpolationMethod(.monotone)
                    }
                }
            }
            .chartYScale(domain: yDomain(allPoints))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(label(v)).font(.caption2) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: xFormat, centered: false).font(.caption2)
                }
            }
            .frame(height: 220)
            .padding(.trailing, 16)          // évite que la dernière étiquette de l'axe X soit coupée

            if series.count > 1 {
                HStack(spacing: 14) {
                    ForEach(series) { s in
                        Label(s.name, systemImage: "circle.fill")
                            .font(.caption).foregroundStyle(s.color)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
    }

    private func yDomain(_ points: [Point]) -> ClosedRange<Double> {
        if isPercent { return 0...100 }
        let high = points.map(\.value).max() ?? 1
        return 0...max(high * 1.15, metric == .network || metric == .disk ? 10_000 : 1)
    }

    private var xFormat: Date.FormatStyle {
        switch range {
        case .hour, .day: .dateTime.hour().minute()
        case .week, .month: .dateTime.day().month(.abbreviated)
        }
    }

    // MARK: Résumé

    @ViewBuilder private var summary: some View {
        let series = self.series
        if series.contains(where: { !$0.points.isEmpty }) {
            Card {
                ForEach(series) { s in
                    let values = s.points.map(\.value)
                    if let low = values.min(), let high = values.max(), !values.isEmpty {
                        let mean = values.reduce(0, +) / Double(values.count)
                        VStack(alignment: .leading, spacing: 2) {
                            if series.count > 1 { Text(s.name).font(.caption.weight(.semibold)).foregroundStyle(s.color) }
                            HStack {
                                stat("Min", label(low))
                                Spacer()
                                stat("Average", label(mean))
                                Spacer()
                                stat("Max", label(high))
                            }
                        }
                    }
                }
            }
        }
    }

    private func stat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium).monospacedDigit())
        }
    }
}
