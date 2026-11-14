import SwiftUI

struct NetworkTab: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(SettingsKey.publicIP) private var publicIPEnabled = false

    var body: some View {
        if let net = state.snapshot?.network {
            VStack(alignment: .leading, spacing: 12) {
                throughput(net)
                internet
                connection(net)
                appsSection
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    // MARK: Débits

    private func throughput(_ net: NetworkStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatCard(
                    title: "Réception", systemImage: "arrow.down.circle", value: Format.rate(net.downRate), valueSize: 17,
                    subtitle: "Aujourd'hui : \(Format.fileBytes(state.todayTraffic.down))",
                    tint: .blue, history: state.netDownHistory, autoScaleFloor: 50_000
                )
                StatCard(
                    title: "Envoi", systemImage: "arrow.up.circle", value: Format.rate(net.upRate), valueSize: 17,
                    subtitle: "Aujourd'hui : \(Format.fileBytes(state.todayTraffic.up))",
                    tint: .purple, history: state.netUpHistory, autoScaleFloor: 50_000
                )
            }
            Text("Interfaces physiques uniquement (Wi-Fi, Ethernet) : le trafic des VPN n'est pas compté deux fois.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Internet (VPN, IP publique, pays)

    private var internet: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Internet")
            Card {
                vpnRow
                Divider().padding(.vertical, 2)
                if publicIPEnabled { publicIPContent } else { publicIPOptIn }
            }
        }
    }

    @ViewBuilder private var vpnRow: some View {
        if let vpn = state.vpn {
            switch vpn.mode {
            case .full:
                KeyValueRow("VPN", "\(vpn.name ?? "Actif") · tout le trafic", color: .green)
                Text("Votre trafic Internet passe par le tunnel \(vpn.interface ?? "VPN").")
                    .font(.caption2).foregroundStyle(.secondary)
            case .partial:
                KeyValueRow("VPN", "\(vpn.name ?? "Tunnel") · partiel", color: .orange)
                Text("Un tunnel est actif, mais Internet sort toujours par votre connexion habituelle.")
                    .font(.caption2).foregroundStyle(.secondary)
            case .off:
                KeyValueRow("VPN", "Aucun détecté")
            }
        } else {
            KeyValueRow("VPN", "Détection…")
        }
    }

    private var publicIPOptIn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("IP publique et pays").font(.caption.weight(.medium))
            Text("Pour afficher votre IP vue d'Internet et son pays, Accalmie doit interroger un service tiers (ipwho.is) qui verra votre IP publique. Rien n'est enregistré.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Afficher l'IP publique et le pays") {
                publicIPEnabled = true
                state.refreshPublicIP(force: true)
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder private var publicIPContent: some View {
        if let info = state.publicIP {
            HStack(spacing: 10) {
                Text(info.flag ?? "🌐").font(.system(size: 32))
                    .accessibilityLabel(info.country.map { "Pays : \($0)" } ?? "Pays inconnu")
                VStack(alignment: .leading, spacing: 1) {
                    Text(info.ip).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    Text([info.country, info.city].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                refreshButton
            }
            if let provider = info.provider { KeyValueRow("Fournisseur", provider) }
            if state.vpn?.mode == .full {
                Text("C'est l'adresse de sortie du VPN, pas celle de votre connexion réelle.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text("Mis à jour \(info.fetchedAt.formatted(.relative(presentation: .named)))")
                .font(.caption2).foregroundStyle(.tertiary)
        } else {
            switch state.publicIPState {
            case .failed(let message):
                HStack {
                    Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    Spacer()
                    refreshButton
                }
            default:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Recherche de l'IP publique…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var refreshButton: some View {
        Button { state.refreshPublicIP(force: true) } label: {
            if state.publicIPState == .loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .buttonStyle(.borderless)
        .disabled(state.publicIPState == .loading)
        .help("Actualiser")
    }

    // MARK: Connexion

    private func connection(_ net: NetworkStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Connexion")
            Card {
                if let name = MachineInfo.localNetworkName() { KeyValueRow("Nom sur le réseau", name) }
                KeyValueRow("Adresse IP locale", net.localIP ?? "—")
                if let wifi = net.wifi {
                    KeyValueRow("Wi-Fi", qualityLabel(wifi), color: qualityColor(wifi))
                    if let ssid = wifi.ssid { KeyValueRow("Réseau", ssid) }
                    KeyValueRow("Signal", "\(wifi.rssi) dBm")
                    KeyValueRow("Débit négocié", "\(Int(wifi.txRate)) Mb/s")
                    if let channel = wifi.channel { KeyValueRow("Canal", "\(channel)") }
                } else {
                    KeyValueRow("Wi-Fi", "Non connecté")
                }
                latencyRow(net)
            }
        }
    }

    @ViewBuilder private func latencyRow(_ net: NetworkStats) -> some View {
        if UserDefaults.standard.bool(forKey: SettingsKey.latency) {
            if let ms = state.latencyMs {
                KeyValueRow("Latence (1.1.1.1)", String(format: "%.0f ms", ms), color: ms < 50 ? .green : (ms < 150 ? .orange : .red))
            } else {
                KeyValueRow("Latence (1.1.1.1)", "Mesure…")
            }
        } else {
            Text("La mesure de latence est désactivée (elle envoie un ping vers 1.1.1.1). Activez-la dans les réglages.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func qualityLabel(_ w: WiFiInfo) -> String {
        switch w.quality {
        case 0.75...: "Excellent"
        case 0.5..<0.75: "Bon"
        case 0.25..<0.5: "Moyen"
        default: "Faible"
        }
    }

    private func qualityColor(_ w: WiFiInfo) -> Color {
        w.quality >= 0.5 ? .green : (w.quality >= 0.25 ? .orange : .red)
    }

    // MARK: Par application

    @ViewBuilder private var appsSection: some View {
        SectionHeader(title: "Trafic par application")
        if state.networkProcesses.isEmpty {
            EmptyHint(text: "Aucune activité réseau notable, ou mesure en cours…", systemImage: "hourglass")
        } else {
            VStack(spacing: 4) {
                ForEach(state.networkProcesses) { proc in
                    HStack(spacing: 8) {
                        AppIconView(path: proc.appPath).frame(width: 18, height: 18)
                        Text(proc.name).font(.callout).lineLimit(1)
                        Spacer()
                        Text("↓ " + Format.rate(proc.down)).frame(width: 84, alignment: .trailing)
                        Text("↑ " + Format.rate(proc.up)).frame(width: 84, alignment: .trailing)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}
