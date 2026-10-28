import AppKit

@MainActor
protocol SidebarControllerDelegate: AnyObject {
    func sidebar(_ sidebar: SidebarController, open url: URL, newTab: Bool)
}

final class SidebarOutlineView: NSOutlineView {
    weak var controller: SidebarController?

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        return controller?.menu(forRow: row)
    }

    override func keyDown(with event: NSEvent) {
        if controller?.handleKey(event) == true { return }
        super.keyDown(with: event)
    }

    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        .zero
    }

    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        let frame = super.frameOfCell(atColumn: column, row: row)
        let x = 18 + CGFloat(level(forRow: row)) * 14
        return NSRect(x: x, y: frame.minY, width: max(bounds.width - x - 12, 0), height: frame.height)
    }
}

final class SidebarController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuItemValidation {
    static let nodeType = NSPasteboard.PasteboardType("com.grahamotte.cubby.sidebar-node")

    weak var delegate: SidebarControllerDelegate?
    private let outlineView = SidebarOutlineView()
    private let renameField = RenameField.make()
    private var draggedNodes: [SidebarNode] = []
    private var reloading = false
    private var currentPath: String?

    private var state: AppState { .shared }
    private var tree: SidebarTree { state.sidebar }

    override func loadView() {
        outlineView.controller = self
        outlineView.headerView = nil
        outlineView.style = .plain
        outlineView.backgroundColor = .clear
        outlineView.rowSizeStyle = .custom
        outlineView.rowHeight = 28
        outlineView.floatsGroupRows = false
        outlineView.indentationPerLevel = 12
        outlineView.allowsMultipleSelection = false
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(clicked)
        outlineView.doubleAction = #selector(doubleClicked)
        outlineView.registerForDraggedTypes([SidebarController.nodeType, .fileURL])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        outlineView.draggingDestinationFeedbackStyle = .sourceList
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("node"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        let scroll = NSScrollView()
        scroll.documentView = outlineView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let settings = PlainButton.make("gearshape", "Settings", target: nil, action: #selector(BrowserWindowController.showSettings(_:)))
        let add = PlainButton.make("plus", "New Group", target: self, action: #selector(newGroup(_:)))
        let buttons = NSStackView(views: [settings, add])
        buttons.orientation = .horizontal
        buttons.spacing = 4
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let root = FillView()
        root.color = Theme.sidebar
        root.addSubview(scroll)
        root.addSubview(buttons)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -6),
            buttons.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
        ])
        view = root
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(sidebarChanged), name: .sidebarChanged, object: nil)
    }

    static func add(_ urls: [URL]) {
        let state = AppState.shared
        let tree = state.sidebar
        let folders = urls.filter(isFolder).map(tree.makeFolder)
        guard !folders.isEmpty else { return }
        let target = tree.nodes.first { $0.kind == .group }
        for folder in folders {
            tree.insert(folder, into: target)
        }
        state.sidebarDidChange()
    }

    static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    func reveal(path: String?) {
        currentPath = path
        updateSelection()
    }

    private func updateSelection() {
        guard let currentPath else {
            outlineView.deselectAll(nil)
            return
        }
        for row in 0..<outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? SidebarNode, node.url?.standardizedFileURL.path == currentPath {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                return
            }
        }
        outlineView.deselectAll(nil)
    }

    private func reload() {
        reloading = true
        outlineView.reloadData()
        expandNodes(tree.nodes)
        reloading = false
        updateSelection()
    }

    private func expandNodes(_ nodes: [SidebarNode]) {
        for node in nodes where node.kind == .group {
            if node.isCollapsed {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
                expandNodes(node.children)
            }
        }
    }

    @objc private func sidebarChanged() {
        reload()
    }

    private func save() {
        state.sidebarDidChange()
    }

    private var clickedNode: SidebarNode? {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        return outlineView.item(atRow: row) as? SidebarNode
    }

    @objc private func clicked() {
        guard let node = outlineView.item(atRow: outlineView.clickedRow) as? SidebarNode else { return }
        if node.kind == .folder, let url = node.url {
            let newTab = NSEvent.modifierFlags.contains(.command)
            delegate?.sidebar(self, open: url, newTab: newTab)
            if newTab { updateSelection() }
        } else {
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
            }
            updateSelection()
        }
    }

    @objc private func doubleClicked() {
        guard let node = outlineView.item(atRow: outlineView.clickedRow) as? SidebarNode, node.kind == .group else { return }
        beginRename(node)
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard let node = outlineView.item(atRow: outlineView.selectedRow) as? SidebarNode else { return false }
        switch event.keyCode {
        case 36, 76:
            beginRename(node)
            return true
        case 51, 117:
            remove(node)
            return true
        default:
            return false
        }
    }

    func menu(forRow row: Int) -> NSMenu {
        let menu = NSMenu()
        let node = outlineView.item(atRow: row) as? SidebarNode
        func add(_ title: String, _ action: Selector, _ represented: Any? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = represented
            menu.addItem(item)
        }
        if let node {
            if node.kind == .folder {
                add("Open in New Tab", #selector(openInNewTab(_:)), node)
                add("Show in Finder", #selector(showInFinder(_:)), node)
                menu.addItem(.separator())
            }
            add(node.kind == .group ? "Rename Group" : "Rename", #selector(renameNode(_:)), node)
            if node.kind == .group {
                add("New Group Inside", #selector(newGroup(_:)), node)
                add("Add Folder…", #selector(addFolder(_:)), node)
            }
            menu.addItem(.separator())
            add(node.kind == .group ? "Remove Group" : "Remove from Sidebar", #selector(removeNode(_:)), node)
            menu.addItem(.separator())
        }
        add("New Group", #selector(newGroup(_:)))
        add("Add Folder…", #selector(addFolder(_:)))
        return menu
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(openInNewTab(_:)) || menuItem.action == #selector(showInFinder(_:)) {
            guard let node = menuItem.representedObject as? SidebarNode, let url = node.url else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }
        return true
    }

    @objc private func openInNewTab(_ sender: NSMenuItem) {
        guard let url = (sender.representedObject as? SidebarNode)?.url else { return }
        delegate?.sidebar(self, open: url, newTab: true)
    }

    @objc private func showInFinder(_ sender: NSMenuItem) {
        guard let url = (sender.representedObject as? SidebarNode)?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func renameNode(_ sender: NSMenuItem) {
        guard let node = sender.representedObject as? SidebarNode else { return }
        beginRename(node)
    }

    @objc private func removeNode(_ sender: NSMenuItem) {
        guard let node = sender.representedObject as? SidebarNode else { return }
        remove(node)
    }

    @objc private func newGroup(_ sender: Any?) {
        let parent = (sender as? NSMenuItem)?.representedObject as? SidebarNode
        let group = SidebarNode.group("New Group")
        tree.insert(group, into: parent)
        parent?.isCollapsed = false
        save()
        beginRename(group)
    }

    @objc private func addFolder(_ sender: NSMenuItem) {
        let parent = (sender.representedObject as? SidebarNode) ?? tree.nodes.last { $0.kind == .group }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls {
                self.tree.insert(self.tree.makeFolder(url), into: parent)
            }
            parent?.isCollapsed = false
            self.save()
        }
    }

    private func remove(_ node: SidebarNode) {
        if node.kind == .group && !node.children.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Remove the group “\(node.displayName)”?"
            alert.informativeText = "Its folders and groups will be removed from the sidebar. Nothing on disk is deleted."
            alert.addButton(withTitle: "Remove")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        tree.remove(node)
        save()
    }

    private func beginRename(_ node: SidebarNode) {
        let row = outlineView.row(forItem: node)
        guard row >= 0, let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView, let label = cell.textField else { return }
        outlineView.scrollRowToVisible(row)
        var frame = outlineView.convert(label.frame, from: cell).insetBy(dx: -2, dy: -2)
        frame.size.width = max(frame.width, outlineView.bounds.width - frame.minX - 8)
        renameField.font = label.font
        renameField.onCommit = { [weak self] name in
            guard let self else { return }
            if self.tree.rename(node, to: name) {
                self.save()
            }
        }
        renameField.onCancel = nil
        renameField.begin(in: outlineView, frame: frame, text: node.displayName)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        tree.children(of: item as? SidebarNode).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        tree.children(of: item as? SidebarNode)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? SidebarNode)?.kind == .group
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? SidebarNode)?.kind == .folder
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !reloading, let node = notification.userInfo?["NSObject"] as? SidebarNode else { return }
        node.isCollapsed = false
        expandNodes(node.children)
        updateChevron(node)
        persistCollapse()
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !reloading, let node = notification.userInfo?["NSObject"] as? SidebarNode else { return }
        node.isCollapsed = true
        updateChevron(node)
        persistCollapse()
    }

    private func updateChevron(_ node: SidebarNode) {
        let row = outlineView.row(forItem: node)
        guard row >= 0, let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView else { return }
        cell.imageView?.image = chevron(collapsed: node.isCollapsed)
    }

    private func chevron(collapsed: Bool) -> NSImage? {
        NSImage(systemSymbolName: collapsed ? "chevron.right" : "chevron.down", accessibilityDescription: nil)
    }

    private func persistCollapse() {
        NotificationCenter.default.removeObserver(self, name: .sidebarChanged, object: nil)
        state.sidebarDidChange()
        NotificationCenter.default.addObserver(self, selector: #selector(sidebarChanged), name: .sidebarChanged, object: nil)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }
        let id = NSUserInterfaceItemIdentifier(node.kind == .group ? "group" : "folder")
        let cell = (outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? makeCell(id, group: node.kind == .group)
        cell.textField?.stringValue = node.displayName
        if node.kind == .group {
            cell.imageView?.image = chevron(collapsed: node.isCollapsed)
        } else {
            let exists = node.url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            cell.imageView?.image = NSImage(systemSymbolName: exists ? "folder" : "exclamationmark.triangle", accessibilityDescription: nil)
            cell.imageView?.contentTintColor = exists ? .secondaryLabelColor : .systemOrange
            cell.toolTip = node.url?.path
            cell.alphaValue = exists ? 1 : 0.6
        }
        return cell
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier, group: Bool) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        cell.addSubview(label)
        cell.textField = label
        let image = NSImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(image)
        cell.imageView = image
        if group {
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .tertiaryLabelColor
            image.symbolConfiguration = .init(pointSize: 8, weight: .semibold)
            image.contentTintColor = .tertiaryLabelColor
            label.setContentHuggingPriority(.required, for: .horizontal)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -16),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 5),
                image.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor, constant: 1),
            ])
        } else {
            label.font = .systemFont(ofSize: 13)
            image.symbolConfiguration = .init(pointSize: 13, weight: .regular)
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 18),
                label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 7),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let row = RoundedRowView()
        row.horizontalInset = 8
        return row
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString("node", forType: SidebarController.nodeType)
        return pasteboardItem
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
        draggedNodes = draggedItems.compactMap { $0 as? SidebarNode }
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        draggedNodes = []
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        let target = item as? SidebarNode
        if info.draggingPasteboard.types?.contains(SidebarController.nodeType) == true {
            guard !draggedNodes.isEmpty else { return [] }
            if let target, target.kind == .folder {
                let parent = target.parent === tree.root ? nil : target.parent
                let position = tree.children(of: parent).firstIndex { $0 === target } ?? 0
                outlineView.setDropItem(parent, dropChildIndex: position)
                return draggedNodes.contains { $0 === parent || (parent?.isDescendant(of: $0) ?? false) } ? [] : .move
            }
            if draggedNodes.contains(where: { $0 === target || (target?.isDescendant(of: $0) ?? false) }) {
                return []
            }
            return .move
        }
        let urls = DragSupport.urls(from: info)
        guard !urls.isEmpty else { return [] }
        if let target, target.kind == .folder, index == NSOutlineViewDropOnItemIndex, let url = target.url {
            return DragSupport.operation(for: info, to: url)
        }
        if let target, target.kind == .folder {
            let parent = target.parent === tree.root ? nil : target.parent
            let position = tree.children(of: parent).firstIndex { $0 === target }.map { $0 + (index > 0 ? 1 : 0) } ?? 0
            outlineView.setDropItem(parent, dropChildIndex: position)
        }
        return urls.contains(where: SidebarController.isFolder) ? .link : []
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let target = item as? SidebarNode
        if info.draggingPasteboard.types?.contains(SidebarController.nodeType) == true {
            var position = index == NSOutlineViewDropOnItemIndex ? tree.children(of: target).count : index
            for node in draggedNodes {
                let before = tree.children(of: target).firstIndex { $0 === node }
                guard tree.move(node, into: target, at: position) else { continue }
                if before == nil || before! >= position { position += 1 }
            }
            target?.isCollapsed = false
            save()
            return true
        }
        let urls = DragSupport.urls(from: info)
        if let target, target.kind == .folder, index == NSOutlineViewDropOnItemIndex, let url = target.url {
            let operation = DragSupport.operation(for: info, to: url)
            guard !operation.isEmpty else { return false }
            FileActions.transfer(urls, to: url, copy: operation == .copy)
            return true
        }
        let folders = urls.filter(SidebarController.isFolder)
        guard !folders.isEmpty else { return false }
        var position = index == NSOutlineViewDropOnItemIndex ? tree.children(of: target).count : index
        for url in folders {
            tree.insert(tree.makeFolder(url), into: target, at: position)
            position += 1
        }
        target?.isCollapsed = false
        save()
        return true
    }
}
