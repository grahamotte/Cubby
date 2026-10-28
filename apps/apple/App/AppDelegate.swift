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
        NSApp.mainMenu = MainMenu.build()
        #if CUBBY_DEV
        DebugHooks.install()
        #endif
        UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")
        let state = AppState.shared
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
            if let current = NSApp.keyWindow?.windowController as? BrowserWindowController {
                openTab(path: path, in: current)
            } else {
                openWindow(path: path)
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func restore(_ session: SessionState) {
        let home = NSHomeDirectory()
        let exists = { (path: String) in FileManager.default.fileExists(atPath: path) }
        for window in session.windows where !window.tabs.isEmpty {
            var first: BrowserWindowController?
            var selected: BrowserWindowController?
            for (index, tab) in window.tabs.enumerated() {
                let controller = BrowserWindowController(tab: tab.normalized(home: home, exists: exists), sidebarWidth: window.sidebarWidth)
                controllers.append(controller)
                if let first, let tabWindow = controller.window {
                    first.window?.addTabbedWindow(tabWindow, ordered: .above)
                } else {
                    if let frame = window.frame {
                        controller.window?.setFrame(from: frame)
                    } else {
                        controller.window?.center()
                    }
                    controller.showWindow(nil)
                    first = controller
                }
                if index == window.selectedTab { selected = controller }
            }
            (selected ?? first)?.window?.makeKeyAndOrderFront(nil)
        }
    }

    @discardableResult
    func openWindow(path: String, layout: PaneLayout = .single) -> BrowserWindowController {
        let tab = SessionState.Tab(layout: layout, paths: [path], activePane: 0).normalized(home: NSHomeDirectory()) { FileManager.default.fileExists(atPath: $0) }
        let reference = NSApp.keyWindow?.windowController as? BrowserWindowController
        let controller = BrowserWindowController(tab: tab, sidebarWidth: reference?.sidebarWidth)
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

    func openTab(path: String, in reference: BrowserWindowController) {
        let tab = SessionState.Tab(layout: .single, paths: [path], activePane: 0).normalized(home: NSHomeDirectory()) { FileManager.default.fileExists(atPath: $0) }
        let controller = BrowserWindowController(tab: tab, sidebarWidth: reference.sidebarWidth)
        controllers.append(controller)
        if let window = controller.window, let referenceWindow = reference.window {
            referenceWindow.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
        } else {
            controller.showWindow(nil)
        }
        controller.activePane.activate()
        saveSessionSoon()
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
        var windows: [SessionState.Window] = []
        var seen = Set<ObjectIdentifier>()
        let ordered = NSApp.orderedWindows.compactMap { $0.windowController as? BrowserWindowController }
        let all = ordered + controllers.filter { controller in !ordered.contains { $0 === controller } }
        for controller in all {
            guard let window = controller.window, !seen.contains(ObjectIdentifier(window)) else { continue }
            let group = window.tabbedWindows ?? [window]
            group.forEach { seen.insert(ObjectIdentifier($0)) }
            let tabControllers = group.compactMap { $0.windowController as? BrowserWindowController }
            guard !tabControllers.isEmpty else { continue }
            let selected = tabControllers.firstIndex { $0.window === window.tabGroup?.selectedWindow } ?? 0
            windows.append(SessionState.Window(frame: window.frameDescriptor, sidebarWidth: controller.sidebarWidth, tabs: tabControllers.map(\.tabState), selectedTab: selected))
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

    @objc func newTab(_ sender: Any?) {
        if let controller = keyController {
            openTab(path: controller.activePane.path, in: controller)
        } else {
            openWindow(path: NSHomeDirectory())
        }
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
