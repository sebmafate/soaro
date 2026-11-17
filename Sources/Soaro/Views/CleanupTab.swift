import SwiftUI

enum CleanupRoute: String, Identifiable {
    case largeFiles, devProjects, simulators, uninstaller, startup
    var id: String { rawValue }

    var title: String {
        switch self {
        case .largeFiles: String(localized: "Large files")
        case .devProjects: String(localized: "Inactive projects")
        case .simulators: String(localized: "Simulators and emulators")
        case .uninstaller: String(localized: "Uninstall apps")
        case .startup: String(localized: "Startup items")
        }
    }

    var subtitle: String {
        switch self {
        case .largeFiles: String(localized: "Find what takes up the most space")
        case .devProjects: String(localized: "node_modules, .build, target… from old projects")
        case .simulators: String(localized: "iOS Simulators and Android emulators")
        case .uninstaller: String(localized: "Remove an app and its leftovers")
        case .startup: String(localized: "What starts when you log in")
        }
    }

    var systemImage: String {
        switch self {
        case .largeFiles: "doc.zipper"
        case .devProjects: "shippingbox"
        case .simulators: "ipad.and.iphone"
        case .uninstaller: "trash.square"
        case .startup: "power.circle"
        }
    }
}

extension CleanupRoute {
    /// Les outils de la liste, dans l'ordre : « Simulators and emulators » entre « Inactive projects » et « Uninstall apps »,
    /// seulement si l'outil est présent (ou en mode démo).
    static func toolRoutes(showSimulators: Bool) -> [CleanupRoute] {
        [.largeFiles, .devProjects] + (showSimulators ? [.simulators] : []) + [.uninstaller, .startup]
    }
}

struct CleanupTab: View {
    @EnvironmentObject private var state: AppState
    @State private var route: CleanupRoute?

    // Les modèles vivent ici pour conserver les résultats quand on revient à la liste.
    @StateObject private var largeFiles: LargeFilesModel
    @StateObject private var devProjects: DevArtifactsModel
    @StateObject private var uninstaller: UninstallerModel
    @StateObject private var startup: StartupModel
    @StateObject private var simulators: SimulatorsModel
    /// Résultat de la détection de l'outil des simulateurs (sur le disque, rien n'est lancé) ; `nil` tant qu'elle n'a pas eu lieu.
    @State private var simulatorDetection: SimulatorToolDetection?
    /// Le SDK Android trouvé (variables d'environnement du processus, sinon le dossier par défaut), `nil` s'il n'y en a pas.
    @State private var androidSDK: AndroidSDKLocation?

    init() {
        // `notify` est rebranché sur l'état au premier affichage (voir `body`).
        _largeFiles = StateObject(wrappedValue: LargeFilesModel(notify: { _ in }))
        _devProjects = StateObject(wrappedValue: DevArtifactsModel(notify: { _ in }))
        _uninstaller = StateObject(wrappedValue: UninstallerModel(notify: { _ in }))
        _startup = StateObject(wrappedValue: StartupModel(notify: { _ in }))
        // Seul endroit de l'application où le vrai lanceur de commandes est construit (avec `Diagnostics.scan`).
        _simulators = StateObject(wrappedValue: SimulatorsModel(runner: RealCommandRunner(), environment: ProcessInfo.processInfo.environment, confirm: SystemConfirmation.ask, notify: { _ in }))
    }

    var body: some View {
        Group {
            if let route {
                toolView(route)
            } else {
                list
            }
        }
        // Un conseil (« Voir la liste ») peut demander l'ouverture directe d'un outil.
        .onChange(of: state.requestedCleanupRoute, initial: true) { _, requested in
            guard let requested else { return }
            open(requested)
            state.requestedCleanupRoute = nil
        }
    }

    // MARK: Liste

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                quickClean
                SectionHeader(title: "System")
                VStack(spacing: 2) {
                    ForEach(CleanupKind.systemKinds) { kind in
                        CleanupRow(kind: kind, size: state.cleanupSizes[kind] ?? nil, busy: state.busyKinds.contains(kind)) {
                            state.perform(.cleanup(kind))
                        }
                    }
                }
                developerSection
                SectionHeader(title: "Tools")
                VStack(spacing: 6) {
                    ForEach(CleanupRoute.toolRoutes(showSimulators: SimulatorToolDetection.showsToolsRow(detection: simulatorDetection, androidSDK: androidSDK, demo: DemoMode.isEnabled))) { item in
                        Button { open(item) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.systemImage).font(.title3).frame(width: 26).foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title).font(.callout.weight(.medium))
                                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .cardBackground(flatOpacity: 0.4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            // La colonne est bornée DANS la zone défilante (comme `page` de la fenêtre) : la barre de défilement reste au bord de la
            // fenêtre. Sans effet dans le panneau (430 pt de large).
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        // Détection à l'apparition de la liste (jamais dans `body`, jamais dans le tick) : quelques lectures du disque, hors acteur principal.
        .task {
            // Mode démo : la rangée est toujours visible, rien n'est lu sur le disque.
            guard !DemoMode.isEnabled else { return }
            let (found, sdk) = await Task.detached(priority: .utility) { () -> (SimulatorToolDetection, AndroidSDKLocation?) in
                let home = URL(fileURLWithPath: NSHomeDirectory())
                return (SimulatorToolDetector.detect(home: home),
                        ToolLocator.androidSDK(environment: ProcessInfo.processInfo.environment, home: home))
            }.value
            simulatorDetection = found
            androidSDK = sdk
        }
    }

    private var quickClean: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick clean").font(.headline)
                    Text(state.quickCleanReclaimable > 0
                         ? "\(Format.fileBytes(state.quickCleanReclaimable)) can be freed safely"
                         : "Nothing important to clean")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clean") { state.perform(.quickCleanup) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!state.busyKinds.isEmpty || state.quickCleanReclaimable == 0)
            }
            Text("App caches, logs and DerivedData. The Trash and dependency caches are left for you to decide.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var developerSection: some View {
        let visible = CleanupKind.visibleDeveloperKinds(sizes: state.cleanupSizes)
        if !visible.isEmpty {
            SectionHeader(title: "Developer")
            VStack(spacing: 2) {
                ForEach(visible) { kind in
                    CleanupRow(kind: kind, size: state.cleanupSizes[kind] ?? nil, busy: state.busyKinds.contains(kind)) {
                        state.perform(.cleanup(kind))
                    }
                }
            }
        }
    }

    // MARK: Outils

    private func open(_ route: CleanupRoute) {
        let notify: (String) -> Void = { [weak state] message in state?.showToast(message) }
        largeFiles.setNotify(notify)
        devProjects.setNotify(notify)
        uninstaller.setNotify(notify)
        startup.setNotify(notify)
        simulators.setNotify(notify)
        self.route = route
    }

    @ViewBuilder private func toolView(_ route: CleanupRoute) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    largeFiles.cancel(); devProjects.cancel(); uninstaller.cancel(); simulators.cancel()
                    self.route = nil
                } label: {
                    Label("Cleanup", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text(route.title).font(.headline)
                Spacer()
                Color.clear.frame(width: 80, height: 1)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()
            switch route {
            case .largeFiles: LargeFilesView(model: largeFiles)
            case .devProjects: DevProjectsView(model: devProjects)
            case .simulators: SimulatorsView(model: simulators)
            case .uninstaller: UninstallerView(model: uninstaller)
            case .startup: StartupItemsView(model: startup)
            }
        }
    }
}
