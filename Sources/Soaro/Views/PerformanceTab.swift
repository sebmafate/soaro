import SwiftUI

struct PerformanceTab: View {
    @EnvironmentObject private var state: AppState
    @State private var sort: ProcessSort = .cpu

    var body: some View {
        if let s = state.snapshot {
            VStack(alignment: .leading, spacing: 12) {
                cpu(s)
                memory(s)
                if let gpu = s.gpu { gpuSection(gpu, sensors: s.sensors) }
                disk(s)
                if let sensors = s.sensors { sensorsSection(sensors, thermal: s.thermalState) }
                processes
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    // MARK: CPU

    private func cpu(_ s: SystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Processeur")
            Card {
                HStack {
                    Text(Format.percent(s.cpu.total))
                        .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                    Spacer()
                    Text("Util. \(Format.percent(s.cpu.user)) · Sys. \(Format.percent(s.cpu.system))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Sparkline(values: state.cpuHistory, color: loadColor(s.cpu.total)).frame(height: 36)
                if !s.cpu.perCore.isEmpty {
                    CoreBars(cpu: s.cpu).padding(.top, 4)
                    if s.cpu.efficiencyCores > 0 {
                        Text("\(s.cpu.efficiencyCores) cœurs économes (E) · \(s.cpu.perCore.count - s.cpu.efficiencyCores) cœurs performance (P)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Mémoire

    private func memory(_ s: SystemSnapshot) -> some View {
        let m = s.memory
        return VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Mémoire")
            Card {
                ProgressView(value: m.usedFraction) {
                    HStack {
                        Text("\(Format.bytes(m.used)) / \(Format.bytes(m.total))").font(.caption.monospacedDigit())
                        Spacer()
                        Text(Format.percent(m.usedFraction)).font(.caption.monospacedDigit())
                    }
                }
                .tint(loadColor(m.usedFraction))
                KeyValueRow("Pression", m.pressure.label, color: m.pressure == .normal ? .green : (m.pressure == .warning ? .orange : .red))
                KeyValueRow("Applications", Format.bytes(m.app))
                KeyValueRow("Système (réservée)", Format.bytes(m.wired))
                KeyValueRow("Compressée", Format.bytes(m.compressed))
                KeyValueRow("En cache (libérable)", Format.bytes(m.cached))
                KeyValueRow("Swap utilisé", Format.bytes(m.swapUsed), color: m.swapUsed >= 3_000_000_000 ? .orange : nil)
            }
        }
    }

    // MARK: GPU

    private func gpuSection(_ gpu: GPUStats, sensors: SensorStats?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Processeur graphique")
            Card {
                HStack {
                    Text(Format.percent(gpu.utilization))
                        .font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                    Spacer()
                    if let t = sensors?.gpu { Text("\(Int(t)) °C").font(.caption).foregroundStyle(.secondary) }
                }
                Sparkline(values: state.gpuHistory, color: loadColor(gpu.utilization)).frame(height: 28)
                KeyValueRow("Mémoire utilisée par le GPU", Format.bytes(gpu.memoryUsed))
            }
        }
    }

    // MARK: Disque

    private func disk(_ s: SystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Disque")
            Card {
                ProgressView(value: s.disk.usedFraction) {
                    HStack {
                        Text("\(Format.fileBytes(s.disk.used)) / \(Format.fileBytes(s.disk.total))").font(.caption.monospacedDigit())
                        Spacer()
                        Text("\(Format.fileBytes(s.disk.available)) libres").font(.caption.monospacedDigit())
                    }
                }
                .tint(loadColor(s.disk.usedFraction))
                if let io = s.diskIO {
                    KeyValueRow("Lecture", Format.rate(io.readRate))
                    KeyValueRow("Écriture", Format.rate(io.writeRate))
                }
                if let smart = state.smartStatus {
                    KeyValueRow("État SMART", smart, color: smart == "Verified" ? .green : (smart == "Indisponible" ? nil : .red))
                }
            }
        }
    }

    // MARK: Capteurs

    private func sensorsSection(_ sensors: SensorStats, thermal: ProcessInfo.ThermalState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Capteurs")
            Card {
                if let t = sensors.cpu { KeyValueRow("Température CPU", temp(t), color: tempColor(t)) }
                if let t = sensors.gpu { KeyValueRow("Température GPU", temp(t), color: tempColor(t)) }
                if let t = sensors.ssd { KeyValueRow("Température SSD", temp(t), color: tempColor(t, hot: 70)) }
                if let t = sensors.battery { KeyValueRow("Température batterie", temp(t), color: tempColor(t, hot: 40)) }
                ForEach(sensors.fans) { fan in
                    KeyValueRow(
                        sensors.fans.count > 1 ? "Ventilateur \(fan.index + 1)" : "Ventilateur",
                        fan.rpm < 1 ? "À l'arrêt" : "\(Int(fan.rpm)) tr/min"
                    )
                }
                if let w = sensors.systemPower { KeyValueRow("Consommation du Mac", String(format: "%.1f W", w)) }
                KeyValueRow("Contrainte thermique", Self.thermalLabel(thermal), color: thermal == .nominal ? .green : (thermal == .fair ? .yellow : .orange))
            }
        }
    }

    private func temp(_ celsius: Double) -> String { "\(Int(celsius.rounded())) °C" }

    private func tempColor(_ t: Double, hot: Double = 85) -> Color {
        t >= hot ? .red : (t >= hot - 15 ? .orange : .green)
    }

    static func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "Aucune"
        case .fair: "Légère"
        case .serious: "Forte"
        case .critical: "Critique"
        @unknown default: "Inconnue"
        }
    }

    // MARK: Processus

    @ViewBuilder private var processes: some View {
        HStack {
            SectionHeader(title: "Processus")
            Spacer()
            Picker("Tri", selection: $sort) {
                ForEach(ProcessSort.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
        }
        HStack {
            Spacer()
            Text("CPU").frame(width: 50, alignment: .trailing)
            Text("Mémoire").frame(width: 64, alignment: .trailing)
            Text("Disque").frame(width: 72, alignment: .trailing)
            Color.clear.frame(width: 20, height: 1)
        }
        .font(.caption2).foregroundStyle(.secondary)
        ProcessList(sort: sort, count: 8)
    }
}
