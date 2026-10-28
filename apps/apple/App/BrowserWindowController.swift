import AppKit

final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSSearchFieldDelegate, PaneControllerDelegate, SidebarControllerDelegate {
    private let splitController = NSSplitViewController()
    private let sidebar = SidebarController()
    private let container = NSViewController()
    private let topBar = TopBar()
    private let panesView = NSView()
    private var settings: SettingsController?
    private var titlebarHeight: CGFloat = 0
    private(set) var panes: [PaneController] = []
    private(set) var layout: PaneLayout = .single
    private(set) var activeIndex = 0
    private var sidebarItem: NSSplitViewItem?
    private var activityObserver: NSObjectProtocol?
    private let textUndoManager = UndoManager()

    var activePane: PaneController { panes[min(activeIndex, panes.count - 1)] }

    init(tab: SessionState.Tab, sidebarWidth: Double? = nil) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.tabbingMode = .disallowed
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.minSize = NSSize(width: 520, height: 320)
        window.isReleasedWhenClosed = false
        window.backgroundColor = Theme.content
        super.init(window: window)
        window.delegate = self

        let splitView = ThemedSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitController.splitView = splitView
        sidebar.delegate = self
        let sidebarItem = NSSplitViewItem(viewController: sidebar)
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 400
        sidebarItem.canCollapse = true
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(260)
        self.sidebarItem = sidebarItem
        container.view = FillView()
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
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact
        installTopBar(titlebarHeight: window.frame.height - window.contentLayoutRect.height)

        layout = tab.layout
        panes = tab.paths.map(makePane)
        activeIndex = min(max(tab.activePane, 0), panes.count - 1)
        rebuildLayout()
        updateActive()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    private func installTopBar(titlebarHeight: CGFloat) {
        self.titlebarHeight = titlebarHeight
        let root = container.view
        for subview in [topBar, panesView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }
        topBar.searchField.delegate = self
        topBar.onNavigate = { [weak self] path in
            self?.activePane.navigate(to: path)
            self?.activePane.activate()
        }
        let top = topBar.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: -titlebarHeight)
        top.priority = .defaultHigh
        NSLayoutConstraint.activate([
            top,
            topBar.topAnchor.constraint(greaterThanOrEqualTo: root.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: max(titlebarHeight, 32)),
            panesView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            panesView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            panesView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            panesView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        activityObserver = NotificationCenter.default.addObserver(forName: .activityChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.topBar.activity = FileActions.activityText }
        }
        topBar.activity = FileActions.activityText
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
        panesView.subviews.forEach { $0.removeFromSuperview() }
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
        panesView.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: panesView.topAnchor),
            root.leadingAnchor.constraint(equalTo: panesView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: panesView.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: panesView.bottomAnchor),
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
        topBar.path = url.path
        topBar.mode = pane.folderView.mode
        topBar.layout = layout
        topBar.searchField.stringValue = pane.query
        if pane.query.isEmpty && !isEditingFilter {
            topBar.isFilterVisible = false
        }
        sidebar.reveal(path: pane.path)
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
        closeSettings()
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

    func paneWantsNewWindow(_ pane: PaneController, path: String) {
        AppDelegate.shared?.openWindow(path: path)
    }

    func sidebar(_ sidebar: SidebarController, open url: URL, newWindow: Bool) {
        if newWindow {
            AppDelegate.shared?.openWindow(path: url.path)
        } else {
            closeSettings()
            activePane.navigate(to: url.path)
            activePane.activate()
        }
    }

    @objc func showSettings(_ sender: Any?) {
        if settings != nil {
            closeSettings()
            return
        }
        let controller = SettingsController()
        controller.headerHeight = max(titlebarHeight, 32)
        controller.onClose = { [weak self] in self?.closeSettings() }
        container.addChild(controller)
        let view = controller.view
        view.translatesAutoresizingMaskIntoConstraints = false
        container.view.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topBar.topAnchor),
            view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: container.view.bottomAnchor),
        ])
        topBar.isHidden = true
        panesView.isHidden = true
        settings = controller
        sidebar.isSettingsActive = true
        window?.makeFirstResponder(view)
    }

    func closeSettings() {
        guard let settings else { return }
        settings.view.removeFromSuperview()
        settings.removeFromParent()
        self.settings = nil
        sidebar.isSettingsActive = false
        topBar.isHidden = false
        panesView.isHidden = false
        activePane.activate()
    }

    private static let selectionActions: Set<Selector> = [
        #selector(PaneController.openSelection(_:)), #selector(PaneController.moveToTrash(_:)), #selector(PaneController.copy(_:)),
        #selector(PaneController.cut(_:)), #selector(PaneController.duplicate(_:)), #selector(PaneController.renameSelection(_:)),
        #selector(PaneController.compress(_:)), #selector(PaneController.quickLook(_:)), #selector(PaneController.newFolderWithSelection(_:)),
        #selector(PaneController.share(_:)), #selector(PaneController.showPackageContents(_:)),
    ]

    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        let sidebarFocused = (window?.firstResponder as? NSView)?.isDescendant(of: sidebar.view) ?? false
        if (sidebarFocused || settings != nil) && BrowserWindowController.selectionActions.contains(action) { return nil }
        if activePane.responds(to: action) { return activePane }
        return super.supplementalTarget(forAction: action, sender: sender)
    }

    @objc func changeLayout(_ sender: NSMenuItem) {
        guard PaneLayout.allCases.indices.contains(sender.tag) else { return }
        setLayout(PaneLayout.allCases[sender.tag])
    }

    private var isEditingFilter: Bool {
        topBar.searchField.currentEditor() != nil
    }

    @objc func performFindPanelAction(_ sender: Any?) {
        if topBar.isFilterVisible && isEditingFilter && topBar.searchField.stringValue.isEmpty {
            topBar.isFilterVisible = false
            activePane.activate()
            return
        }
        topBar.isFilterVisible = true
        window?.makeFirstResponder(topBar.searchField)
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
        sidebarItem?.animator().isCollapsed.toggle()
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
        activityObserver.map(NotificationCenter.default.removeObserver)
        AppDelegate.shared?.windowClosed(self)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else { return }
        activePane.query = field.stringValue
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        if topBar.searchField.stringValue.isEmpty {
            topBar.isFilterVisible = false
        }
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
}
