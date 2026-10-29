import AppKit
import Quartz

@MainActor
protocol PaneControllerDelegate: AnyObject {
    func paneDidBecomeActive(_ pane: PaneController)
    func paneDidNavigate(_ pane: PaneController)
    func paneWantsNextPane(_ pane: PaneController)
    func paneWantsNewWindow(_ pane: PaneController, path: String)
}

final class PaneController: NSViewController, FileBrowserHost, NSMenuItemValidation, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    weak var delegate: PaneControllerDelegate?
    private(set) var model: DirectoryModel
    private(set) var folderView: FolderView
    private(set) var history = NavigationHistory()
    private var browser: FileBrowser?
    private let header = PaneHeader()
    private let content = NSView()
    private let loading = NSProgressIndicator()
    private let message = NSTextField(wrappingLabelWithString: "")
    private var loadingIndicator: DispatchWorkItem?
    private var pendingSelection: Set<String> = []
    private var pendingRename: String?
    private var scrollMemory = ScrollMemory()
    private var restoresScroll = false
    private var scrolledWhileLoading = false
    private var observers: [NSObjectProtocol] = []
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            model.query = query
            model.applyPresentation()
        }
    }
    var isActive = false {
        didSet { header.isActive = isActive }
    }
    var showsHeader = false {
        didSet { header.isHidden = !showsHeader }
    }

    var path: String { model.path }
    var directoryURL: URL { browser?.browseDirectory ?? model.path.fileURL }
    var selectedItems: [FileItem] { browser?.selectedItems ?? [] }

    init(path: String) {
        let view = AppState.shared.view(for: path)
        folderView = view
        model = DirectoryModel(path: path, view: view, visibility: AppState.shared.visibility)
        super.init(nibName: nil, bundle: nil)
        history.visit(path)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func loadView() {
        let root = NSView()
        for subview in [header, content, loading, message] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }
        header.isHidden = true
        header.onClick = { [weak self] in self?.activate() }
        loading.style = .spinning
        loading.controlSize = .small
        loading.isDisplayedWhenStopped = false
        message.font = .systemFont(ofSize: NSFont.systemFontSize)
        message.textColor = Theme.secondaryText
        message.alignment = .center
        message.isHidden = true
        let headerHeight = header.heightAnchor.constraint(equalToConstant: 26)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            headerHeight,
            content.topAnchor.constraint(equalTo: header.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            loading.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            loading.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            message.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            message.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            message.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -40),
        ])
        header.heightConstraint = headerHeight
        view = root
        installBrowser()
        startModel()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, self.restoresScroll, let scroll = note.object as? NSView, scroll.isDescendant(of: self.content) else { return }
                    self.scrolledWhileLoading = true
                }
            },
            center.addObserver(forName: .showHiddenChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.model.visibility = AppState.shared.visibility
                    self.model.reload()
                }
            },
        ]
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func activate() {
        browser?.focus()
        browserDidBecomeActive()
    }

    func navigate(to path: String, select names: Set<String> = [], recordHistory: Bool = true) {
        let standardized = (path as NSString).standardizingPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory) else {
            NSSound.beep()
            return
        }
        guard isDirectory.boolValue else {
            navigate(to: (standardized as NSString).deletingLastPathComponent, select: [(standardized as NSString).lastPathComponent], recordHistory: recordHistory)
            return
        }
        if recordHistory {
            history.visit(standardized)
        }
        if model.isLoaded {
            scrollMemory.save(browser?.scrollAnchor(), for: model.path)
        }
        restoresScroll = true
        scrolledWhileLoading = false
        query = ""
        pendingRename = nil
        model.stop()
        folderView = AppState.shared.view(for: standardized)
        model = DirectoryModel(path: standardized, view: folderView, visibility: AppState.shared.visibility)
        model.query = query
        pendingSelection = Set(names.map { (standardized as NSString).appendingPathComponent($0) })
        if browserMode != folderView.mode {
            installBrowser()
        }
        startModel()
        delegate?.paneDidNavigate(self)
    }

    func refresh() {
        model.reload()
    }

    func goBack() {
        guard let path = history.back() else { return }
        let from = model.path
        navigate(to: path, select: childName(of: path, toward: from), recordHistory: false)
    }

    func goForward() {
        guard let path = history.forward() else { return }
        navigate(to: path, recordHistory: false)
    }

    func goUp() {
        let path = model.path
        guard path != "/" else { return }
        navigate(to: (path as NSString).deletingLastPathComponent, select: [(path as NSString).lastPathComponent])
    }

    func setMode(_ mode: ViewMode) {
        guard mode != folderView.mode else { return }
        folderView.mode = mode
        AppState.shared.setView(folderView, for: model.path)
        let selected = Set(selectedItems.map(\.path))
        let anchor = browser?.scrollAnchor()
        installBrowser()
        browser?.reload(.loaded)
        if let anchor { browser?.restoreScroll(anchor) }
        browser?.select(paths: selected, scroll: true)
        browser?.focus()
        delegate?.paneDidNavigate(self)
    }

    private var browserMode: ViewMode? {
        switch browser {
        case is ListBrowser: .list
        case is IconBrowser: .icons
        case is ColumnBrowser: .columns
        default: nil
        }
    }

    private func makeBrowser(for mode: ViewMode) -> FileBrowser {
        switch mode {
        case .list: ListBrowser()
        case .icons: IconBrowser()
        case .columns: ColumnBrowser()
        }
    }

    private func installBrowser() {
        let hadFocus = browser.map { view.window?.firstResponder.map(isInside(of: $0.view)) ?? false } ?? false
        if let browser {
            browser.view.removeFromSuperview()
            browser.removeFromParent()
        }
        let next = makeBrowser(for: folderView.mode)
        next.host = self
        addChild(next)
        next.view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(next.view)
        NSLayoutConstraint.activate([
            next.view.topAnchor.constraint(equalTo: content.topAnchor),
            next.view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            next.view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            next.view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        browser = next
        if hadFocus { next.focus() }
    }

    private func isInside(of container: NSView) -> (NSResponder) -> Bool {
        { responder in (responder as? NSView)?.isDescendant(of: container) ?? false }
    }

    private func startModel() {
        setLoading(true)
        model.onChange = { [weak self] change in
            guard let self else { return }
            self.browser?.reload(change)
            if case .children = change {} else {
                if case .loaded = change, self.restoresScroll {
                    self.restoresScroll = false
                    if !self.scrolledWhileLoading, let anchor = self.scrollMemory.anchor(for: self.model.path) {
                        self.browser?.restoreScroll(anchor)
                    }
                }
                self.setLoading(false)
                self.applyPending()
                if let error = self.model.error, case .loaded = change {
                    self.showMessage(error.isPermissionDenied ? "Cubby needs Full Disk Access to read this folder." : error.localizedDescription)
                }
            }
        }
        model.start()
        header.title = displayName(model.path)
    }

    private func setLoading(_ isLoading: Bool) {
        loadingIndicator?.cancel()
        loadingIndicator = nil
        if isLoading {
            showMessage(nil)
            let work = DispatchWorkItem { [weak self] in self?.loading.startAnimation(nil) }
            loadingIndicator = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        } else {
            loading.stopAnimation(nil)
        }
    }

    private func showMessage(_ text: String?) {
        message.stringValue = text ?? ""
        message.isHidden = text == nil
    }

    private func applyPending() {
        if !pendingSelection.isEmpty {
            browser?.select(paths: pendingSelection, scroll: true)
            pendingSelection = []
        }
        if let rename = pendingRename, model.items.contains(where: { $0.path == rename }) {
            pendingRename = nil
            browser?.beginRename(path: rename)
        }
    }

    private func reveal(_ urls: [URL], rename: Bool = false) {
        let paths = Set(urls.map(\.standardizedFileURL.path).filter { ($0 as NSString).deletingLastPathComponent == model.path })
        guard !paths.isEmpty else { return }
        if rename, let first = paths.first {
            pendingRename = first
        }
        pendingSelection = paths
        if model.items.contains(where: { paths.contains($0.path) }) {
            applyPending()
        }
    }

    private func displayName(_ path: String) -> String {
        path == "/" ? "Macintosh HD" : FileManager.default.displayName(atPath: path)
    }

    private func childName(of parent: String, toward path: String) -> Set<String> {
        guard path.hasPrefix(parent == "/" ? "/" : parent + "/") else { return [] }
        let rest = path.dropFirst(parent == "/" ? 1 : parent.count + 1)
        return rest.split(separator: "/").first.map { [String($0)] } ?? []
    }

    func open(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        if items.count == 1, items[0].isFolder {
            let item = items[0]
            navigate(to: item.isSymlink ? (item.path as NSString).resolvingSymlinksInPath : item.path)
            return
        }
        for item in items {
            if item.isFolder {
                delegate?.paneWantsNewWindow(self, path: item.path)
            } else {
                NSWorkspace.shared.open(item.url)
            }
        }
    }

    func browserSelectionChanged() {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible, QLPreviewPanel.shared().dataSource === self {
            QLPreviewPanel.shared().reloadData()
        }
    }

    func browserDidBecomeActive() {
        delegate?.paneDidBecomeActive(self)
    }

    func browseDirectoryChanged() {
        delegate?.paneDidNavigate(self)
    }

    func focusNextPane() {
        delegate?.paneWantsNextPane(self)
    }

    func scrollAnchor(for path: String) -> ScrollAnchor? {
        scrollMemory.anchor(for: path)
    }

    func saveScroll(_ anchor: ScrollAnchor?, for path: String) {
        scrollMemory.save(anchor, for: path)
    }

    func toggleQuickLook() {
        let panel = QLPreviewPanel.shared()!
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func rename(_ item: FileItem, to name: String) {
        guard name != item.name else { return }
        if FileNaming.becomesHidden(renaming: item.name, to: name) && !AppState.shared.showHiddenFiles {
            let alert = NSAlert()
            alert.messageText = "Are you sure you want to use a name that begins with a dot “.”?"
            alert.informativeText = "These names are reserved for the system. If you continue, “\(name)” will be hidden."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Use “.”")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        if let renamed = FileActions.rename(item.url, to: name) {
            reveal([renamed])
        }
    }

    func setSort(_ key: SortKey, ascending: Bool) {
        folderView.sort = key
        folderView.ascending = ascending
        AppState.shared.setView(folderView, for: model.path)
        model.sort = key
        model.ascending = ascending
        model.applyPresentation()
        browser?.viewDidChange()
    }

    func setIconSize(_ size: Int) {
        let clamped = min(max(size, FolderView.iconSizes.lowerBound), FolderView.iconSizes.upperBound)
        guard clamped != folderView.iconSize else { return }
        folderView.iconSize = clamped
        AppState.shared.setView(folderView, for: model.path)
        browser?.viewDidChange()
    }

    func setListIconSize(_ size: Int) {
        let clamped = FolderView(mode: folderView.mode, sort: folderView.sort, ascending: folderView.ascending, iconSize: folderView.iconSize, listIconSize: size).listIconSize
        guard clamped != folderView.listIconSize else { return }
        folderView.listIconSize = clamped
        AppState.shared.setView(folderView, for: model.path)
        browser?.viewDidChange()
    }

    func drop(_ urls: [URL], into directory: URL, operation: NSDragOperation) -> Bool {
        let copy = operation == .copy
        let reveals = directory.standardizedFileURL.path == model.path
        FileActions.transfer(urls, to: directory, copy: copy) { [weak self] destinations in
            if reveals { self?.reveal(destinations) }
        }
        return true
    }

    func menu(for items: [FileItem], in directory: URL) -> NSMenu {
        ContextMenu.build(for: items, in: directory, pane: self)
    }

    private var actionURLs: [URL] { selectedItems.map(\.url) }

    @objc func openSelection(_ sender: Any?) { open(selectedItems) }
    @objc func goBack(_ sender: Any?) { goBack() }
    @objc func goForward(_ sender: Any?) { goForward() }
    @objc func goToEnclosingFolder(_ sender: Any?) { goUp() }
    @objc func refresh(_ sender: Any?) { refresh() }
    @objc func quickLook(_ sender: Any?) { toggleQuickLook() }

    @objc func newFolder(_ sender: Any?) {
        if let url = FileActions.newFolder(in: directoryURL) { reveal([url], rename: true) }
    }

    @objc func newFile(_ sender: Any?) {
        if let url = FileActions.newFile(in: directoryURL) { reveal([url], rename: true) }
    }

    @objc func newFolderWithSelection(_ sender: Any?) {
        FileActions.newFolder(with: actionURLs, in: directoryURL) { [weak self] folder in self?.reveal([folder], rename: true) }
    }

    @objc func renameSelection(_ sender: Any?) {
        guard let item = selectedItems.first else { return }
        browser?.beginRename(path: item.path)
    }

    @objc func duplicate(_ sender: Any?) {
        FileActions.duplicate(actionURLs) { [weak self] urls in self?.reveal(urls) }
    }

    @objc func moveToTrash(_ sender: Any?) {
        FileActions.trash(actionURLs)
    }

    @objc func copy(_ sender: Any?) { FileActions.writeToPasteboard(actionURLs, cut: false) }
    @objc func cut(_ sender: Any?) {
        FileActions.writeToPasteboard(actionURLs, cut: true)
        browser?.reload(.refreshed)
    }

    @objc func paste(_ sender: Any?) {
        FileActions.paste(into: directoryURL, forceMove: false) { [weak self] urls in self?.reveal(urls) }
    }

    @objc func pasteAndMove(_ sender: Any?) {
        FileActions.paste(into: directoryURL, forceMove: true) { [weak self] urls in self?.reveal(urls) }
    }

    @objc func copyPath(_ sender: Any?) {
        FileActions.copyPaths(actionURLs.isEmpty ? [directoryURL] : actionURLs)
    }

    @objc func compress(_ sender: Any?) {
        FileActions.compress(actionURLs) { [weak self] url in self?.reveal([url]) }
    }

    @objc func showInFinder(_ sender: Any?) {
        if actionURLs.isEmpty {
            NSWorkspace.shared.open(directoryURL)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(actionURLs)
        }
    }

    @objc func openInTerminal(_ sender: Any?) {
        let folder = selectedItems.count == 1 && selectedItems[0].isFolder ? selectedItems[0].url : directoryURL
        FileActions.openInTerminal(folder)
    }

    @objc func addToSidebar(_ sender: Any?) {
        let folders = selectedItems.filter(\.isFolder).map(\.url)
        SidebarController.add(folders.isEmpty ? [directoryURL] : folders)
    }

    @objc func share(_ sender: Any?) {
        let picker = NSSharingServicePicker(items: actionURLs)
        let point = view.convert(view.window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        picker.show(relativeTo: NSRect(origin: point, size: NSSize(width: 1, height: 1)), of: view, preferredEdge: .minY)
    }

    @objc func showPackageContents(_ sender: Any?) {
        guard let item = selectedItems.first, item.isPackage else { return }
        navigate(to: item.path)
    }

    @objc func setViewMode(_ sender: Any?) {
        guard let tag = (sender as? NSMenuItem)?.tag ?? (sender as? NSSegmentedControl)?.selectedSegment, ViewMode.allCases.indices.contains(tag) else { return }
        setMode(ViewMode.allCases[tag])
    }

    @objc func sortBy(_ sender: NSMenuItem) {
        guard SortKey.allCases.indices.contains(sender.tag) else { return }
        let key = SortKey.allCases[sender.tag]
        setSort(key, ascending: key == folderView.sort ? !folderView.ascending : key.defaultAscending)
    }

    @objc func setSortDirection(_ sender: NSMenuItem) {
        setSort(folderView.sort, ascending: sender.tag == 0)
    }

    @objc func biggerIcons(_ sender: Any?) {
        if folderView.mode == .list {
            setListIconSize(folderView.steppedListIconSize(bigger: true))
        } else {
            setIconSize(folderView.iconSize + 16)
        }
    }

    @objc func smallerIcons(_ sender: Any?) {
        if folderView.mode == .list {
            setListIconSize(folderView.steppedListIconSize(bigger: false))
        } else {
            setIconSize(folderView.iconSize - 16)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if view.window?.firstResponder is NSTextView, let action = menuItem.action, BrowserWindowController.textEditingBlockedActions.contains(action) {
            return false
        }
        let hasSelection = !selectedItems.isEmpty
        switch menuItem.action {
        case #selector(goBack(_:)): return history.canGoBack
        case #selector(goForward(_:)): return history.canGoForward
        case #selector(goToEnclosingFolder(_:)): return model.path != "/"
        case #selector(openSelection(_:)), #selector(renameSelection(_:)), #selector(duplicate(_:)), #selector(moveToTrash(_:)), #selector(copy(_:)), #selector(cut(_:)), #selector(compress(_:)), #selector(newFolderWithSelection(_:)), #selector(quickLook(_:)):
            return hasSelection
        case #selector(paste(_:)), #selector(pasteAndMove(_:)):
            return !FileActions.pasteboardURLs().isEmpty
        case #selector(setViewMode(_:)):
            menuItem.state = ViewMode.allCases.indices.contains(menuItem.tag) && ViewMode.allCases[menuItem.tag] == folderView.mode ? .on : .off
            return true
        case #selector(sortBy(_:)):
            let isCurrent = SortKey.allCases.indices.contains(menuItem.tag) && SortKey.allCases[menuItem.tag] == folderView.sort
            menuItem.state = isCurrent ? .on : .off
            return true
        case #selector(setSortDirection(_:)):
            menuItem.state = folderView.sort.hasDirection && (menuItem.tag == 0) == folderView.ascending ? .on : .off
            return folderView.sort.hasDirection
        case #selector(biggerIcons(_:)), #selector(smallerIcons(_:)):
            return folderView.mode == .icons || folderView.mode == .list
        case #selector(showPackageContents(_:)):
            return selectedItems.count == 1 && selectedItems[0].isPackage
        default:
            return true
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { selectedItems.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated {
            let items = selectedItems
            return items.indices.contains(index) ? items[index].url as NSURL : nil
        }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        MainActor.assumeIsolated {
            guard event.type == .keyDown, let browser else { return false }
            let target: NSView? = (browser as? ListBrowser)?.outlineView ?? (browser as? TileBrowser)?.collectionView
            guard let target else { return false }
            target.keyDown(with: event)
            return true
        }
    }
}

final class PaneHeader: NSView {
    private let label = NSTextField(labelWithString: "")
    var heightConstraint: NSLayoutConstraint?
    var onClick: (() -> Void)?

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    var isActive = false {
        didSet { needsDisplay = true; label.textColor = isActive ? Theme.text : Theme.tertiaryText }
    }

    override var isHidden: Bool {
        didSet { heightConstraint?.constant = isHidden ? 0 : 26 }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingMiddle
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.content.setFill()
        bounds.fill()
        Theme.divider.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        if isActive {
            Theme.accent.setFill()
            NSRect(x: 0, y: bounds.height - 2, width: bounds.width, height: 2).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
