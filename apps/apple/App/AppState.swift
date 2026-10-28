import AppKit

extension Notification.Name {
    static let sidebarChanged = Notification.Name("CubbySidebarChanged")
    static let showHiddenChanged = Notification.Name("CubbyShowHiddenChanged")
    static let listColumnsChanged = Notification.Name("CubbyListColumnsChanged")
}

@MainActor
final class AppState {
    static let shared = AppState()

    let paths = CubbyPaths.standard
    let configStore: ConfigStore
    let folderViews: FolderViewStore
    let undoManager = UndoManager()
    private(set) var config: AppConfig
    private(set) var sidebar: SidebarTree
    private(set) var configError: String?
    var listColumns: [SessionState.Column] = []
    var cutURLs: [URL] = []
    var cutChangeCount = -1
    private var saveWorkItem: DispatchWorkItem?
    private var configWatchers: [PathWatcher] = []

    private init() {
        undoManager.groupsByEvent = false
        configStore = ConfigStore(paths: paths)
        folderViews = FolderViewStore(url: paths.folderViewsFile)
        switch configStore.load() {
        case .loaded(let loaded), .created(let loaded):
            config = loaded
        case .invalid(let fallback, let message):
            config = fallback
            configError = message
        }
        sidebar = SidebarTree(nodes: config.sidebar)
        folderViews.prune { FileManager.default.fileExists(atPath: $0) }
        configWatchers = [paths.configDirectory.path, paths.configFile.path].map { path in
            PathWatcher(path: path) { [weak self] in self?.reloadConfigIfChanged() }
        }
    }

    var showHiddenFiles: Bool {
        get { config.showHiddenFiles }
        set {
            config.showHiddenFiles = newValue
            saveConfig()
            NotificationCenter.default.post(name: .showHiddenChanged, object: nil)
        }
    }

    func sidebarDidChange() {
        config.sidebar = sidebar.nodes
        saveConfig()
        NotificationCenter.default.post(name: .sidebarChanged, object: nil)
    }

    func saveConfig() {
        guard configError == nil else { return }
        do {
            try configStore.save(config)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func view(for path: String) -> FolderView {
        folderViews.view(for: path, identity: FolderIdentity(path: path)) ?? config.defaultView
    }

    func setView(_ view: FolderView, for path: String) {
        folderViews.setView(view, for: path, identity: FolderIdentity(path: path), defaultView: config.defaultView)
        scheduleFolderViewSave()
    }

    func folderMoved(from oldPath: String, to newPath: String) {
        if sidebar.updateFolders(movedFrom: oldPath, to: newPath) {
            sidebarDidChange()
        }
    }

    func flush() {
        saveWorkItem?.cancel()
        try? folderViews.save()
    }

    private func scheduleFolderViewSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in try? self?.folderViews.save() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: item)
    }

    private func reloadConfigIfChanged() {
        let data = try? Data(contentsOf: paths.configFile)
        guard let data, !configStore.isOwnWrite(data) else { return }
        do {
            let loaded = try JSONDecoder().decode(AppConfig.self, from: data)
            let hiddenChanged = loaded.showHiddenFiles != config.showHiddenFiles
            config = loaded
            configError = nil
            sidebar = SidebarTree(nodes: loaded.sidebar)
            NotificationCenter.default.post(name: .sidebarChanged, object: nil)
            if hiddenChanged {
                NotificationCenter.default.post(name: .showHiddenChanged, object: nil)
            }
        } catch {
            configError = ConfigStore.describe(error)
            presentConfigError()
        }
    }

    func presentConfigError() {
        guard let message = configError else { return }
        let alert = NSAlert()
        alert.messageText = "Cubby couldn't read config.json"
        alert.informativeText = "\(message)\n\nCubby won't overwrite the file until it's fixed.\n\(paths.configFile.path)"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Reveal in Finder")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([paths.configFile])
        }
    }
}
