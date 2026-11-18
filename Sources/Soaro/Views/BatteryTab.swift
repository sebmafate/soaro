import SwiftUI

struct BatteryTab: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if let b = state.snapshot?.battery {
            VStack(alignment: .leading, spacing: 12) {
                gauge(b)
                details(b)
                healthSection(b)
                energySection
            }
        } else {
            EmptyHint(text: "No battery detected on this Mac.", systemImage: "battery.0percent")
        }
    }

    // MARK: Jauge

    private func gauge(_ b: BatteryStats) -> some View {
        let fraction = b.percent / 100
        // Même niveau que le glyphe et la valeur de la barre de menus : les seuils réglés, pas une règle fixe.
        let color = BatteryGlyphColors.barTint(for: b, thresholds: PressureThresholds.load().battery)
        return HStack(spacing: 18) {
            ZStack {
                // `inset` : le trait est centré sur le bord, sans marge il déborderait du cadre.
                Circle().inset(by: 6).stroke(.quaternary, lineWidth: 11)
                Circle().inset(by: 6)
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(Format.percent(fraction))
                        .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                    BatteryGlyph(percent: b.percent, power: b.powerState, level: .battery(b, thresholds: PressureThresholds.load().battery),
                                 body: BatteryGlyphGeometry.tabBody)
                }
            }
            .frame(width: 112, height: 112)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Battery level")
            .accessibilityValue(Format.percent(fraction))

            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle(b)).font(.headline)
                Text(statusDetail(b)).font(.callout).foregroundStyle(.supportingText)
                if let w = b.adapterWatts {
                    Label("Charger \(w) W", systemImage: "powerplug").font(.caption).foregroundStyle(.supportingText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func statusTitle(_ b: BatteryStats) -> String {
        if b.isCharging { return String(localized: "Charging") }
        if b.isPluggedIn { return b.isFullyCharged ? String(localized: "Charged") : String(localized: "On power adapter") }
        return String(localized: "On battery")
    }

    private func statusDetail(_ b: BatteryStats) -> String {
        if b.isCharging { return b.minutesRemaining.map { String(localized: "Full in \(Format.minutes($0))") } ?? String(localized: "Estimating…") }
        if b.isPluggedIn {
            if b.isFullyCharged { return String(localized: "Plugged in, charging complete") }
            if let limit = state.systemFacts.chargeLimit, limit < 100 { return String(localized: "Plugged in, charge limited to \(limit) % by macOS") }
            return String(localized: "Plugged in, charging paused")
        }
        return b.minutesRemaining.map { String(localized: "\(Format.minutes($0)) of battery left") } ?? String(localized: "Estimating battery life…")
    }

    // MARK: Détails

    private func details(_ b: BatteryStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Details")
            Card {
                if let p = b.batteryPower, abs(p) >= 0.1 {
                    KeyValueRow(p > 0 ? "Charging power" : "Discharging power", String(format: "%.1f W", abs(p)))
                }
                if let s = b.systemPower { KeyValueRow("Mac power draw", String(format: "%.1f W", s)) }
                if let t = b.temperature ?? state.snapshot?.sensors?.battery {
                    KeyValueRow("Temperature", "\(Int(t.rounded())) °C", color: t >= 42 ? .orange : .green)
                }
                if let max = b.maxCapacity, let design = b.designCapacity {
                    KeyValueRow("Current capacity", "\(max) / \(design) mAh")
                }
            }
        }
    }

    // MARK: Santé

    private func healthSection(_ b: BatteryStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Battery health")
            Card {
                if let h = b.health {
                    ProgressView(value: h) {
                        HStack {
                            Text("Maximum capacity").font(.caption)
                            Spacer()
                            Text(Format.percent(h)).font(.caption.weight(.semibold).monospacedDigit())
                        }
                    }
                    .tint(h >= 0.8 ? .green : (h >= 0.7 ? .orange : .red))
                    Text(healthAdvice(h)).font(.caption).foregroundStyle(.supportingText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                KeyValueRow("Charge cycles", "\(b.cycleCount)")
            }
        }
    }

    private func healthAdvice(_ h: Double) -> String {
        switch h {
        case 0.9...: String(localized: "Excellent: the battery keeps almost all of its original capacity.")
        case 0.8..<0.9: String(localized: "Good: normal wear for a battery that is used regularly.")
        case 0.7..<0.8: String(localized: "Worn: battery life is noticeably shorter. Consider a replacement soon.")
        default: String(localized: "Heavily worn: a replacement is recommended.")
        }
    }

    // MARK: Énergie par application

    @ViewBuilder private var energySection: some View {
        SectionHeader(title: "Energy impact by app")
        if state.energyEntries.isEmpty {
            EmptyHint(text: "Measuring… (about 2 seconds)", systemImage: "hourglass")
        } else {
            let maxImpact = max(state.energyEntries.map(\.impact).max() ?? 1, 1)
            VStack(spacing: 6) {
                ForEach(state.energyEntries) { entry in
                    HStack(spacing: 8) {
                        AppIconView(path: entry.appPath).frame(width: 18, height: 18)
                        Text(entry.name).font(.callout).lineLimit(1)
                        Spacer()
                        ProgressView(value: min(1, entry.impact / maxImpact))
                            .tint(entry.impact >= 40 ? .red : (entry.impact >= 15 ? .orange : .green))
                            .frame(width: 80)
                        Text(String(format: "%.0f", entry.impact))
                            .font(.caption.monospacedDigit()).foregroundStyle(.supportingText)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
            Text("Same scale as the “Energy Impact” column in Activity Monitor: the higher the value, the faster the app drains the battery.")
                .font(.caption2).foregroundStyle(.supportingText)
        }
    }
}
