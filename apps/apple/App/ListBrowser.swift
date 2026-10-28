import AppKit

final class FileOutlineView: NSOutlineView {
    weak var browser: ListBrowser?

    override func keyDown(with event: NSEvent) {
        if browser?.handleKey(event) == true { return }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 && !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if row < 0 {
            deselectAll(nil)
        }
        return browser?.contextMenu()
    }

    override func becomeFirstResponder() -> Bool {
        browser?.host?.browserDidBecomeActive()
        return super.becomeFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        browser?.host?.browserDidBecomeActive()
        super.mouseDown(with: event)
    }
}

final class ListBrowser: NSViewController, FileBrowser, NSOutlineViewDataSource, NSOutlineViewDelegate {
    struct Column {
        let id: String
        let title: String
        let sort: SortKey
        let width: CGFloat
        let alignment: NSTextAlignment
        let hiddenByDefault: Bool
    }

    static let columns: [Column] = [
        Column(id: "name", title: "Name", sort: .name, width: 320, alignment: .left, hiddenByDefault: false),
        Column(id: "modified", title: "Date Modified", sort: .modified, width: 170, alignment: .left, hiddenByDefault: false),
        Column(id: "added", title: "Date Added", sort: .added, width: 170, alignment: .left, hiddenByDefault: true),
        Column(id: "created", title: "Date Created", sort: .created, width: 170, alignment: .left, hiddenByDefault: true),
        Column(id: "size", title: "Size", sort: .size, width: 80, alignment: .right, hiddenByDefault: false),
        Column(id: "kind", title: "Kind", sort: .kind, width: 130, alignment: .left, hiddenByDefault: false),
    ]

    weak var host: FileBrowserHost?
    let outlineView = FileOutlineView()
    private let scrollView = NSScrollView()
    private let renameField = RenameField.make()
    private var applyingSelection = false
    private var applyingColumns = false

    private var items: [FileItem] = []

    override func loadView() {
        outlineView.browser = self
        outlineView.headerView = QuietHeaderView(frame: NSRect(x: 0, y: 0, width: 0, height: 30))
        outlineView.allowsMultipleSelection = true
        outlineView.allowsColumnReordering = true
        outlineView.allowsColumnResizing = true
        outlineView.columnAutoresizingStyle = .noColumnAutoresizing
        outlineView.style = .plain
        outlineView.backgroundColor = .clear
        outlineView.gridStyleMask = []
        outlineView.rowHeight = 28
        outlineView.intercellSpacing = NSSize(width: 6, height: 0)
        outlineView.autoresizesOutlineColumn = false
        outlineView.indentationPerLevel = 14
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(doubleClicked)
        outlineView.registerForDraggedTypes(DragSupport.types)
        outlineView.setDraggingSourceOperationMask([.copy, .move, .link, .generic], forLocal: false)
        outlineView.setDraggingSourceOperationMask([.copy, .move, .link, .generic], forLocal: true)
        outlineView.draggingDestinationFeedbackStyle = .regular

        for spec in ListBrowser.columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.id))
            column.title = spec.title
            column.width = spec.width
            column.minWidth = spec.id == "name" ? 120 : 50
            column.headerCell.alignment = spec.alignment
            column.sortDescriptorPrototype = NSSortDescriptor(key: spec.sort.rawValue, ascending: spec.sort.defaultAscending)
            outlineView.addTableColumn(column)
            if spec.id == "name" { outlineView.outlineTableColumn = column }
        }
        let headerMenu = NSMenu()
        for spec in ListBrowser.columns where spec.id != "name" {
            let item = NSMenuItem(title: spec.title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
            item.representedObject = spec.id
            item.target = self
            headerMenu.addItem(item)
        }
        outlineView.headerView?.menu = headerMenu
        applyColumnState()

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        view = scrollView

        NotificationCenter.default.addObserver(self, selector: #selector(columnsChanged), name: .listColumnsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(columnGeometryChanged), name: NSTableView.columnDidResizeNotification, object: outlineView)
        NotificationCenter.default.addObserver(self, selector: #selector(columnGeometryChanged), name: NSTableView.columnDidMoveNotification, object: outlineView)
    }

    var selectedItems: [FileItem] {
        outlineView.selectedRowIndexes.compactMap { outlineView.item(atRow: $0) as? FileItem }
    }

    func reload(_ change: DirectoryModel.Change) {
        switch change {
        case .children(let item):
            let selected = Set(selectedItems.map(\.path))
            outlineView.reloadItem(item, reloadChildren: true)
            restoreSelection(selected)
        case .loaded:
            items = host?.model.items ?? []
            outlineView.reloadData()
            updateSortIndicator()
            outlineView.scrollRowToVisible(0)
        case .refreshed:
            let selected = Set(selectedItems.map(\.path))
            items = host?.model.items ?? []
            outlineView.reloadData()
            updateSortIndicator()
            restoreSelection(selected)
        }
    }

    func select(paths: Set<String>, scroll: Bool) {
        restoreSelection(paths)
        if scroll, let first = outlineView.selectedRowIndexes.first {
            outlineView.scrollRowToVisible(first)
        }
    }

    func focus() {
        view.window?.makeFirstResponder(outlineView)
    }

    func viewDidChange() {
        updateSortIndicator()
    }

    func beginRename(path: String) {
        select(paths: [path], scroll: true)
        guard let row = outlineView.selectedRowIndexes.first, let item = outlineView.item(atRow: row) as? FileItem,
              let cell = outlineView.view(atColumn: outlineView.column(withIdentifier: NSUserInterfaceItemIdentifier("name")), row: row, makeIfNecessary: true) as? NSTableCellView,
              let label = cell.textField else { return }
        var frame = outlineView.convert(label.frame, from: cell)
        frame.size.width = max(frame.width, 120)
        frame = frame.insetBy(dx: -2, dy: -1)
        renameField.font = label.font
        renameField.onCommit = { [weak self] name in
            self?.host?.rename(item, to: name)
            self?.focus()
        }
        renameField.onCancel = { [weak self] in self?.focus() }
        renameField.begin(in: outlineView, frame: frame, text: item.name)
    }

    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 36, 76:
            if flags.isEmpty, selectedItems.count == 1, let item = selectedItems.first {
                beginRename(path: item.path)
                return true
            }
        case 49:
            host?.toggleQuickLook()
            return true
        case 48:
            if flags.isEmpty {
                host?.focusNextPane()
                return true
            }
        case 125:
            if flags.contains(.command) {
                host?.open(selectedItems)
                return true
            }
        default:
            break
        }
        return false
    }

    func contextMenu() -> NSMenu? {
        host?.menu(for: selectedItems, in: host?.model.path.fileURL ?? URL(filePath: "/"))
    }

    @objc private func doubleClicked() {
        guard outlineView.clickedRow >= 0 else { return }
        host?.open(selectedItems)
    }

    private func restoreSelection(_ paths: Set<String>) {
        guard !paths.isEmpty else { return }
        applyingSelection = true
        var indexes = IndexSet()
        if paths.count == 1, let path = paths.first {
            let row = row(forPath: path)
            if row >= 0 { indexes.insert(row) }
        } else {
            for row in 0..<outlineView.numberOfRows {
                if let item = outlineView.item(atRow: row) as? FileItem, paths.contains(item.path) {
                    indexes.insert(row)
                }
            }
        }
        outlineView.selectRowIndexes(indexes, byExtendingSelection: false)
        applyingSelection = false
        host?.browserSelectionChanged()
    }

    private func row(forPath path: String) -> Int {
        let parent = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        if parent == host?.model.path, let index = items.firstIndex(where: { $0.name == name }) {
            return outlineView.row(forItem: items[index])
        }
        for row in 0..<outlineView.numberOfRows {
            if let item = outlineView.item(atRow: row) as? FileItem, item.path == path { return row }
        }
        return -1
    }

    private func updateSortIndicator() {
        guard let view = host?.folderView else { return }
        let descriptor = NSSortDescriptor(key: view.sort.rawValue, ascending: view.ascending)
        if outlineView.sortDescriptors.first != descriptor {
            outlineView.sortDescriptors = [descriptor]
        }
        for column in outlineView.tableColumns {
            let active = column.sortDescriptorPrototype?.key == view.sort.rawValue
            outlineView.setIndicatorImage(active ? NSImage(named: view.ascending ? "NSAscendingSortIndicator" : "NSDescendingSortIndicator") : nil, in: column)
        }
        outlineView.highlightedTableColumn = outlineView.tableColumns.first { $0.sortDescriptorPrototype?.key == view.sort.rawValue }
    }

    private func applyColumnState() {
        applyingColumns = true
        let saved = AppState.shared.listColumns
        if !saved.isEmpty {
            var position = 0
            var seen = Set<String>()
            for state in saved where seen.insert(state.id).inserted {
                let current = outlineView.column(withIdentifier: NSUserInterfaceItemIdentifier(state.id))
                guard current >= 0, let column = outlineView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(state.id)) else { continue }
                if current != position {
                    outlineView.moveColumn(current, toColumn: position)
                }
                position += 1
                column.width = max(state.width, column.minWidth)
                column.isHidden = state.id != "name" && state.hidden
            }
        } else {
            for spec in ListBrowser.columns {
                outlineView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(spec.id))?.isHidden = spec.hiddenByDefault
            }
        }
        for item in outlineView.headerView?.menu?.items ?? [] {
            let id = item.representedObject as? String ?? ""
            item.state = outlineView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(id))?.isHidden == false ? .on : .off
        }
        applyingColumns = false
    }

    private func saveColumnState() {
        AppState.shared.listColumns = outlineView.tableColumns.map {
            SessionState.Column(id: $0.identifier.rawValue, width: $0.width, hidden: $0.isHidden)
        }
        NotificationCenter.default.post(name: .listColumnsChanged, object: self)
    }

    @objc private func toggleColumn(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let column = outlineView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(id)) else { return }
        column.isHidden.toggle()
        sender.state = column.isHidden ? .off : .on
        saveColumnState()
    }

    @objc private func columnsChanged(_ notification: Notification) {
        guard notification.object as? ListBrowser !== self else { return }
        applyColumnState()
    }

    @objc private func columnGeometryChanged(_ notification: Notification) {
        guard !applyingColumns else { return }
        saveColumnState()
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item = item as? FileItem else { return items.count }
        return item.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let item = item as? FileItem else { return items[index] }
        return item.children?[index] ?? item
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileItem)?.isFolder ?? false
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let item = notification.userInfo?["NSObject"] as? FileItem else { return }
        host?.model.expand(item)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let item = notification.userInfo?["NSObject"] as? FileItem else { return }
        host?.model.collapse(item)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? FileItem, let tableColumn else { return nil }
        let id = tableColumn.identifier
        if id.rawValue == "name" {
            let cell = (outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? makeNameCell(id)
            cell.textField?.stringValue = item.name
            cell.imageView?.image = IconCache.shared.icon(for: item)
            cell.alphaValue = item.isHidden || isCut(item) ? 0.5 : 1
            return cell
        }
        let cell = (outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? makeTextCell(id, alignment: tableColumn.headerCell.alignment)
        let text: String
        switch id.rawValue {
        case "modified": text = FileFormat.date(item.modified)
        case "added": text = FileFormat.date(item.added)
        case "created": text = FileFormat.date(item.created)
        case "size": text = FileFormat.size(item)
        default: text = item.kind
        }
        cell.textField?.stringValue = text
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        RoundedRowView()
    }

    func outlineView(_ outlineView: NSOutlineView, typeSelectStringFor tableColumn: NSTableColumn?, item: Any) -> String? {
        tableColumn?.identifier.rawValue == "name" ? (item as? FileItem)?.name : nil
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !applyingSelection else { return }
        host?.browserSelectionChanged()
    }

    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = outlineView.sortDescriptors.first, let key = descriptor.key.flatMap(SortKey.init(rawValue:)) else { return }
        guard key != host?.folderView.sort || descriptor.ascending != host?.folderView.ascending else { return }
        host?.setSort(key, ascending: descriptor.ascending)
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        (item as? FileItem)?.url as NSURL?
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        if let folder = item as? FileItem, folder.isFolder {
            outlineView.setDropItem(folder, dropChildIndex: NSOutlineViewDropOnItemIndex)
            return DragSupport.operation(for: info, to: folder.url)
        }
        let parent = (item as? FileItem).flatMap { target -> FileItem? in
            outlineView.parent(forItem: target) as? FileItem
        }
        outlineView.setDropItem(parent, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return DragSupport.operation(for: info, to: parent?.url ?? URL(filePath: host?.model.path ?? "/", directoryHint: .isDirectory))
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let directory = (item as? FileItem)?.url ?? URL(filePath: host?.model.path ?? "/", directoryHint: .isDirectory)
        let operation = DragSupport.operation(for: info, to: directory)
        guard !operation.isEmpty else { return false }
        return host?.drop(DragSupport.urls(from: info), into: directory, operation: operation) ?? false
    }

    private func isCut(_ item: FileItem) -> Bool {
        let cut = AppState.shared.cutURLs
        return !cut.isEmpty && cut.contains { $0.path == item.path }
    }

    private func makeNameCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let image = NSImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        image.imageScaling = .scaleProportionallyUpOrDown
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingMiddle
        label.cell?.truncatesLastVisibleLine = true
        cell.addSubview(image)
        cell.addSubview(label)
        cell.imageView = image
        cell.textField = label
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            image.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makeTextCell(_ id: NSUserInterfaceItemIdentifier, alignment: NSTextAlignment) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

extension String {
    var fileURL: URL { URL(filePath: self, directoryHint: .isDirectory) }
}
