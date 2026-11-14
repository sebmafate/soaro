import AppKit
import SwiftUI

/// Sections de la fenêtre indépendante : les onglets du panneau, plus « Ce Mac » et les réglages.
enum WindowSection: Hashable, Identifiable {
    case tab(AppTab)
    case machine
    case settings

    var id: String {
        switch self {
        case .tab(let tab): tab.rawValue
        case .machine: "machine"
        case .settings: "settings"
        }
    }

    var title: String {
        switch self {
        case .tab(let tab): tab.title
        case .machine: "Ce Mac"
        case .settings: "Réglages"
        }
    }

    var systemImage: String {
        switch self {
        case .tab(let tab): tab.systemImage
        case .machine: "laptopcomputer"
        case .settings: "gearshape"
        }
    }

    var appTab: AppTab? {
        if case .tab(let tab) = self { return tab }
        return nil
    }
}

/// Fenêtre AppKit créée à la demande. (Une scène SwiftUI `Window` s'ouvrirait toute seule au lancement,
/// ce qu'on ne veut pas pour une app de barre de menus.) Elle est détruite à la fermeture pour ne rien coûter.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()
    static let pinnedKey = "windowPinned"
    private var window: NSWindow?
    private weak var state: AppState?

    /// Referme le panneau de la barre de menus (la fenêtre prend le relais ; les deux côte à côte feraient doublon).
    static weak var menuBarPanel: NSWindow?

    static func dismissMenuBarPanel() {
        // `orderOut` plutôt que `close` : on se contente de masquer, sans toucher à la durée de vie de la fenêtre (gérée par SwiftUI).
        if let panel = menuBarPanel, panel.isVisible { panel.orderOut(nil) }
    }

    func show(state: AppState, section: WindowSection = .tab(.overview)) {
        Self.dismissMenuBarPanel()
        if window == nil {
            let host = NSHostingController(rootView: MainWindowView(initialSection: section).environmentObject(state))
            host.sceneBridgingOptions = [.toolbars, .title]      // la barre d'outils SwiftUI devient celle de la fenêtre
            let window = NSWindow(contentViewController: host)
            window.title = "Accalmie"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            // Fenêtre translucide : c'est le fond flouté (WindowGlassBackground) qui se voit, pas un aplat opaque.
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.setContentSize(NSSize(width: 860, height: 680))
            window.minSize = NSSize(width: 700, height: 520)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("AccalmieMainWindow")
            if window.frame.origin == .zero { window.center() }
            self.window = window
            self.state = state
            applyPinned(UserDefaults.standard.bool(forKey: Self.pinnedKey))
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Mode trace (`ACCALMIE_CAPTURE=<fichier.png>`) : photographie la vraie fenêtre, verre compris.
    /// Une app peut capturer ses propres fenêtres sans autorisation d'enregistrement d'écran.
    func captureForDebugging(to path: String) {
        guard let window else { return }
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        // .null = cadre de la fenêtre ; 8 = optionIncludingWindow ; 1 = boundsIgnoreFraming
        if let offset = ProcessInfo.processInfo.environment["ACCALMIE_SCROLL"].flatMap(Double.init) {
            func scroll(_ view: NSView) {
                if let sv = view as? NSScrollView, let doc = sv.documentView { doc.scroll(NSPoint(x: 0, y: offset)) }
                view.subviews.forEach(scroll)
            }
            if let content = window.contentView { scroll(content) }
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        }
        guard let image = create(.null, 8, UInt32(window.windowNumber), 1)?.takeRetainedValue() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// Épinglée : la fenêtre flotte au-dessus des autres apps, y compris quand Accalmie n'est pas active.
    func applyPinned(_ pinned: Bool) {
        window?.level = pinned ? .floating : .normal
        window?.hidesOnDeactivate = false
    }

    func windowWillClose(_ notification: Notification) {
        state?.isWindowVisible = false
        state?.windowTab = nil
        window?.contentViewController = nil      // libère toute la hiérarchie SwiftUI
        window = nil
    }
}

struct MainWindowView: View {
    @EnvironmentObject private var state: AppState
    @State private var selection: WindowSection?
    @AppStorage(MainWindowController.pinnedKey) private var pinned = false

    init(initialSection: WindowSection) {
        _selection = State(initialValue: initialSection)
    }

    private var sections: [WindowSection] {
        AppTab.allCases.filter { $0 != .battery || state.hasBattery }.map(WindowSection.tab) + [.machine]
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(sections) { section in
                        Label(section.title, systemImage: section.systemImage).tag(section)
                    }
                }
                Section {
                    Label(WindowSection.settings.title, systemImage: WindowSection.settings.systemImage).tag(WindowSection.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .safeAreaInset(edge: .bottom) { statusFooter }
            .scrollContentBackground(.hidden)
        } detail: {
            clearContainer(detail)
                .scrollContentBackground(.hidden)
                .navigationTitle(selection?.title ?? "Accalmie")
                .overlay(alignment: .top) { TitleBarBlur() }
                .overlay(alignment: .bottom) { toast }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Toggle(isOn: $pinned) {
                            Label("Toujours au premier plan", systemImage: pinned ? "pin.fill" : "pin")
                        }
                        .toggleStyle(.button)
                        .help(pinned ? "Ne plus garder la fenêtre au premier plan" : "Garder la fenêtre au premier plan")
                    }
                }
        }
        .environment(\.glassSurface, true)
        .background(WindowGlassBackground().ignoresSafeArea())
        .onChange(of: pinned, initial: true) { _, new in MainWindowController.shared.applyPinned(new) }
        .background(WindowVisibilityReader { visible in
            state.isWindowVisible = visible
            if visible { state.windowTab = selection?.appTab }
        })
        .onChange(of: selection) { _, new in state.windowTab = new?.appTab }
        .onChange(of: state.requestedCleanupRoute) { _, requested in
            if requested != nil { selection = .tab(.cleanup) }
        }
        .onAppear { state.windowTab = selection?.appTab }
        .animation(.easeInOut(duration: 0.2), value: state.toast)
    }

    /// Retire le fond opaque que SwiftUI met derrière la colonne de détail, pour laisser voir le verre.
    @ViewBuilder private func clearContainer<V: View>(_ view: V) -> some View {
        if #available(macOS 15.0, *) {
            view.containerBackground(.clear, for: .window)
        } else {
            view
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection ?? .tab(.overview) {
        case .tab(.overview): page { OverviewTab() }
        case .tab(.performance): page { PerformanceTab() }
        case .tab(.battery): page { BatteryTab() }
        case .tab(.network): page { NetworkTab() }
        case .tab(.history): page { HistoryTab() }
        case .tab(.cleanup): CleanupTab().frame(maxWidth: 640).frame(maxWidth: .infinity)
        case .machine: page { MachineView() }
        case .settings: SettingsView().frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
    }

    /// Les pages sont pensées pour une colonne : on la borne et on la centre plutôt que de l'étirer.
    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
        }
    }

    private var statusFooter: some View {
        HStack(spacing: 6) {
            Circle().fill(state.worstSeverity?.color ?? .green).frame(width: 8, height: 8)
            Text(statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var statusText: String {
        switch state.worstSeverity {
        case .critical: "Action recommandée"
        case .warning: "\(state.recommendations.count) point(s) d'attention"
        case .info: "\(state.recommendations.count) suggestion(s)"
        case nil: "Tout est en ordre"
        }
    }

    @ViewBuilder private var toast: some View {
        if let toast = state.toast {
            Text(toast)
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .cardBackground()
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Ce Mac

struct MachineView: View {
    @EnvironmentObject private var state: AppState
    @State private var info: MachineInfo?

    var body: some View {
        VStack(spacing: 16) {
            if let info {
                header(info)
                hardware(info)
                displays(info)
                identity(info)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .task {
            guard info == nil else { return }
            var loaded = await Task.detached(priority: .userInitiated) { MachineInfo.load() }.value
            loaded.displays = MachineInfo.currentDisplays()
            info = loaded
        }
    }

    private func header(_ info: MachineInfo) -> some View {
        VStack(spacing: 6) {
            // macOS fournit l'image du modèle exact de ce Mac ; pictogramme générique en secours.
            if let image = NSImage(named: NSImage.computerName) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .accessibilityLabel(info.title.isEmpty ? "Ce Mac" : info.title)
            } else {
                Image(systemName: info.modelName?.contains("Book") == true ? "laptopcomputer" : "desktopcomputer")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.secondary)
            }
            // Comme « À propos de ce Mac » : le nom donné à la machine en titre, le modèle en dessous.
            Text(info.computerName ?? (info.title.isEmpty ? "Mac" : info.title)).font(.title2.weight(.semibold))
                .textSelection(.enabled)
            if info.computerName != nil, !info.title.isEmpty {
                Text(info.title).font(.callout).foregroundStyle(.secondary)
            }
            Text(info.osVersion).font(.callout).foregroundStyle(.secondary)
            if let pending = state.pendingMacOSUpdate {
                Button {
                    state.perform(Advice.Action.openSettings(SettingsPane.softwareUpdate))
                } label: {
                    Label("Mise à jour disponible : macOS \(pending)", systemImage: "arrow.down.circle.fill")
                }
                .controlSize(.small)
                .help("Ouvrir Réglages Système › Mise à jour de logiciels")
                .padding(.top, 2)
            }
        }
        .padding(.top, 8)
    }

    private func hardware(_ info: MachineInfo) -> some View {
        Card {
            row("Processeur", [
                info.chip,
                "\(info.totalCores) cœurs",
                info.efficiencyCores > 0 ? "\(info.performanceCores) performance · \(info.efficiencyCores) économes" : nil,
            ])
            Divider()
            row("Mémoire", [Format.bytes(info.memory)])
            if let gpu = info.gpuCores {
                Divider()
                row("Graphiques", [[info.chip, "(\(gpu) cœurs)"].compactMap { $0 }.joined(separator: " ")])
            }
            if let disk = state.snapshot?.disk {
                Divider()
                row("Disque", ["\(Format.fileBytes(disk.total))", "\(Format.fileBytes(disk.available)) libres"])
            }
        }
    }

    @ViewBuilder private func displays(_ info: MachineInfo) -> some View {
        if !info.displays.isEmpty {
            Card {
                ForEach(Array(info.displays.enumerated()), id: \.offset) { index, display in
                    if index > 0 { Divider() }
                    row(index == 0 ? "Écrans" : "", [display.name, "\(display.pixels) · \(display.refreshRate) Hz"])
                }
            }
        }
    }

    private func identity(_ info: MachineInfo) -> some View {
        Card {
            if let name = info.computerName { row("Nom de l'ordinateur", [name]) }
            if let host = info.localHostName {
                Divider()
                row("Nom sur le réseau", ["\(host).local"])
            }
            if let id = info.modelIdentifier {
                if info.computerName != nil || info.localHostName != nil { Divider() }
                row("Identifiant du modèle", [id])
            }
            if let serial = info.serialNumber {
                Divider()
                row("Numéro de série", [serial])
            }
            if let uptime = state.snapshot?.uptime {
                Divider()
                row("Allumé depuis", [Format.uptime(uptime)])
            }
        }
    }

    private func row(_ label: String, _ values: [String?]) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.callout.weight(.medium))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(values.compactMap { $0 }, id: \.self) { value in
                    Text(value).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Bandeau flouté sous la barre de titre : le contenu qui défile passe dessous sans gêner la lecture du titre.
/// (Un `NSVisualEffectView` « dans la fenêtre » : les matériaux SwiftUI flouteraient le bureau, pas le contenu.)
struct TitleBarBlur: View {
    var body: some View {
        GeometryReader { geometry in
            BlurStrip()
                .frame(height: geometry.safeAreaInsets.top)
                .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 0.5) }
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct BlurStrip: NSViewRepresentable {
        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.material = .headerView
            view.blendingMode = .withinWindow
            view.state = .active
            return view
        }

        func updateNSView(_ view: NSVisualEffectView, context: Context) {}
    }
}
