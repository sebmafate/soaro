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
                    title: "Download", systemImage: "arrow.down.circle", value: Format.rate(net.downRate), valueSize: 17,
                    subtitle: String(localized: "Today: \(Format.fileBytes(state.todayTraffic.down))"),
                    tint: .blue, history: state.netDownHistory, autoScaleFloor: 50_000
                )
                StatCard(
                    title: "Upload", systemImage: "arrow.up.circle", value: Format.rate(net.upRate), valueSize: 17,
                    subtitle: String(localized: "Today: \(Format.fileBytes(state.todayTraffic.up))"),
                    tint: .purple, history: state.netUpHistory, autoScaleFloor: 50_000
                )
            }
            Text("Physical interfaces only (Wi-Fi, Ethernet): VPN traffic is not counted twice.")
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
                KeyValueRow("VPN", vpn.name.map { String(localized: "\($0) · all traffic") } ?? String(localized: "Active · all traffic"), color: .green)
                Text("Your Internet traffic goes through the \(vpn.interface ?? "VPN") tunnel.")
                    .font(.caption2).foregroundStyle(.secondary)
            case .partial:
                KeyValueRow("VPN", vpn.name.map { String(localized: "\($0) · partial") } ?? String(localized: "Tunnel · partial"), color: .orange)
                Text("A tunnel is active, but Internet traffic still leaves through your usual connection.")
                    .font(.caption2).foregroundStyle(.secondary)
            case .off:
                KeyValueRow("VPN", String(localized: "None detected"))
            }
        } else {
            KeyValueRow("VPN", String(localized: "Detecting…"))
        }
    }

    private var publicIPOptIn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Public IP and country").font(.caption.weight(.medium))
            Text("To show your IP as the Internet sees it, and its country, Soaro has to ask a third-party service (ipwho.is), which will see your public IP. Nothing is stored.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Show public IP and country") {
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
                    .accessibilityLabel(info.country.map { "Country: \($0)" } ?? "Unknown country")
                VStack(alignment: .leading, spacing: 1) {
                    Text(info.ip).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    Text([info.country, info.city].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                refreshButton
            }
            if let provider = info.provider { KeyValueRow("Provider", provider) }
            if state.vpn?.mode == .full {
                Text("This is the VPN exit address, not the address of your real connection.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text("Updated \(info.fetchedAt.formatted(.relative(presentation: .named)))")
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
                    Text("Looking up the public IP…").font(.caption).foregroundStyle(.secondary)
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
        .help("Refresh")
    }

    // MARK: Connexion

    private func connection(_ net: NetworkStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Connection")
            Card {
                if let name = MachineInfo.localNetworkName() { KeyValueRow("Network name", name) }
                KeyValueRow("Local IP address", net.localIP ?? "—")
                if let wifi = net.wifi {
                    KeyValueRow("Wi-Fi", qualityLabel(wifi), color: qualityColor(wifi))
                    if let ssid = wifi.ssid { KeyValueRow("Network", ssid) }
                    KeyValueRow("Signal", "\(wifi.rssi) dBm")
                    KeyValueRow("Link speed", "\(Int(wifi.txRate)) Mb/s")
                    if let channel = wifi.channel { KeyValueRow("Channel", "\(channel)") }
                } else {
                    KeyValueRow("Wi-Fi", String(localized: "Not connected"))
                }
                latencyRow(net)
            }
        }
    }

    @ViewBuilder private func latencyRow(_ net: NetworkStats) -> some View {
        if UserDefaults.standard.bool(forKey: SettingsKey.latency) {
            if let ms = state.latencyMs {
                KeyValueRow("Latency (1.1.1.1)", String(format: "%.0f ms", ms), color: ms < 50 ? .green : (ms < 150 ? .orange : .red))
            } else {
                KeyValueRow("Latency (1.1.1.1)", String(localized: "Measuring…"))
            }
        } else {
            Text("Latency measurement is off (it sends a ping to 1.1.1.1). Turn it on in Settings.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func qualityLabel(_ w: WiFiInfo) -> String {
        switch w.quality {
        case 0.75...: "Excellent"
        case 0.5..<0.75: String(localized: "Good")
        case 0.25..<0.5: String(localized: "Fair")
        default: String(localized: "Weak")
        }
    }

    private func qualityColor(_ w: WiFiInfo) -> Color {
        w.quality >= 0.5 ? .green : (w.quality >= 0.25 ? .orange : .red)
    }

    // MARK: Par application

    @ViewBuilder private var appsSection: some View {
        SectionHeader(title: "Traffic by app")
        if state.networkProcesses.isEmpty {
            EmptyHint(text: "No notable network activity, or still measuring…", systemImage: "hourglass")
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
