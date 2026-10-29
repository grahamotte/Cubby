import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private(set) static weak var shared: AppDelegate?

    private var controllers: [BrowserWindowController] = []
    private var sessionWorkItem: DispatchWorkItem?
    private var launched = false
    private var pendingPaths: [String] = []

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.mainMenu = MainMenu.build()
        #if CUBBY_DEV
        DebugHooks.install()
        #endif
        UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")
        let state = AppState.shared
        Theme.apply(state.theme, scheme: state.colorScheme)
        if let session = SessionState.load(from: state.paths.sessionFile) {
            state.listColumns = session.listColumns ?? []
            restore(session)
        }
        launched = true
        for path in pendingPaths {
            openWindow(path: path)
        }
        pendingPaths = []
        if controllers.isEmpty {
            openWindow(path: NSHomeDirectory())
        }
        NSApp.activate()
        state.presentConfigError()
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveSession()
        AppState.shared.flush()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openWindow(path: NSHomeDirectory())
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let paths = urls.filter(\.isFileURL).map(\.path)
        guard launched else {
            pendingPaths += paths
            return
        }
        for path in paths {
            openWindow(path: path)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func restore(_ session: SessionState) {
        for window in session.windows where window.tabs.contains(where: { $0 != nil }) {
            let controller = BrowserWindowController(tabs: ProfileTabs(tabs: window.tabs, profile: AppState.shared.profile), sidebarWidth: window.sidebarWidth)
            controllers.append(controller)
            if let frame = window.frame {
                controller.window?.setFrame(from: frame)
            } else {
                controller.window?.center()
            }
            controller.showWindow(nil)
        }
    }

    @discardableResult
    func openWindow(path: String, layout: PaneLayout = .single) -> BrowserWindowController {
        let tab = SessionState.Tab(layout: layout, paths: [path], activePane: 0)
        let reference = NSApp.keyWindow?.windowController as? BrowserWindowController
        let controller = BrowserWindowController(tabs: ProfileTabs(tab: tab, profile: AppState.shared.profile), sidebarWidth: reference?.sidebarWidth)
        controllers.append(controller)
        if let referenceWindow = reference?.window, let window = controller.window {
            window.setFrame(referenceWindow.frame, display: false)
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: referenceWindow.frame.minX, y: referenceWindow.frame.maxY)))
        } else {
            controller.window?.center()
        }
        controller.showWindow(nil)
        controller.activePane.activate()
        saveSessionSoon()
        return controller
    }

    func windowClosed(_ controller: BrowserWindowController) {
        controllers.removeAll { $0 === controller }
        saveSessionSoon()
    }

    func saveSessionSoon() {
        sessionWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveSession() }
        sessionWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }

    private func saveSession() {
        sessionWorkItem?.cancel()
        let ordered = NSApp.orderedWindows.compactMap { $0.windowController as? BrowserWindowController }
        let all = ordered + controllers.filter { controller in !ordered.contains { $0 === controller } }
        let windows = all.compactMap { controller in
            controller.window.map { SessionState.Window(frame: $0.frameDescriptor, sidebarWidth: controller.sidebarWidth, tabs: controller.profileTabs.saving(controller.tabState)) }
        }
        let state = SessionState(windows: windows, listColumns: AppState.shared.listColumns.isEmpty ? nil : AppState.shared.listColumns)
        try? state.save(to: AppState.shared.paths.sessionFile)
    }

    private var keyController: BrowserWindowController? {
        NSApp.keyWindow?.windowController as? BrowserWindowController ?? controllers.last
    }

    @objc func newWindow(_ sender: Any?) {
        openWindow(path: keyController?.activePane.path ?? NSHomeDirectory())
    }

    @objc func toggleHiddenFiles(_ sender: Any?) {
        AppState.shared.showHiddenFiles.toggle()
    }

    @objc func openConfigFile(_ sender: Any?) {
        let url = AppState.shared.paths.configFile
        if !FileManager.default.fileExists(atPath: url.path) {
            AppState.shared.saveConfig()
        }
        let textEdit = NSWorkspace.shared.urlForApplication(toOpen: .plainText) ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")
        if let textEdit {
            NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleHiddenFiles(_:)) {
            menuItem.state = AppState.shared.showHiddenFiles ? .on : .off
        }
        return true
    }
}
