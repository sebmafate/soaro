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
            SectionHeader(title: "Processor")
            Card {
                HStack {
                    Text(Format.percent(s.cpu.total))
                        .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                    Spacer()
                    Text("User \(Format.percent(s.cpu.user)) · System \(Format.percent(s.cpu.system))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Sparkline(values: state.cpuHistory, color: loadColor(s.cpu.total)).frame(height: 36)
                if !s.cpu.perCore.isEmpty {
                    CoreBars(cpu: s.cpu).padding(.top, 4)
                    if s.cpu.efficiencyCores > 0 {
                        Text("Efficiency cores (E): \(s.cpu.efficiencyCores) · Performance cores (P): \(s.cpu.perCore.count - s.cpu.efficiencyCores)")
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
            SectionHeader(title: "Memory")
            Card {
                ProgressView(value: m.usedFraction) {
                    HStack {
                        Text("\(Format.bytes(m.used)) / \(Format.bytes(m.total))").font(.caption.monospacedDigit())
                        Spacer()
                        Text(Format.percent(m.usedFraction)).font(.caption.monospacedDigit())
                    }
                }
                .tint(loadColor(m.usedFraction))
                KeyValueRow("Pressure", m.pressure.label, color: m.pressure == .normal ? .green : (m.pressure == .warning ? .orange : .red))
                KeyValueRow("Apps", Format.bytes(m.app))
                KeyValueRow("System (wired)", Format.bytes(m.wired))
                KeyValueRow("Compressed", Format.bytes(m.compressed))
                KeyValueRow("Cached (reclaimable)", Format.bytes(m.cached))
                KeyValueRow("Swap used", Format.bytes(m.swapUsed), color: m.swapUsed >= 3_000_000_000 ? .orange : nil)
            }
        }
    }

    // MARK: GPU

    private func gpuSection(_ gpu: GPUStats, sensors: SensorStats?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Graphics")
            Card {
                HStack {
                    Text(Format.percent(gpu.utilization))
                        .font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                    Spacer()
                    if let t = sensors?.gpu { Text("\(Int(t)) °C").font(.caption).foregroundStyle(.secondary) }
                }
                Sparkline(values: state.gpuHistory, color: loadColor(gpu.utilization)).frame(height: 28)
                KeyValueRow("GPU memory used", Format.bytes(gpu.memoryUsed))
            }
        }
    }

    // MARK: Disque

    private func disk(_ s: SystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Disk")
            Card {
                ProgressView(value: s.disk.usedFraction) {
                    HStack {
                        Text("\(Format.fileBytes(s.disk.used)) / \(Format.fileBytes(s.disk.total))").font(.caption.monospacedDigit())
                        Spacer()
                        Text("\(Format.fileBytes(s.disk.available)) free").font(.caption.monospacedDigit())
                    }
                }
                .tint(loadColor(s.disk.usedFraction))
                if let io = s.diskIO {
                    KeyValueRow("Read", Format.rate(io.readRate))
                    KeyValueRow("Write", Format.rate(io.writeRate))
                }
                if let smart = state.smartStatus {
                    KeyValueRow("SMART status", smart == "Unavailable" ? String(localized: "Unavailable") : smart, color: smart == "Verified" ? .green : (smart == String(localized: "Unavailable") ? nil : .red))
                }
            }
        }
    }

    // MARK: Capteurs

    private func sensorsSection(_ sensors: SensorStats, thermal: ProcessInfo.ThermalState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Sensors")
            Card {
                if let t = sensors.cpu { KeyValueRow("CPU temperature", temp(t), color: tempColor(t)) }
                if let t = sensors.gpu { KeyValueRow("GPU temperature", temp(t), color: tempColor(t)) }
                if let t = sensors.ssd { KeyValueRow("SSD temperature", temp(t), color: tempColor(t, hot: 70)) }
                if let t = sensors.battery { KeyValueRow("Battery temperature", temp(t), color: tempColor(t, hot: 40)) }
                ForEach(sensors.fans) { fan in
                    KeyValueRow(
                        sensors.fans.count > 1 ? "Fan \(fan.index + 1)" : "Fan",
                        fan.rpm < 1 ? String(localized: "Stopped") : "\(Int(fan.rpm)) rpm"
                    )
                }
                if let w = sensors.systemPower { KeyValueRow("Mac power draw", String(format: "%.1f W", w)) }
                KeyValueRow("Thermal pressure", Self.thermalLabel(thermal), color: thermal == .nominal ? .green : (thermal == .fair ? .yellow : .orange))
            }
        }
    }

    private func temp(_ celsius: Double) -> String { "\(Int(celsius.rounded())) °C" }

    private func tempColor(_ t: Double, hot: Double = 85) -> Color {
        t >= hot ? .red : (t >= hot - 15 ? .orange : .green)
    }

    static func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: String(localized: "None")
        case .fair: String(localized: "Light")
        case .serious: String(localized: "Strong")
        case .critical: String(localized: "Critical")
        @unknown default: String(localized: "Unknown")
        }
    }

    // MARK: Processus

    @ViewBuilder private var processes: some View {
        HStack {
            SectionHeader(title: "Processes")
            Spacer()
            Picker("Sort", selection: $sort) {
                ForEach(ProcessSort.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
        }
        HStack {
            Spacer()
            Text("CPU").frame(width: 50, alignment: .trailing)
            Text("Memory").frame(width: 64, alignment: .trailing)
            Text("Disk").frame(width: 72, alignment: .trailing)
            Color.clear.frame(width: 20, height: 1)
        }
        .font(.caption2).foregroundStyle(.secondary)
        ProcessList(sort: sort, count: 8)
    }
}
