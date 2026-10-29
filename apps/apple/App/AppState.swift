import AppKit

extension Notification.Name {
    static let sidebarChanged = Notification.Name("CubbySidebarChanged")
    static let showHiddenChanged = Notification.Name("CubbyShowHiddenChanged")
    static let listColumnsChanged = Notification.Name("CubbyListColumnsChanged")
    static let configChanged = Notification.Name("CubbyConfigChanged")
    static let themeChanged = Notification.Name("CubbyThemeChanged")
}

@MainActor
final class AppState {
    static let shared = AppState()

    let paths = CubbyPaths.standard
    let configStore: ConfigStore
    let folderViews: FolderViewStore
    let undoManager = UndoManager()
    private(set) var config: AppConfig
    private(set) var configError: String?
    private(set) var themes: ThemeLibrary
    var listColumns: [SessionState.Column] = []
    var cutURLs: [URL] = []
    var cutChangeCount = -1
    private var saveWorkItem: DispatchWorkItem?
    private var configWatchers: [PathWatcher] = []
    private var themeWatchers: [PathWatcher] = []

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
        try? FileManager.default.createDirectory(at: paths.themesDirectory, withIntermediateDirectories: true)
        themes = ThemeLibrary(directory: paths.themesDirectory)
        folderViews.prune { FileManager.default.fileExists(atPath: $0) }
        configWatchers = [paths.configDirectory.path, paths.configFile.path].map { path in
            PathWatcher(path: path) { [weak self] in self?.reloadConfigIfChanged() }
        }
        watchThemes()
    }

    var showHiddenFiles: Bool {
        get { config.showHiddenFiles }
        set {
            config.showHiddenFiles = newValue
            saveConfig()
            NotificationCenter.default.post(name: .showHiddenChanged, object: nil)
        }
    }

    var showDSStoreFiles: Bool {
        get { config.showDSStoreFiles }
        set {
            config.showDSStoreFiles = newValue
            saveConfig()
            NotificationCenter.default.post(name: .showHiddenChanged, object: nil)
        }
    }

    var visibility: Visibility {
        config.visibility
    }

    var defaultView: FolderView {
        get { config.defaultView }
        set {
            config.defaultView = newValue
            saveConfig()
        }
    }

    var colorScheme: ColorScheme {
        get { config.appearance }
        set {
            config.appearance = newValue
            saveConfig()
            themeDidChange()
        }
    }

    var theme: ThemeDefinition {
        themes.theme(id: config.theme)
    }

    func setTheme(_ id: String, forProfile index: Int) {
        guard config.setTheme(id, forProfile: index) else { return }
        saveConfig()
        if index == config.profile {
            themeDidChange()
        } else {
            NotificationCenter.default.post(name: .configChanged, object: nil)
        }
    }

    private func profilesDidChange(themeBefore: String) {
        sidebarDidChange()
        if config.theme != themeBefore {
            themeDidChange()
        }
    }

    func reloadThemes() {
        let loaded = ThemeLibrary(directory: paths.themesDirectory)
        watchThemes()
        guard loaded != themes else { return }
        themes = loaded
        themeDidChange()
    }

    func themeDidChange() {
        Theme.apply(theme, scheme: config.appearance)
        NotificationCenter.default.post(name: .themeChanged, object: nil)
    }

    private func watchThemes() {
        let directory = paths.themesDirectory
        themeWatchers = ([directory] + ThemeLibrary.files(in: directory)).map { url in
            PathWatcher(path: url.path) { [weak self] in self?.reloadThemes() }
        }
    }

    var sidebar: SidebarTree {
        config.sidebar
    }

    var profiles: [SidebarProfile] {
        config.profiles
    }

    var profile: Int {
        config.profile
    }

    func selectProfile(_ index: Int) {
        let theme = config.theme
        if config.selectProfile(index) {
            profilesDidChange(themeBefore: theme)
        }
    }

    @discardableResult
    func addProfile() -> Int {
        let index = config.addProfile()
        sidebarDidChange()
        return index
    }

    func removeProfile(at index: Int) {
        let theme = config.theme
        if config.removeProfile(at: index) {
            profilesDidChange(themeBefore: theme)
        }
    }

    func renameProfile(at index: Int, to name: String) {
        if config.renameProfile(at: index, to: name) {
            sidebarDidChange()
        }
    }

    func setProfileIcon(at index: Int, to icon: String) {
        if config.setProfileIcon(at: index, to: icon) {
            sidebarDidChange()
        }
    }

    func sidebarDidChange() {
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
        if config.updateFolders(movedFrom: oldPath, to: newPath) {
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
            let hiddenChanged = loaded.visibility != config.visibility
            let themeChanged = loaded.theme != config.theme || loaded.appearance != config.appearance
            config = loaded
            configError = nil
            NotificationCenter.default.post(name: .sidebarChanged, object: nil)
            NotificationCenter.default.post(name: .configChanged, object: nil)
            if hiddenChanged {
                NotificationCenter.default.post(name: .showHiddenChanged, object: nil)
            }
            if themeChanged {
                themeDidChange()
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
