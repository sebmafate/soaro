import SwiftUI

enum PanelMetrics {
    static let size = CGSize(width: 430, height: 640)
}

/// Hôte du panneau. Il n'observe PAS l'état : quand la fenêtre est cachée, le contenu est
/// retiré de la hiérarchie SwiftUI pour ne pas être recalculé à chaque mesure (économie de CPU).
struct PopoverView: View {
    @EnvironmentObject private var state: AppState
    @State private var isVisible = false

    var body: some View {
        ZStack {
            if isVisible {
                PopoverContent()
            } else {
                Color.clear
            }
        }
        .frame(width: PanelMetrics.size.width, height: PanelMetrics.size.height)
        .background(WindowVisibilityReader(onChange: { visible in
            isVisible = visible
            state.isPopoverVisible = visible
        }, onWindow: { window in
            MainWindowController.menuBarPanel = window
        }))
    }
}

struct PopoverContent: View {
    @EnvironmentObject private var state: AppState
    @State private var showSettings = false

    private var tabs: [AppTab] {
        AppTab.allCases.filter { $0 != .battery || state.hasBattery }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !showSettings { tabBar }
            Divider()
            Group {
                if showSettings {
                    SettingsView()
                } else {
                    switch state.activeTab {
                    case .overview: scrolling { OverviewTab() }
                    case .performance: scrolling { PerformanceTab() }
                    case .battery: scrolling { BatteryTab() }
                    case .network: scrolling { NetworkTab() }
                    case .history: scrolling { HistoryTab() }
                    case .cleanup: CleanupTab()
                    }
                }
            }
            if let toast = state.toast {
                Text(toast)
                    .font(.caption)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: PanelMetrics.size.width, height: PanelMetrics.size.height)
        .animation(.easeInOut(duration: 0.2), value: state.toast)
    }

    private func scrolling<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content().padding(14)
        }
    }

    // MARK: Entête

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Accalmie").font(.headline)
                Text(statusLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                MainWindowController.shared.show(state: state, section: .tab(state.activeTab))
            } label: {
                Image(systemName: "macwindow")
            }
            .buttonStyle(.borderless)
            .help("Ouvrir dans une fenêtre (reste ouverte quand on clique ailleurs)")
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: showSettings ? "xmark.circle.fill" : "gearshape")
            }
            .buttonStyle(.borderless)
            .help(showSettings ? "Fermer les réglages" : "Réglages")
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quitter Accalmie")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var statusLine: String {
        guard state.snapshot != nil else { return "Mesure en cours…" }
        switch state.worstSeverity {
        case .critical: return "Action recommandée"
        case .warning: return "\(state.recommendations.count) point(s) d'attention"
        case .info: return "\(state.recommendations.count) suggestion(s)"
        case nil: return "Tout est en ordre"
        }
    }

    // MARK: Onglets

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                Button {
                    state.activeTab = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.systemImage).font(.system(size: 15))
                        Text(tab.title).font(.system(size: 10))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(state.activeTab == tab ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(state.activeTab == tab ? Color.accentColor : .secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(state.activeTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }
}
