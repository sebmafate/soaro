import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
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
            Section("Dans la barre de menus") {
                Picker("Style", selection: $compact) {
                    Text("Compact (libellé au-dessus)").tag(true)
                    Text("Texte sur une ligne").tag(false)
                }
                Toggle("Charge CPU", isOn: $showCPU)
                Toggle("Charge GPU", isOn: $showGPU)
                Toggle("Mémoire utilisée", isOn: $showMemory)
                Toggle("Disque utilisé", isOn: $showDisk)
                if state.hasBattery { Toggle("Niveau de batterie", isOn: $showBattery) }
                Toggle("Débit réseau", isOn: $showNetwork)
            }
            Section("Couleurs des valeurs") {
                Text("Dans la barre de menus, une valeur passe à l'orange, au rouge puis à l'écarlate quand elle franchit ces seuils.")
                    .font(.caption).foregroundStyle(.secondary)
                ThresholdEditor(title: "Processeur et GPU (charge)", thresholds: $thresholds.load, ascending: true)
                ThresholdEditor(title: "Disque (espace occupé)", thresholds: $thresholds.disk, ascending: true)
                if state.hasBattery {
                    ThresholdEditor(title: "Batterie (niveau restant, hors secteur)", thresholds: $thresholds.battery, ascending: false)
                }
                Text("La mémoire n'a pas de seuil : sa couleur suit la pression réelle mesurée par macOS (orange : pression élevée ; rouge : avec un swap d'au moins la moitié de la RAM ; écarlate : pression critique).")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Rétablir les seuils par défaut") { thresholds = .default }
                    .disabled(thresholds == .default)
            }
            .onChange(of: thresholds) { _, new in new.save() }
            Section("Conseils de réglage") {
                Text("Accalmie lit certains réglages de macOS pour proposer des conseils (batterie, veille, démarrage, stockage, mises à jour, sauvegarde). Elle ne modifie jamais un réglage : elle ouvre le bon panneau de Réglages Système.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(state.dismissedAdviceCount == 0 ? "Aucun conseil ignoré" : "Réafficher les \(state.dismissedAdviceCount) conseil(s) ignoré(s)") {
                    state.restoreDismissedAdvice()
                }
                .disabled(state.dismissedAdviceCount == 0)
            }
            Section("Comportement") {
                Toggle("Notifier en cas de problème critique", isOn: $notifications)
                Toggle("Ouvrir au démarrage de session", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
            }
            Section("Réseau") {
                Toggle("Afficher l'IP publique et le pays", isOn: $publicIP)
                    .onChange(of: publicIP) { _, enabled in
                        if enabled { state.refreshPublicIP(force: true) } else { state.forgetPublicIP() }
                    }
                Text("Désactivé par défaut : interroge un service tiers (ipwho.is, ou ipapi.co en secours) qui voit alors votre IP publique. Au plus une requête toutes les 5 minutes, uniquement quand l'onglet Réseau est ouvert. Rien n'est enregistré. La détection du VPN, elle, est entièrement locale.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Mesurer la latence (ping vers 1.1.1.1)", isOn: $latency)
                Text("Désactivé par défaut : cette option envoie un petit paquet à un serveur Cloudflare toutes les 10 secondes, uniquement quand l'onglet Réseau est ouvert.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Données") {
                Button("Effacer l'historique") { state.clearHistory() }
                Text("Accalmie ne transmet aucune donnée : l'historique reste dans ~/Library/Application Support/Accalmie.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("À propos") {
                Text("Accalmie surveille CPU, GPU, mémoire, disque, réseau et batterie. Il ne supprime que des caches, journaux et dossiers régénérables de votre dossier personnel, ou met à la corbeille (récupérable), toujours après confirmation.")
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
            state.showToast("Démarrage automatique impossible : placez l'app dans Applications.")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Trois seuils réglables, toujours gardés dans l'ordre (chaque réglage est borné par ses voisins).
struct ThresholdEditor: View {
    let title: String
    @Binding var thresholds: LevelThresholds
    /// `true` : la valeur est mauvaise quand elle monte ; `false` : quand elle descend (batterie).
    let ascending: Bool

    private var word: String { ascending ? "à partir de" : "en dessous de" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.medium))
            if ascending {
                row("Orange", .orange, $thresholds.medium, 5...(thresholds.high - 5))
                row("Rouge", .red, $thresholds.high, (thresholds.medium + 5)...(thresholds.critical - 5))
                row("Écarlate", PressureLevel.scarlet, $thresholds.critical, (thresholds.high + 5)...100)
            } else {
                row("Orange", .orange, $thresholds.medium, (thresholds.high + 5)...95)
                row("Rouge", .red, $thresholds.high, (thresholds.critical + 5)...(thresholds.medium - 5))
                row("Écarlate", PressureLevel.scarlet, $thresholds.critical, 5...(thresholds.high - 5))
            }
        }
        .padding(.vertical, 2)
    }

    private func row(_ name: String, _ color: Color, _ value: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range, step: 5) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text("\(name) \(word) \(value.wrappedValue) %").font(.callout).monospacedDigit()
            }
        }
        .accessibilityLabel("\(title), seuil \(name.lowercased())")
        .accessibilityValue("\(value.wrappedValue) %")
    }
}
