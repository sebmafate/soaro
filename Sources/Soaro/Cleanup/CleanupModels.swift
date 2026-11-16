import AppKit
import Foundation

/// Drapeau d'annulation partagé avec une tâche détachée (qui n'hérite pas de l'annulation de son parent).
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

/// Demande de confirmation avant une action destructrice : titre, message, libellé du bouton, `critical` → accord.
/// Les modèles la reçoivent à l'initialisation pour que les tests puissent répondre « Annuler » sans afficher d'alerte.
typealias ConfirmHandler = @MainActor (_ title: String, _ message: String, _ button: String, _ critical: Bool) -> Bool

enum SystemConfirmation {
    /// Valeur par défaut : la vraie boîte de dialogue (`AppState.confirm`).
    static let ask: ConfirmHandler = { title, message, button, critical in
        AppState.confirm(title: title, message: message, button: button, critical: critical)
    }
}

// MARK: - Gros fichiers

@MainActor
final class LargeFilesModel: ObservableObject {
    @Published private(set) var files: [LargeFile]
    @Published private(set) var isScanning = false
    @Published private(set) var hasScanned = false
    @Published var selected: Set<String> = []
    @Published var minSizeMB = 100 {
        didSet { if minSizeMB != oldValue { scan() } }
    }

    static let thresholds = [50, 100, 500, 1_000]
    private var token: CancelToken?
    private var notify: (String) -> Void
    private let confirm: ConfirmHandler

    /// `files` : état initial (vide en production ; sert aux tests, qui ne scannent pas le disque).
    init(notify: @escaping (String) -> Void, confirm: @escaping ConfirmHandler = SystemConfirmation.ask, files: [LargeFile] = []) {
        self.notify = notify
        self.confirm = confirm
        self.files = files
    }
    func setNotify(_ notify: @escaping (String) -> Void) { self.notify = notify }

    var selectedFiles: [LargeFile] { files.filter { selected.contains($0.id) } }
    var selectedSize: UInt64 { selectedFiles.reduce(0) { $0 + $1.size } }

    func scan() {
        if DemoMode.isEnabled {
            files = DemoData.largeFiles.filter { $0.size >= UInt64(minSizeMB) * 1_000_000 }
            selected = []
            hasScanned = true
            return
        }
        token?.cancel()
        let token = CancelToken()
        self.token = token
        isScanning = true
        selected = []
        let minSize = UInt64(minSizeMB) * 1_000_000
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                LargeFileScanner.scan(roots: LargeFileScanner.defaultRoots(), minSize: minSize, isCancelled: { token.isCancelled })
            }.value
            guard let self, !token.isCancelled else { return }
            self.files = result
            self.isScanning = false
            self.hasScanned = true
        }
    }

    func cancel() { token?.cancel(); isScanning = false }

    func toggle(_ file: LargeFile) {
        if selected.contains(file.id) { selected.remove(file.id) } else { selected.insert(file.id) }
    }

    func trashSelected() {
        let items = selectedFiles
        guard !items.isEmpty else { return }
        guard confirm(
            String(localized: "Move the selected files to the Trash? (\(items.count))"),
            String(localized: "\(Format.fileBytes(selectedSize)) will be freed once the Trash is emptied. You can still recover them from the Trash."),
            String(localized: "Move to Trash"), false
        ) else { return }
        let result = LargeFileScanner.trash(items)
        let gone = Set(items.map(\.id))
        files.removeAll { gone.contains($0.id) }
        selected = []
        notify(result.failures == 0 ? String(localized: "\(Format.fileBytes(result.freed)) moved to the Trash") : String(localized: "Files that could not be moved: \(result.failures)"))
    }
}

// MARK: - Projets inactifs

@MainActor
final class DevArtifactsModel: ObservableObject {
    @Published private(set) var artifacts: [DevArtifact]
    @Published private(set) var isScanning = false
    @Published private(set) var hasScanned = false
    @Published var selected: Set<String> = []

    private var token: CancelToken?
    private var notify: (String) -> Void
    private let confirm: ConfirmHandler

    /// `artifacts` : état initial (vide en production ; sert aux tests, qui ne scannent pas le disque).
    init(notify: @escaping (String) -> Void, confirm: @escaping ConfirmHandler = SystemConfirmation.ask, artifacts: [DevArtifact] = []) {
        self.notify = notify
        self.confirm = confirm
        self.artifacts = artifacts
    }
    func setNotify(_ notify: @escaping (String) -> Void) { self.notify = notify }

    var selectedArtifacts: [DevArtifact] { artifacts.filter { selected.contains($0.id) } }
    var selectedSize: UInt64 { selectedArtifacts.reduce(0) { $0 + $1.size } }
    var totalSize: UInt64 { artifacts.reduce(0) { $0 + $1.size } }

    func scan() {
        if DemoMode.isEnabled {
            artifacts = DemoData.devArtifacts
            selected = Set(artifacts.filter { ($0.daysInactive() ?? 0) >= DevArtifactScanner.staleAfterDays }.map(\.id))
            hasScanned = true
            return
        }
        token?.cancel()
        let token = CancelToken()
        self.token = token
        isScanning = true
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                DevArtifactScanner.scan(isCancelled: { token.isCancelled })
            }.value
            guard let self, !token.isCancelled else { return }
            self.artifacts = result
            // Pré-sélection : les projets inactifs depuis longtemps.
            self.selected = Set(result.filter { ($0.daysInactive() ?? 0) >= DevArtifactScanner.staleAfterDays }.map(\.id))
            self.isScanning = false
            self.hasScanned = true
        }
    }

    func cancel() { token?.cancel(); isScanning = false }

    func toggle(_ artifact: DevArtifact) {
        if selected.contains(artifact.id) { selected.remove(artifact.id) } else { selected.insert(artifact.id) }
    }

    func removeSelected() {
        let items = selectedArtifacts
        guard !items.isEmpty else { return }
        guard confirm(
            String(localized: "Delete the selected rebuildable folders? (\(items.count))"),
            String(localized: "\(Format.fileBytes(selectedSize)) will be freed. Your sources are not touched: just run “npm install”, “swift build”… to rebuild them."),
            String(localized: "Delete"), false
        ) else { return }

        Task { [weak self] in
            let removed = await Task.detached(priority: .userInitiated) {
                items.filter { DevArtifactScanner.remove($0) }
            }.value
            guard let self else { return }
            let gone = Set(removed.map(\.id))
            self.artifacts.removeAll { gone.contains($0.id) }
            self.selected.subtract(gone)
            let freed = removed.reduce(UInt64(0)) { $0 + $1.size }
            self.notify(removed.count == items.count
                ? String(localized: "\(Format.fileBytes(freed)) freed")
                : String(localized: "Folders that could not be deleted: \(items.count - removed.count)"))
        }
    }
}

// MARK: - Désinstalleur

@MainActor
final class UninstallerModel: ObservableObject {
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isLoading = false
    @Published var search = ""
    @Published private(set) var current: InstalledApp?
    @Published private(set) var leftovers: [Leftover] = []
    @Published private(set) var isLoadingLeftovers = false
    @Published var excluded: Set<String> = []

    private var token: CancelToken?
    private var notify: (String) -> Void

    init(notify: @escaping (String) -> Void) { self.notify = notify }
    func setNotify(_ notify: @escaping (String) -> Void) { self.notify = notify }

    var filtered: [InstalledApp] {
        let q = search.trimmingCharacters(in: .whitespaces)
        let base = apps.filter(AppUninstaller.canUninstall)
        guard !q.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var selectedLeftovers: [Leftover] { leftovers.filter { !excluded.contains($0.id) } }
    var totalToFree: UInt64 {
        (current?.size ?? 0) + selectedLeftovers.reduce(0) { $0 + $1.size }
    }

    func load() {
        if DemoMode.isEnabled { apps = DemoData.apps; return }
        guard !isLoading else { return }
        token?.cancel()
        let token = CancelToken()
        self.token = token
        isLoading = true
        Task { [weak self] in
            let list = await Task.detached(priority: .utility) { AppUninstaller.installedApps() }.value
            guard let self, !token.isCancelled else { return }
            self.apps = list
            self.isLoading = false

            // Les tailles arrivent au fil de l'eau (certaines apps pèsent plusieurs Go).
            for app in list {
                if token.isCancelled { return }
                let size = await Task.detached(priority: .utility) { CleanupService.allocatedSize(of: app.url) }.value
                if let index = self.apps.firstIndex(where: { $0.id == app.id }) { self.apps[index].size = size }
            }
        }
    }

    func cancel() { token?.cancel() }

    func select(_ app: InstalledApp) {
        current = app
        leftovers = []
        excluded = []
        if DemoMode.isEnabled {
            leftovers = DemoData.leftovers(for: app)
            return
        }
        isLoadingLeftovers = true
        Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) { AppUninstaller.leftovers(for: app) }.value
            guard let self, self.current?.id == app.id else { return }
            self.leftovers = found
            self.isLoadingLeftovers = false
        }
    }

    func deselect() { current = nil; leftovers = [] }

    func uninstall() {
        guard let app = current else { return }
        if AppUninstaller.isRunning(app) {
            notify(String(localized: "“\(app.name)” is open: quit it first."))
            return
        }
        let items = selectedLeftovers
        guard AppState.confirm(
            title: String(localized: "Uninstall “\(app.name)”?"),
            message: String(localized: "The app and its related items (\(items.count)) will be moved to the Trash (\(Format.fileBytes(totalToFree))). You can recover them until the Trash is emptied."),
            button: String(localized: "Uninstall"), critical: true
        ) else { return }

        let result = AppUninstaller.uninstall(app, leftovers: items)
        if result.failures.isEmpty {
            apps.removeAll { $0.id == app.id }
            deselect()
            notify(String(localized: "“\(app.name)” uninstalled · \(Format.fileBytes(result.freed)) freed"))
        } else {
            notify(String(localized: "Partly failed: \(result.failures.prefix(2).joined(separator: ", "))"))
        }
    }
}

// MARK: - Éléments de démarrage

@MainActor
final class StartupModel: ObservableObject {
    @Published private(set) var agents: [LaunchAgentItem] = []
    @Published private(set) var loginItems: [LoginItem]?
    @Published private(set) var loginItemsDenied = false
    @Published private(set) var isLoading = false
    private var notify: (String) -> Void

    init(notify: @escaping (String) -> Void) { self.notify = notify }
    func setNotify(_ notify: @escaping (String) -> Void) { self.notify = notify }

    func load() {
        if DemoMode.isEnabled { agents = DemoData.agents; return }
        isLoading = true
        Task { [weak self] in
            let list = await Task.detached(priority: .utility) { () -> [LaunchAgentItem] in
                StartupItemsService.launchAgents(disabled: StartupItemsService.disabledLabels())
            }.value
            self?.agents = list
            self?.isLoading = false
        }
    }

    /// Déclenche la demande d'autorisation d'automatisation (System Events) : à lancer sur action de l'utilisateur.
    func loadLoginItems() {
        if DemoMode.isEnabled { loginItems = DemoData.loginItems; return }
        Task { [weak self] in
            let items = await Task.detached(priority: .userInitiated) { StartupItemsService.loginItems() }.value
            self?.loginItems = items
            self?.loginItemsDenied = (items == nil)
        }
    }

    func setEnabled(_ agent: LaunchAgentItem, enabled: Bool) {
        Task { [weak self] in
            let ok = await Task.detached(priority: .userInitiated) { StartupItemsService.setEnabled(agent, enabled: enabled) }.value
            guard let self else { return }
            if ok {
                for index in self.agents.indices where self.agents[index].label == agent.label {
                    self.agents[index].isDisabled = !enabled
                }
            } else {
                self.notify(String(localized: "Could not change “\(agent.displayName)”"))
            }
        }
    }

    func remove(_ item: LoginItem) {
        guard AppState.confirm(
            title: String(localized: "Remove “\(item.name)” from the login items?"),
            message: String(localized: "The app will no longer open at login. It is not deleted."),
            button: String(localized: "Remove")
        ) else { return }
        Task { [weak self] in
            let ok = await Task.detached(priority: .userInitiated) { StartupItemsService.removeLoginItem(item) }.value
            guard let self else { return }
            if ok { self.loginItems?.removeAll { $0.id == item.id } } else { self.notify(String(localized: "Could not remove “\(item.name)”")) }
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
