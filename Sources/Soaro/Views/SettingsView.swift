import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var updater = Updater.shared
    @AppStorage(SettingsKey.notifications) private var notifications = true
    @AppStorage(SettingsKey.menuBarCPU) private var showCPU = true
    @AppStorage(SettingsKey.menuBarMemory) private var showMemory = false
    @AppStorage(SettingsKey.menuBarGPU) private var showGPU = false
    @AppStorage(SettingsKey.menuBarBattery) private var showBattery = false
    @AppStorage(SettingsKey.menuBarNetwork) private var showNetwork = false
    @AppStorage(SettingsKey.latency) private var latency = false
    @AppStorage(SettingsKey.menuBarDisk) private var showDisk = false
    @AppStorage(SettingsKey.menuBarCompact) private var compact = true
    @AppStorage(SettingsKey.publicIP) private var publicIP = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var thresholds = PressureThresholds.load()

    var body: some View {
        Form {
            Section("In the menu bar") {
                Picker("Style", selection: $compact) {
                    Text("Compact (label above)").tag(true)
                    Text("Single line of text").tag(false)
                }
                Toggle("CPU load", isOn: $showCPU)
                Toggle("GPU load", isOn: $showGPU)
                Toggle("Memory used", isOn: $showMemory)
                Toggle("Disk used", isOn: $showDisk)
                if state.hasBattery { Toggle("Battery level", isOn: $showBattery) }
                Toggle("Network speed", isOn: $showNetwork)
            }
            Section("Value colors") {
                Text("In the menu bar, a value turns orange, then red, then scarlet when it crosses these thresholds.")
                    .font(.caption).foregroundStyle(.secondary)
                ThresholdEditor(title: "Processor and GPU (load)", thresholds: $thresholds.load, ascending: true)
                ThresholdEditor(title: "Disk (space used)", thresholds: $thresholds.disk, ascending: true)
                if state.hasBattery {
                    ThresholdEditor(title: "Battery (level left, on battery power)", thresholds: $thresholds.battery, ascending: false)
                }
                Text("Memory has no threshold: its color follows the real pressure measured by macOS (orange: high pressure; red: with swap of at least half the RAM; scarlet: critical pressure).")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Reset thresholds to defaults") { thresholds = .default }
                    .disabled(thresholds == .default)
            }
            .onChange(of: thresholds) { _, new in new.save() }
            Section("Settings tips") {
                Text("Soaro reads some macOS settings to suggest tips (battery, sleep, startup, storage, updates, backup). It never changes a setting: it opens the right System Settings pane.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(state.dismissedAdviceCount == 0 ? "No dismissed tips" : "Show dismissed tips again (\(state.dismissedAdviceCount))") {
                    state.restoreDismissedAdvice()
                }
                .disabled(state.dismissedAdviceCount == 0)
            }
            Section("Behavior") {
                Toggle("Notify on critical problems", isOn: $notifications)
                Toggle("Open at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
            }
            Section("Network") {
                Toggle("Show public IP and country", isOn: $publicIP)
                    .onChange(of: publicIP) { _, enabled in
                        if enabled { state.refreshPublicIP(force: true) } else { state.forgetPublicIP() }
                    }
                Text("Off by default: asks a third-party service (ipwho.is, or ipapi.co as a backup), which then sees your public IP. At most one request every 5 minutes, only while the Network tab is open. Nothing is stored. VPN detection is entirely local.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Measure latency (ping to 1.1.1.1)", isOn: $latency)
                Text("Off by default: this option sends a small packet to a Cloudflare server every 10 seconds, only while the Network tab is open.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Data") {
                Button("Clear history") { state.clearHistory() }
                Text("Soaro sends no data: history stays in ~/Library/Application Support/Soaro.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if updater.isAvailable {
                Section("Updates") {
                    Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                    Button("Check for updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                    Text("Once a day, Soaro downloads a small public file from soaro.app to see if a new version exists. It sends no personal data.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("About") {
                Text("Soaro monitors CPU, GPU, memory, disk, network and battery. It only deletes caches, logs and rebuildable folders in your home folder, or moves items to the Trash (recoverable), always after confirmation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Opens the browser: the app itself sends nothing.
                Link(destination: SupportLink.url) {
                    Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                }
                Text("Soaro is free and open source. Supporting it is optional.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            state.showToast(String(localized: "Cannot open at login: put the app in Applications."))
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Trois seuils réglables, toujours gardés dans l'ordre (chaque réglage est borné par ses voisins).
struct ThresholdEditor: View {
    let title: LocalizedStringKey
    @Binding var thresholds: LevelThresholds
    /// `true` : la valeur est mauvaise quand elle monte ; `false` : quand elle descend (batterie).
    let ascending: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.medium))
            if ascending {
                row(String(localized: "Orange"), .orange, $thresholds.medium, 5...(thresholds.high - 5))
                row(String(localized: "Red"), .red, $thresholds.high, (thresholds.medium + 5)...(thresholds.critical - 5))
                row(String(localized: "Scarlet"), PressureLevel.scarlet, $thresholds.critical, (thresholds.high + 5)...100)
            } else {
                row(String(localized: "Orange"), .orange, $thresholds.medium, (thresholds.high + 5)...95)
                row(String(localized: "Red"), .red, $thresholds.high, (thresholds.critical + 5)...(thresholds.medium - 5))
                row(String(localized: "Scarlet"), PressureLevel.scarlet, $thresholds.critical, 5...(thresholds.high - 5))
            }
        }
        .padding(.vertical, 2)
    }

    private func row(_ name: String, _ color: Color, _ value: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range, step: 5) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                // « Orange from 60 % » / « Red below 20 % » : deux phrases entières, pour que chaque langue place les mots comme elle veut.
                if ascending {
                    Text("\(name) from \(value.wrappedValue) %").font(.callout).monospacedDigit()
                } else {
                    Text("\(name) below \(value.wrappedValue) %").font(.callout).monospacedDigit()
                }
            }
        }
    }
}

/// Where the "Buy me a coffee" button leads.
enum SupportLink {
    static let url = URL(string: "https://buymeacoffee.com/sebmafate")!
}
