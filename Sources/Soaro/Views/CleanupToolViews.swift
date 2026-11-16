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

// MARK: - Gros fichiers

struct LargeFilesView: View {
    @ObservedObject var model: LargeFilesModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Minimum size").font(.caption).foregroundStyle(.secondary)
                Picker("Minimum size", selection: $model.minSizeMB) {
                    ForEach(LargeFilesModel.thresholds, id: \.self) { mb in
                        Text(Format.fileBytes(UInt64(mb) * 1_000_000)).tag(mb)
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
                .frame(width: 220)
                Spacer()
                Button(model.hasScanned ? "Scan again" : "Scan") { model.scan() }
                    .controlSize(.small).disabled(model.isScanning)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()

            if model.isScanning {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Scanning your home folder…").font(.caption).foregroundStyle(.secondary)
                    Text("macOS may ask for access to Documents, Downloads, and so on.").font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.hasScanned {
                intro
            } else if model.files.isEmpty {
                EmptyHint(text: "No file larger than \(model.minSizeMB) MB found.", systemImage: "checkmark.circle")
                    .padding(14).frame(maxHeight: .infinity, alignment: .top)
            } else {
                List {
                    ForEach(model.files) { file in
                        SelectionRow(isOn: model.selected.contains(file.id), toggle: { model.toggle(file) }) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.name).font(.callout).lineLimit(1).truncationMode(.middle)
                                Text("\(file.folder) · modified \(relativeDate(file.modified))")
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                            }
                            Spacer()
                            Text(Format.fileBytes(file.size)).font(.caption.monospacedDigit())
                            Button { revealInFinder(file.url) } label: { Image(systemName: "magnifyingglass.circle") }
                                .buttonStyle(.borderless).help("Show in Finder")
                        }
                    }
                }
                .listStyle(.plain)
                ActionBar(
                    summary: model.selected.isEmpty ? String(localized: "Files: \(model.files.count)") : String(localized: "Selected: \(model.selected.count) · \(Format.fileBytes(model.selectedSize))"),
                    button: String(localized: "Move to Trash"), enabled: !model.selected.isEmpty, action: model.trashSelected
                )
            }
        }
        .onAppear { if !model.hasScanned && !model.isScanning { model.scan() } }
    }

    private var intro: some View {
        EmptyHint(text: "Run a scan to list your largest files.", systemImage: "doc.zipper")
            .padding(14).frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Projets inactifs

struct DevProjectsView: View {
    @ObservedObject var model: DevArtifactsModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.hasScanned ? "Folders found: \(model.artifacts.count) · \(Format.fileBytes(model.totalSize))" : "Project scan")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(model.hasScanned ? "Scan again" : "Scan") { model.scan() }
                    .controlSize(.small).disabled(model.isScanning)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()

            if model.isScanning {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Looking for node_modules, .build, target, Pods…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.hasScanned && model.artifacts.isEmpty {
                EmptyHint(text: "No dependency or build folder found.", systemImage: "checkmark.circle")
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
                                    .buttonStyle(.borderless).help("Show in Finder")
                            }
                        }
                    } footer: {
                        Text("Projects inactive for more than \(DevArtifactScanner.staleAfterDays) days are pre-selected. These folders can be rebuilt with “npm install”, “swift build”, and so on; your sources are never touched.")
                            .font(.caption2)
                    }
                }
                .listStyle(.plain)
                ActionBar(
                    summary: model.selected.isEmpty ? String(localized: "Nothing selected") : String(localized: "Selected: \(model.selected.count) · \(Format.fileBytes(model.selectedSize))"),
                    button: String(localized: "Delete"), enabled: !model.selected.isEmpty, destructive: true, action: model.removeSelected
                )
            }
        }
        .onAppear { if !model.hasScanned && !model.isScanning { model.scan() } }
    }

    private func activityText(_ item: DevArtifact) -> String {
        guard let days = item.daysInactive() else { return String(localized: "activity unknown") }
        return days == 0 ? String(localized: "active today") : String(localized: "inactive for \(days) d")
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
            TextField("Search for an app", text: $model.search)
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
                                Text("Last opened: \(relativeDate(app.lastUsed))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(app.size.map { Format.fileBytes($0) } ?? "…").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
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
                    Text([app.version.map { "v\($0)" }, app.size.map { Format.fileBytes($0) }].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()

            if model.isLoadingLeftovers {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Looking for related files…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("Application") {
                        HStack {
                            Image(systemName: "app.fill").foregroundStyle(.secondary)
                            Text(app.url.path).font(.caption).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(app.size.map { Format.fileBytes($0) } ?? "").font(.caption.monospacedDigit())
                        }
                    }
                    Section("Related files (\(model.leftovers.count))") {
                        if model.leftovers.isEmpty {
                            Text("No leftovers found in ~/Library.").font(.caption).foregroundStyle(.secondary)
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
                    summary: String(localized: "\(Format.fileBytes(model.totalToFree)) freed"),
                    button: String(localized: "Uninstall"), enabled: true, destructive: true, action: model.uninstall
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
                    Text("No third-party launch agents.").font(.caption).foregroundStyle(.secondary)
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
                        .accessibilityLabel("Launch \(agent.displayName) at login")
                    }
                }
            } header: {
                Text("Launch agents")
            } footer: {
                Text("Turning an agent off stops it and keeps it from coming back, without deleting its file: just turn it on again. Apple's agents are not listed.")
                    .font(.caption2)
            }

            Section {
                if let items = model.loginItems {
                    if items.isEmpty { Text("No login items.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(items) { item in
                        HStack {
                            AppIconView(path: item.path).frame(width: 20, height: 20)
                            Text(item.name).font(.callout)
                            Spacer()
                            Button("Remove") { model.remove(item) }.controlSize(.small)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.loginItemsDenied
                             ? "Access denied. Allow Soaro to control “System Events” in System Settings › Privacy & Security › Automation."
                             : "Shows the “Open at Login” list from System Settings. macOS will ask for your permission.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button(model.loginItemsDenied ? "Try again" : "Show") { model.loadLoginItems() }.controlSize(.small)
                    }
                }
            } header: {
                Text("Open at login")
            } footer: {
                HStack {
                    Text("“Allow in the Background” apps can only be managed in System Settings.").font(.caption2)
                    Spacer()
                    Button("Open System Settings") { model.openSystemSettings() }.controlSize(.mini)
                }
            }
        }
        .listStyle(.plain)
        .onAppear { model.load() }
    }
}
