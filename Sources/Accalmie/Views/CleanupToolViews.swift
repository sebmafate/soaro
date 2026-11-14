import AppKit
import SwiftUI

private func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

private func relativeDate(_ date: Date?) -> String {
    guard let date else { return "—" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}

/// Barre d'action collée en bas d'une liste : résumé + bouton principal.
private struct ActionBar: View {
    let summary: String
    let button: String
    let enabled: Bool
    var destructive = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text(summary).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(button, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(destructive ? .red : .accentColor)
                    .disabled(!enabled)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }
}

private struct SelectionRow<Content: View>: View {
    let isOn: Bool
    let toggle: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: toggle) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOn ? "Sélectionné" : "Non sélectionné")
            content
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Gros fichiers

struct LargeFilesView: View {
    @ObservedObject var model: LargeFilesModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Taille minimale").font(.caption).foregroundStyle(.secondary)
                Picker("Taille minimale", selection: $model.minSizeMB) {
                    ForEach(LargeFilesModel.thresholds, id: \.self) { mb in
                        Text(mb >= 1_000 ? "\(mb / 1_000) Go" : "\(mb) Mo").tag(mb)
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
                .frame(width: 220)
                Spacer()
                Button(model.hasScanned ? "Relancer" : "Analyser") { model.scan() }
                    .controlSize(.small).disabled(model.isScanning)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()

            if model.isScanning {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Analyse de votre dossier personnel…").font(.caption).foregroundStyle(.secondary)
                    Text("macOS peut vous demander l'accès à Documents, Téléchargements, etc.").font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.hasScanned {
                intro
            } else if model.files.isEmpty {
                EmptyHint(text: "Aucun fichier de plus de \(model.minSizeMB) Mo trouvé.", systemImage: "checkmark.circle")
                    .padding(14).frame(maxHeight: .infinity, alignment: .top)
            } else {
                List {
                    ForEach(model.files) { file in
                        SelectionRow(isOn: model.selected.contains(file.id), toggle: { model.toggle(file) }) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.name).font(.callout).lineLimit(1).truncationMode(.middle)
                                Text("\(file.folder) · modifié \(relativeDate(file.modified))")
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                            }
                            Spacer()
                            Text(Format.fileBytes(file.size)).font(.caption.monospacedDigit())
                            Button { revealInFinder(file.url) } label: { Image(systemName: "magnifyingglass.circle") }
                                .buttonStyle(.borderless).help("Afficher dans le Finder")
                        }
                    }
                }
                .listStyle(.plain)
                ActionBar(
                    summary: model.selected.isEmpty ? "\(model.files.count) fichiers" : "\(model.selected.count) sélectionné(s) · \(Format.fileBytes(model.selectedSize))",
                    button: "Mettre à la corbeille", enabled: !model.selected.isEmpty, action: model.trashSelected
                )
            }
        }
        .onAppear { if !model.hasScanned && !model.isScanning { model.scan() } }
    }

    private var intro: some View {
        EmptyHint(text: "Lancez l'analyse pour lister vos plus gros fichiers.", systemImage: "doc.zipper")
            .padding(14).frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Projets inactifs

struct DevProjectsView: View {
    @ObservedObject var model: DevArtifactsModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.hasScanned ? "\(Format.fileBytes(model.totalSize)) dans \(model.artifacts.count) dossiers" : "Analyse des projets")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(model.hasScanned ? "Relancer" : "Analyser") { model.scan() }
                    .controlSize(.small).disabled(model.isScanning)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()

            if model.isScanning {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Recherche de node_modules, .build, target, Pods…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.hasScanned && model.artifacts.isEmpty {
                EmptyHint(text: "Aucun dossier de dépendances ou de build trouvé.", systemImage: "checkmark.circle")
                    .padding(14).frame(maxHeight: .infinity, alignment: .top)
            } else {
                List {
                    Section {
                        ForEach(model.artifacts) { item in
                            SelectionRow(isOn: model.selected.contains(item.id), toggle: { model.toggle(item) }) {
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 6) {
                                        Text(item.projectName).font(.callout).lineLimit(1)
                                        Text(item.kind.label)
                                            .font(.system(size: 9, weight: .semibold))
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(.quaternary, in: Capsule())
                                    }
                                    Text("\(item.projectPath) · \(activityText(item))")
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                                }
                                Spacer()
                                Text(Format.fileBytes(item.size)).font(.caption.monospacedDigit())
                                Button { revealInFinder(item.url) } label: { Image(systemName: "magnifyingglass.circle") }
                                    .buttonStyle(.borderless).help("Afficher dans le Finder")
                            }
                        }
                    } footer: {
                        Text("Les projets inactifs depuis plus de \(DevArtifactScanner.staleAfterDays) jours sont pré-sélectionnés. Ces dossiers se recréent avec « npm install », « swift build », etc. ; vos sources ne sont jamais touchées.")
                            .font(.caption2)
                    }
                }
                .listStyle(.plain)
                ActionBar(
                    summary: model.selected.isEmpty ? "Rien de sélectionné" : "\(model.selected.count) sélectionné(s) · \(Format.fileBytes(model.selectedSize))",
                    button: "Supprimer", enabled: !model.selected.isEmpty, destructive: true, action: model.removeSelected
                )
            }
        }
        .onAppear { if !model.hasScanned && !model.isScanning { model.scan() } }
    }

    private func activityText(_ item: DevArtifact) -> String {
        guard let days = item.daysInactive() else { return "activité inconnue" }
        return days == 0 ? "actif aujourd'hui" : "inactif depuis \(days) j"
    }
}

// MARK: - Désinstalleur

struct UninstallerView: View {
    @ObservedObject var model: UninstallerModel

    var body: some View {
        Group {
            if let app = model.current {
                detail(app)
            } else {
                list
            }
        }
        .onAppear { if model.apps.isEmpty { model.load() } }
    }

    private var list: some View {
        VStack(spacing: 0) {
            TextField("Rechercher une application", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()
            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.filtered) { app in
                    Button { model.select(app) } label: {
                        HStack(spacing: 8) {
                            AppIconView(path: app.url.path).frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name).font(.callout).lineLimit(1)
                                Text("Dernière ouverture : \(relativeDate(app.lastUsed))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(app.size.map(Format.fileBytes) ?? "…").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
    }

    private func detail(_ app: InstalledApp) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { model.deselect() } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                AppIconView(path: app.url.path).frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(.headline)
                    Text([app.version.map { "v\($0)" }, app.size.map(Format.fileBytes)].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()

            if model.isLoadingLeftovers {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Recherche des fichiers associés…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("Application") {
                        HStack {
                            Image(systemName: "app.fill").foregroundStyle(.secondary)
                            Text(app.url.path).font(.caption).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(app.size.map(Format.fileBytes) ?? "").font(.caption.monospacedDigit())
                        }
                    }
                    Section("Fichiers associés (\(model.leftovers.count))") {
                        if model.leftovers.isEmpty {
                            Text("Aucun reste trouvé dans ~/Library.").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(model.leftovers) { item in
                            SelectionRow(isOn: !model.excluded.contains(item.id), toggle: {
                                if model.excluded.contains(item.id) { model.excluded.remove(item.id) } else { model.excluded.insert(item.id) }
                            }) {
                                Text(item.displayPath).font(.caption).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(Format.fileBytes(item.size)).font(.caption.monospacedDigit())
                            }
                        }
                    }
                }
                .listStyle(.plain)
                ActionBar(
                    summary: "\(Format.fileBytes(model.totalToFree)) libérés",
                    button: "Désinstaller", enabled: true, destructive: true, action: model.uninstall
                )
            }
        }
    }
}

// MARK: - Éléments de démarrage

struct StartupItemsView: View {
    @ObservedObject var model: StartupModel

    var body: some View {
        List {
            Section {
                if model.isLoading && model.agents.isEmpty {
                    ProgressView()
                } else if model.agents.isEmpty {
                    Text("Aucun agent de lancement tiers.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.agents) { agent in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(agent.displayName).font(.callout).lineLimit(1)
                            Text(agent.program.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? agent.label)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { !agent.isDisabled },
                            set: { model.setEnabled(agent, enabled: $0) }
                        ))
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                        .accessibilityLabel("Lancer \(agent.displayName) à l'ouverture de session")
                    }
                }
            } header: {
                Text("Agents de lancement")
            } footer: {
                Text("Désactiver arrête l'agent et l'empêche de revenir, sans supprimer son fichier : il suffit de le réactiver. Les agents d'Apple ne sont pas listés.")
                    .font(.caption2)
            }

            Section {
                if let items = model.loginItems {
                    if items.isEmpty { Text("Aucun élément d'ouverture.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(items) { item in
                        HStack {
                            AppIconView(path: item.path).frame(width: 20, height: 20)
                            Text(item.name).font(.callout)
                            Spacer()
                            Button("Retirer") { model.remove(item) }.controlSize(.small)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.loginItemsDenied
                             ? "Accès refusé. Autorisez Accalmie à contrôler « System Events » dans Réglages Système › Confidentialité › Automatisation."
                             : "Affiche la liste « Ouvrir à la connexion » de Réglages Système. macOS demandera votre autorisation.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button(model.loginItemsDenied ? "Réessayer" : "Afficher") { model.loadLoginItems() }.controlSize(.small)
                    }
                }
            } header: {
                Text("Ouvrir à la connexion")
            } footer: {
                HStack {
                    Text("Les « apps en arrière-plan » ne peuvent se gérer que dans Réglages Système.").font(.caption2)
                    Spacer()
                    Button("Ouvrir les réglages") { model.openSystemSettings() }.controlSize(.mini)
                }
            }
        }
        .listStyle(.plain)
        .onAppear { model.load() }
    }
}
