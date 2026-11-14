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
            EmptyHint(text: "Aucune batterie détectée sur ce Mac.", systemImage: "battery.0percent")
        }
    }

    // MARK: Jauge

    private func gauge(_ b: BatteryStats) -> some View {
        let fraction = b.percent / 100
        let color: Color = b.isPluggedIn ? .green : levelColor(fraction)
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
                    Image(systemName: b.isCharging ? "bolt.fill" : (b.isPluggedIn ? "powerplug.fill" : "battery.50percent"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 112, height: 112)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Niveau de batterie")
            .accessibilityValue(Format.percent(fraction))

            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle(b)).font(.headline)
                Text(statusDetail(b)).font(.callout).foregroundStyle(.secondary)
                if let w = b.adapterWatts {
                    Label("Chargeur \(w) W", systemImage: "powerplug").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func statusTitle(_ b: BatteryStats) -> String {
        if b.isCharging { return "En charge" }
        if b.isPluggedIn { return b.isFullyCharged ? "Chargée" : "Sur secteur" }
        return "Sur batterie"
    }

    private func statusDetail(_ b: BatteryStats) -> String {
        if b.isCharging { return b.minutesRemaining.map { "Pleine dans \(Format.minutes($0))" } ?? "Estimation en cours…" }
        if b.isPluggedIn {
            if b.isFullyCharged { return "Branchée, charge terminée" }
            if let limit = state.systemFacts.chargeLimit, limit < 100 { return "Branchée, charge limitée à \(limit) % par macOS" }
            return "Branchée, charge en pause"
        }
        return b.minutesRemaining.map { "\(Format.minutes($0)) d'autonomie restante" } ?? "Autonomie en cours d'estimation…"
    }

    // MARK: Détails

    private func details(_ b: BatteryStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Détails")
            Card {
                if let p = b.batteryPower, abs(p) >= 0.1 {
                    KeyValueRow(p > 0 ? "Puissance de charge" : "Puissance de décharge", String(format: "%.1f W", abs(p)))
                }
                if let s = b.systemPower { KeyValueRow("Consommation du Mac", String(format: "%.1f W", s)) }
                if let t = b.temperature ?? state.snapshot?.sensors?.battery {
                    KeyValueRow("Température", "\(Int(t.rounded())) °C", color: t >= 42 ? .orange : .green)
                }
                if let max = b.maxCapacity, let design = b.designCapacity {
                    KeyValueRow("Capacité actuelle", "\(max) / \(design) mAh")
                }
            }
        }
    }

    // MARK: Santé

    private func healthSection(_ b: BatteryStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Santé de la batterie")
            Card {
                if let h = b.health {
                    ProgressView(value: h) {
                        HStack {
                            Text("Capacité maximale").font(.caption)
                            Spacer()
                            Text(Format.percent(h)).font(.caption.weight(.semibold).monospacedDigit())
                        }
                    }
                    .tint(h >= 0.8 ? .green : (h >= 0.7 ? .orange : .red))
                    Text(healthAdvice(h)).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                KeyValueRow("Cycles de charge", "\(b.cycleCount)")
            }
        }
    }

    private func healthAdvice(_ h: Double) -> String {
        switch h {
        case 0.9...: "Excellente : la batterie conserve presque toute sa capacité d'origine."
        case 0.8..<0.9: "Bonne : usure normale pour une batterie utilisée régulièrement."
        case 0.7..<0.8: "Usée : l'autonomie est sensiblement réduite. Un remplacement sera bientôt à envisager."
        default: "Très usée : un remplacement est recommandé."
        }
    }

    // MARK: Énergie par application

    @ViewBuilder private var energySection: some View {
        SectionHeader(title: "Impact énergétique par application")
        if state.energyEntries.isEmpty {
            EmptyHint(text: "Mesure en cours… (environ 2 secondes)", systemImage: "hourglass")
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
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
            Text("Même échelle que la colonne « Impact énergétique » du Moniteur d'activité : plus la valeur est haute, plus l'app vide la batterie.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
