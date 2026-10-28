import AppKit

extension NSToolbarItem.Identifier {
    static let navigation = NSToolbarItem.Identifier("navigation")
    static let viewMode = NSToolbarItem.Identifier("viewMode")
    static let layout = NSToolbarItem.Identifier("layout")
    static let search = NSToolbarItem.Identifier("search")
    static let newFolder = NSToolbarItem.Identifier("newFolder")
}

final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSSearchFieldDelegate, PaneControllerDelegate, SidebarControllerDelegate {
    private let splitController = NSSplitViewController()
    private let sidebar = SidebarController()
    private let container = NSViewController()
    private(set) var panes: [PaneController] = []
    private(set) var layout: PaneLayout = .single
    private(set) var activeIndex = 0
    private var viewModeGroup: NSToolbarItemGroup?
    private var navigationGroup: NSToolbarItemGroup?
    private var searchItem: NSSearchToolbarItem?
    private var sidebarItem: NSSplitViewItem?
    private let textUndoManager = UndoManager()

    var activePane: PaneController { panes[min(activeIndex, panes.count - 1)] }

    init(tab: SessionState.Tab, sidebarWidth: Double? = nil) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.tabbingMode = .automatic
        window.tabbingIdentifier = "CubbyBrowser"
        window.titleVisibility = .visible
        window.minSize = NSSize(width: 520, height: 320)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        sidebar.delegate = self
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 400
        sidebarItem.canCollapse = true
        self.sidebarItem = sidebarItem
        container.view = NSView()
        let contentItem = NSSplitViewItem(viewController: container)
        contentItem.minimumThickness = 300
        splitController.addSplitViewItem(sidebarItem)
        splitController.addSplitViewItem(contentItem)
        splitController.splitView.autosaveName = nil
        window.contentViewController = splitController
        window.setContentSize(NSSize(width: 1100, height: 680))
        if let sidebarWidth {
            splitController.splitView.setPosition(sidebarWidth, ofDividerAt: 0)
        } else {
            splitController.splitView.setPosition(210, ofDividerAt: 0)
        }

        let toolbar = NSToolbar(identifier: "CubbyToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        layout = tab.layout
        panes = tab.paths.map(makePane)
        activeIndex = min(max(tab.activePane, 0), panes.count - 1)
        rebuildLayout()
        updateActive()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    var sidebarWidth: Double {
        guard let view = sidebarItem?.viewController.view, sidebarItem?.isCollapsed == false else { return 210 }
        return view.frame.width
    }

    var tabState: SessionState.Tab {
        SessionState.Tab(layout: layout, paths: panes.map(\.path), activePane: activeIndex)
    }

    private func makePane(_ path: String) -> PaneController {
        let pane = PaneController(path: path)
        pane.delegate = self
        return pane
    }

    func setLayout(_ newLayout: PaneLayout) {
        guard newLayout != layout else { return }
        let count = newLayout.paneCount
        let activePath = activePane.path
        if panes.count > count {
            let active = activePane
            let keep = activeIndex < count ? Array(panes.prefix(count)) : Array(panes.prefix(count - 1)) + [active]
            for pane in panes where !keep.contains(where: { $0 === pane }) {
                pane.model.stop()
                pane.view.removeFromSuperview()
                pane.removeFromParent()
            }
            panes = keep
            activeIndex = panes.firstIndex { $0 === active } ?? 0
        }
        while panes.count < count {
            panes.append(makePane(activePath))
        }
        layout = newLayout
        rebuildLayout()
        updateActive()
        activePane.activate()
        AppDelegate.shared?.saveSessionSoon()
    }

    private func rebuildLayout() {
        for pane in panes {
            pane.view.removeFromSuperview()
            pane.removeFromParent()
        }
        container.view.subviews.forEach { $0.removeFromSuperview() }
        var index = 0
        let rows: [NSView] = layout.rows.map { columns in
            let views: [NSView] = (0..<columns).map { _ in
                let pane = panes[index]
                index += 1
                container.addChild(pane)
                pane.showsHeader = layout.paneCount > 1
                return pane.view
            }
            return views.count == 1 ? views[0] : makeSplit(views, vertical: true)
        }
        let root = rows.count == 1 ? rows[0] : makeSplit(rows, vertical: false)
        root.translatesAutoresizingMaskIntoConstraints = false
        container.view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: container.view.safeAreaLayoutGuide.topAnchor),
            root.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: container.view.bottomAnchor),
        ])
        container.view.layoutSubtreeIfNeeded()
        equalize(root)
    }

    private func makeSplit(_ views: [NSView], vertical: Bool) -> NSSplitView {
        let split = NSSplitView()
        split.isVertical = vertical
        split.dividerStyle = .thin
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = true
            split.addArrangedSubview(view)
        }
        return split
    }

    private func equalize(_ view: NSView) {
        guard let split = view as? NSSplitView else { return }
        let count = split.arrangedSubviews.count
        let total = split.isVertical ? split.bounds.width : split.bounds.height
        for index in 0..<(count - 1) {
            split.setPosition(total * CGFloat(index + 1) / CGFloat(count), ofDividerAt: index)
        }
        split.arrangedSubviews.forEach(equalize)
    }

    private func updateActive() {
        for (index, pane) in panes.enumerated() {
            pane.isActive = index == activeIndex && panes.count > 1
        }
        let pane = activePane
        let url = pane.directoryURL
        window?.title = url.path == "/" ? "Macintosh HD" : FileManager.default.displayName(atPath: url.path)
        window?.representedURL = url
        window?.tab.title = window?.title ?? ""
        viewModeGroup?.selectedIndex = ViewMode.allCases.firstIndex(of: pane.folderView.mode) ?? 0
        searchItem?.searchField.stringValue = pane.query
        sidebar.reveal(path: pane.path)
        navigationGroup?.subitems[0].isEnabled = pane.history.canGoBack
        navigationGroup?.subitems[1].isEnabled = pane.history.canGoForward
    }

    func open(_ path: String) {
        activePane.navigate(to: path)
    }

    func paneDidBecomeActive(_ pane: PaneController) {
        guard let index = panes.firstIndex(where: { $0 === pane }), index != activeIndex else { return }
        activeIndex = index
        updateActive()
    }

    func paneDidNavigate(_ pane: PaneController) {
        if pane === activePane {
            updateActive()
        }
        AppDelegate.shared?.saveSessionSoon()
    }

    func paneWantsNextPane(_ pane: PaneController) {
        guard panes.count > 1, let index = panes.firstIndex(where: { $0 === pane }) else { return }
        activeIndex = (index + 1) % panes.count
        activePane.activate()
        updateActive()
    }

    func paneWantsNewTab(_ pane: PaneController, path: String) {
        AppDelegate.shared?.openTab(path: path, in: self)
    }

    func sidebar(_ sidebar: SidebarController, open url: URL, newTab: Bool) {
        if newTab {
            AppDelegate.shared?.openTab(path: url.path, in: self)
        } else {
            activePane.navigate(to: url.path)
            activePane.activate()
        }
    }

    private static let selectionActions: Set<Selector> = [
        #selector(PaneController.openSelection(_:)), #selector(PaneController.moveToTrash(_:)), #selector(PaneController.copy(_:)),
        #selector(PaneController.cut(_:)), #selector(PaneController.duplicate(_:)), #selector(PaneController.renameSelection(_:)),
        #selector(PaneController.compress(_:)), #selector(PaneController.quickLook(_:)), #selector(PaneController.newFolderWithSelection(_:)),
        #selector(PaneController.share(_:)), #selector(PaneController.showPackageContents(_:)),
    ]

    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        let sidebarFocused = (window?.firstResponder as? NSView)?.isDescendant(of: sidebar.view) ?? false
        if sidebarFocused && BrowserWindowController.selectionActions.contains(action) { return nil }
        if activePane.responds(to: action) { return activePane }
        return super.supplementalTarget(forAction: action, sender: sender)
    }

    override func newWindowForTab(_ sender: Any?) {
        AppDelegate.shared?.openTab(path: activePane.path, in: self)
    }

    @objc func changeLayout(_ sender: NSMenuItem) {
        guard PaneLayout.allCases.indices.contains(sender.tag) else { return }
        setLayout(PaneLayout.allCases[sender.tag])
    }

    @objc func changeViewMode(_ sender: NSToolbarItemGroup) {
        guard ViewMode.allCases.indices.contains(sender.selectedIndex) else { return }
        activePane.setMode(ViewMode.allCases[sender.selectedIndex])
    }

    @objc func navigate(_ sender: NSToolbarItemGroup) {
        if sender.selectedIndex == 0 { activePane.goBack() } else { activePane.goForward() }
    }

    @objc func performFindPanelAction(_ sender: Any?) {
        guard let searchItem else { return }
        window?.makeFirstResponder(searchItem.searchField)
    }

    @objc func goToFolder(_ sender: Any?) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Go to Folder"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "~/Downloads"
        field.stringValue = (activePane.path as NSString).abbreviatingWithTildeInPath
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let path = (field.stringValue.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
            let resolved = path.hasPrefix("/") ? path : (self.activePane.path as NSString).appendingPathComponent(path)
            self.activePane.navigate(to: resolved)
            self.activePane.activate()
        }
    }

    @objc func goToLocation(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        activePane.navigate(to: path)
        activePane.activate()
    }

    @objc func toggleSidebarVisibility(_ sender: Any?) {
        splitController.toggleSidebar(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(changeLayout(_:)) {
            menuItem.state = PaneLayout.allCases.indices.contains(menuItem.tag) && PaneLayout.allCases[menuItem.tag] == layout ? .on : .off
        }
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        updateActive()
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        window.firstResponder is NSTextView ? textUndoManager : AppState.shared.undoManager
    }

    func windowWillClose(_ notification: Notification) {
        panes.forEach { $0.model.stop() }
        AppDelegate.shared?.windowClosed(self)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else { return }
        activePane.query = field.stringValue
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) || commandSelector == #selector(NSResponder.moveDown(_:)) {
            activePane.activate()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            (control as? NSSearchField)?.stringValue = ""
            activePane.query = ""
            activePane.activate()
            return true
        }
        return false
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .navigation, .flexibleSpace, .newFolder, .viewMode, .layout, .search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .navigation:
            let images = ["chevron.backward", "chevron.forward"].compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            let group = NSToolbarItemGroup(itemIdentifier: itemIdentifier, images: images, selectionMode: .momentary, labels: ["Back", "Forward"], target: self, action: #selector(navigate(_:)))
            group.label = "Back/Forward"
            group.controlRepresentation = .expanded
            navigationGroup = group
            return group
        case .viewMode:
            let images = ViewMode.allCases.compactMap { NSImage(systemSymbolName: $0.symbolName, accessibilityDescription: $0.title) }
            let group = NSToolbarItemGroup(itemIdentifier: itemIdentifier, images: images, selectionMode: .selectOne, labels: ViewMode.allCases.map(\.title), target: self, action: #selector(changeViewMode(_:)))
            group.label = "View"
            group.controlRepresentation = .expanded
            group.selectedIndex = ViewMode.allCases.firstIndex(of: panes.first?.folderView.mode ?? .list) ?? 0
            viewModeGroup = group
            return group
        case .layout:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Layout")
            item.label = "Layout"
            item.toolTip = "Pane Layout"
            let menu = NSMenu()
            for (index, layout) in PaneLayout.allCases.enumerated() {
                let entry = NSMenuItem(title: layout.title, action: #selector(changeLayout(_:)), keyEquivalent: "")
                entry.tag = index
                entry.target = self
                entry.image = NSImage(systemSymbolName: layout.symbolName, accessibilityDescription: nil)
                menu.addItem(entry)
            }
            item.menu = menu
            item.showsIndicator = true
            return item
        case .newFolder:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "New Folder")
            item.label = "New Folder"
            item.toolTip = "New Folder"
            item.action = #selector(PaneController.newFolder(_:))
            return item
        case .search:
            let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
            item.searchField.placeholderString = "Filter"
            item.searchField.delegate = self
            item.searchField.sendsSearchStringImmediately = true
            item.resignsFirstResponderWithCancel = true
            searchItem = item
            return item
        default:
            return nil
        }
    }
}
