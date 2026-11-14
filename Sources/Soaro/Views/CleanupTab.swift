import SwiftUI

enum CleanupRoute: String, Identifiable {
    case largeFiles, devProjects, uninstaller, startup
    var id: String { rawValue }

    var title: String {
        switch self {
        case .largeFiles: "Gros fichiers"
        case .devProjects: "Projets inactifs"
        case .uninstaller: "Désinstaller des apps"
        case .startup: "Éléments de démarrage"
        }
    }

    var subtitle: String {
        switch self {
        case .largeFiles: "Retrouver ce qui occupe le plus de place"
        case .devProjects: "node_modules, .build, target… de vieux projets"
        case .uninstaller: "Supprimer une app et ses restes"
        case .startup: "Ce qui se lance à l'ouverture de session"
        }
    }

    var systemImage: String {
        switch self {
        case .largeFiles: "doc.zipper"
        case .devProjects: "shippingbox"
        case .uninstaller: "trash.square"
        case .startup: "power.circle"
        }
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

    init() {
        // `notify` est rebranché sur l'état au premier affichage (voir `body`).
        _largeFiles = StateObject(wrappedValue: LargeFilesModel(notify: { _ in }))
        _devProjects = StateObject(wrappedValue: DevArtifactsModel(notify: { _ in }))
        _uninstaller = StateObject(wrappedValue: UninstallerModel(notify: { _ in }))
        _startup = StateObject(wrappedValue: StartupModel(notify: { _ in }))
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
                SectionHeader(title: "Système")
                VStack(spacing: 2) {
                    ForEach(CleanupKind.systemKinds) { kind in
                        CleanupRow(kind: kind, size: state.cleanupSizes[kind] ?? nil, busy: state.busyKinds.contains(kind)) {
                            state.perform(.cleanup(kind))
                        }
                    }
                }
                developerSection
                SectionHeader(title: "Outils")
                VStack(spacing: 6) {
                    ForEach([CleanupRoute.largeFiles, .devProjects, .uninstaller, .startup]) { item in
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
        }
    }

    private var quickClean: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nettoyage rapide").font(.headline)
                    Text(state.quickCleanReclaimable > 0
                         ? "\(Format.fileBytes(state.quickCleanReclaimable)) récupérables sans risque"
                         : "Rien d'important à nettoyer")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Nettoyer") { state.perform(.quickCleanup) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!state.busyKinds.isEmpty || state.quickCleanReclaimable == 0)
            }
            Text("Caches d'applications, journaux et DerivedData. La corbeille et les caches de dépendances restent à votre main.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var developerSection: some View {
        let visible = CleanupKind.developerKinds.filter { ((state.cleanupSizes[$0] ?? nil) ?? 0) > 0 }
        if !visible.isEmpty {
            SectionHeader(title: "Développeur")
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
        self.route = route
    }

    @ViewBuilder private func toolView(_ route: CleanupRoute) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    largeFiles.cancel(); devProjects.cancel(); uninstaller.cancel()
                    self.route = nil
                } label: {
                    Label("Nettoyage", systemImage: "chevron.left")
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
            case .uninstaller: UninstallerView(model: uninstaller)
            case .startup: StartupItemsView(model: startup)
            }
        }
    }
}
