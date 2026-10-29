import AppKit

final class ColumnTableView: NSTableView {
    weak var browser: ColumnBrowser?

    override func keyDown(with event: NSEvent) {
        if browser?.handleKey(event, in: self) == true { return }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 && !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if row < 0 {
            deselectAll(nil)
        }
        window?.makeFirstResponder(self)
        return browser?.contextMenu(for: self)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        browser?.columnBecameActive(self)
        return result
    }
}

final class ColumnBrowser: NSViewController, FileBrowser, NSTableViewDataSource, NSTableViewDelegate {
    private final class Column {
        let path: String
        let model: DirectoryModel?
        let table = ColumnTableView()
        let scroll = NSScrollView()

        init(path: String, model: DirectoryModel?) {
            self.path = path
            self.model = model
        }
    }

    static let columnWidth: CGFloat = 240

    weak var host: FileBrowserHost?
    private let scrollView = NSScrollView()
    private let document = FlippedView()
    private var columnViews: [NSView] = []
    private var dividers: [FillView] = []
    private var columns: [Column] = []
    private var previewView: NSView?
    private var activeIndex = 0
    private var applyingSelection = false
    private let renameField = RenameField.make()

    override func loadView() {
        scrollView.documentView = document
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        view = scrollView
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutColumns()
    }

    var browseDirectory: URL? {
        columns.indices.contains(activeIndex) ? columns[activeIndex].path.fileURL : nil
    }

    var selectedItems: [FileItem] {
        guard columns.indices.contains(activeIndex) else { return [] }
        return selected(in: columns[activeIndex])
    }

    func reload(_ change: DirectoryModel.Change) {
        guard let host else { return }
        if case .children = change { return }
        if columns.first?.path != host.model.path {
            truncate(after: -1)
            let column = makeColumn(path: host.model.path, model: nil)
            columns.append(column)
            addArranged(column.scroll)
            activeIndex = 0
        }
        guard let first = columns.first else { return }
        let selected = Set(self.selected(in: first).map(\.path))
        first.table.reloadData()
        restore(selected, in: first)
    }

    func select(paths: Set<String>, scroll: Bool) {
        guard columns.indices.contains(activeIndex) else { return }
        let column = columns[activeIndex]
        restore(paths, in: column)
        if scroll, let row = column.table.selectedRowIndexes.first {
            column.table.scrollRowToVisible(row)
        }
        selectionChanged(in: column)
    }

    func focus() {
        guard columns.indices.contains(activeIndex) else { return }
        view.window?.makeFirstResponder(columns[activeIndex].table)
    }

    func beginRename(path: String) {
        select(paths: [path], scroll: true)
        guard columns.indices.contains(activeIndex) else { return }
        let column = columns[activeIndex]
        guard let row = column.table.selectedRowIndexes.first, let cell = column.table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView, let label = cell.textField else { return }
        let item = items(in: column)[row]
        renameField.font = label.font
        renameField.onCommit = { [weak self] name in
            self?.host?.rename(item, to: name)
            self?.focus()
        }
        renameField.onCancel = { [weak self] in self?.focus() }
        renameField.begin(in: column.table, frame: column.table.convert(label.frame, from: cell).insetBy(dx: -2, dy: -1), text: item.name)
    }

    func handleKey(_ event: NSEvent, in table: ColumnTableView) -> Bool {
        guard let index = columns.firstIndex(where: { $0.table === table }), let combo = KeyCombo(event: event) else { return false }
        switch Shortcuts.action(for: combo, in: .columns) {
        case .nextColumn:
            if index + 1 < columns.count {
                let next = columns[index + 1]
                if next.table.selectedRowIndexes.isEmpty && next.table.numberOfRows > 0 {
                    next.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                }
                view.window?.makeFirstResponder(next.table)
            }
            return true
        case .previousColumn:
            if index > 0 {
                view.window?.makeFirstResponder(columns[index - 1].table)
                truncate(after: index - 1)
                selectionChanged(in: columns[index - 1])
            }
            return true
        default:
            break
        }
        switch Shortcuts.action(for: combo, in: .browsing) {
        case .renameItem:
            if selectedItems.count == 1, let item = selectedItems.first {
                beginRename(path: item.path)
                return true
            }
        case .previewItem:
            host?.toggleQuickLook()
            return true
        case .nextPane:
            host?.focusNextPane()
            return true
        case .openItem:
            host?.open(selectedItems)
            return true
        default:
            break
        }
        return false
    }

    func contextMenu(for table: ColumnTableView) -> NSMenu? {
        guard let index = columns.firstIndex(where: { $0.table === table }) else { return nil }
        activeIndex = index
        return host?.menu(for: selected(in: columns[index]), in: columns[index].path.fileURL)
    }

    func columnBecameActive(_ table: ColumnTableView) {
        guard let index = columns.firstIndex(where: { $0.table === table }) else { return }
        host?.browserDidBecomeActive()
        if activeIndex != index {
            activeIndex = index
            host?.browseDirectoryChanged()
        }
    }

    private func items(in column: Column) -> [FileItem] {
        (column.model ?? host?.model)?.items ?? []
    }

    private func selected(in column: Column) -> [FileItem] {
        let items = items(in: column)
        return column.table.selectedRowIndexes.compactMap { items.indices.contains($0) ? items[$0] : nil }
    }

    private func restore(_ paths: Set<String>, in column: Column) {
        guard !paths.isEmpty else { return }
        applyingSelection = true
        let items = items(in: column)
        let names = Set(paths.map { ($0 as NSString).lastPathComponent })
        column.table.selectRowIndexes(DirectoryListing.indexes(of: names, in: items), byExtendingSelection: false)
        applyingSelection = false
    }

    private func makeColumn(path: String, model: DirectoryModel?) -> Column {
        let column = Column(path: path, model: model)
        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        tableColumn.width = ColumnBrowser.columnWidth - 5
        column.table.addTableColumn(tableColumn)
        column.table.headerView = nil
        column.table.browser = self
        column.table.rowHeight = 26
        column.table.style = .plain
        column.table.backgroundColor = .clear
        column.table.allowsMultipleSelection = true
        column.table.dataSource = self
        column.table.delegate = self
        column.table.target = self
        column.table.doubleAction = #selector(doubleClicked(_:))
        column.table.registerForDraggedTypes(DragSupport.types)
        column.table.setDraggingSourceOperationMask([.copy, .move, .link, .generic], forLocal: false)
        column.table.setDraggingSourceOperationMask([.copy, .move, .link, .generic], forLocal: true)
        column.scroll.documentView = column.table
        column.scroll.hasVerticalScroller = true
        column.scroll.autohidesScrollers = true
        column.scroll.drawsBackground = false
        if let model {
            model.onChange = { [weak self, weak column] _ in
                guard let self, let column else { return }
                let selected = Set(self.selected(in: column).map(\.path))
                column.table.reloadData()
                self.restore(selected, in: column)
            }
            model.start()
        }
        return column
    }

    private func addArranged(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = true
        document.addSubview(view)
        columnViews.append(view)
        layoutColumns()
    }

    private func layoutColumns() {
        let height = scrollView.contentSize.height
        let tables = columnViews.filter { $0 !== previewView }
        while dividers.count < tables.count {
            let divider = FillView()
            divider.color = Theme.divider
            document.addSubview(divider)
            dividers.append(divider)
        }
        while dividers.count > tables.count {
            dividers.removeLast().removeFromSuperview()
        }
        var x: CGFloat = 0
        var index = 0
        for view in columnViews {
            if view === previewView {
                let width = ColumnBrowser.columnWidth * 1.4
                view.frame = NSRect(x: x, y: 0, width: width, height: height)
                x += width
            } else {
                view.frame = NSRect(x: x, y: 0, width: ColumnBrowser.columnWidth - 1, height: height)
                dividers[index].frame = NSRect(x: x + ColumnBrowser.columnWidth - 1, y: 0, width: 1, height: height)
                index += 1
                x += ColumnBrowser.columnWidth
            }
        }
        document.frame = NSRect(x: 0, y: 0, width: max(x, scrollView.contentSize.width), height: height)
    }

    private func truncate(after index: Int) {
        while columns.count > index + 1 {
            let column = columns.removeLast()
            column.model?.stop()
            column.scroll.removeFromSuperview()
            columnViews.removeAll { $0 === column.scroll }
        }
        if let previewView {
            previewView.removeFromSuperview()
            columnViews.removeAll { $0 === previewView }
        }
        previewView = nil
        layoutColumns()
        activeIndex = min(activeIndex, max(columns.count - 1, 0))
    }

    private func selectionChanged(in column: Column) {
        guard let index = columns.firstIndex(where: { $0 === column }) else { return }
        activeIndex = index
        truncate(after: index)
        let selected = selected(in: column)
        if selected.count == 1, let item = selected.first {
            if item.isFolder {
                let model = DirectoryModel(path: item.path, view: host?.folderView ?? .standard, visibility: AppState.shared.visibility)
                let next = makeColumn(path: item.path, model: model)
                columns.append(next)
                addArranged(next.scroll)
            } else {
                let preview = PreviewView(frame: NSRect(x: 0, y: 0, width: ColumnBrowser.columnWidth * 1.4, height: scrollView.contentSize.height))
                previewView = preview
                preview.show(item)
                addArranged(preview)
            }
            DispatchQueue.main.async { [weak self] in self?.scrollToEnd() }
        }
        host?.browseDirectoryChanged()
        host?.browserSelectionChanged()
    }

    private func scrollToEnd() {
        layoutColumns()
        let x = max(document.frame.width - scrollView.contentView.bounds.width, 0)
        scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: x, y: 0))
    }

    private func column(for table: NSTableView) -> Column? {
        columns.first { $0.table === table }
    }

    @objc private func doubleClicked(_ sender: NSTableView) {
        guard sender.clickedRow >= 0, let column = column(for: sender) else { return }
        let items = selected(in: column)
        if items.count == 1, items[0].isFolder {
            host?.open(items)
        } else {
            host?.open(items.filter { !$0.isFolder })
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        column(for: tableView).map { items(in: $0).count } ?? 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = column(for: tableView) else { return nil }
        let items = items(in: column)
        guard items.indices.contains(row) else { return nil }
        let item = items[row]
        let id = NSUserInterfaceItemIdentifier("ColumnCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? ColumnCell) ?? ColumnCell(identifier: id)
        cell.textField?.stringValue = item.name
        cell.imageView?.image = IconCache.shared.icon(for: item)
        cell.chevron.isHidden = !item.isFolder
        cell.alphaValue = item.isHidden ? 0.5 : 1
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        RoundedRowView()
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        guard let column = column(for: tableView) else { return nil }
        let items = items(in: column)
        return items.indices.contains(row) ? items[row].name : nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !applyingSelection, let table = notification.object as? NSTableView, let column = column(for: table) else { return }
        selectionChanged(in: column)
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let column = column(for: tableView) else { return nil }
        let items = items(in: column)
        return items.indices.contains(row) ? items[row].url as NSURL : nil
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard let column = column(for: tableView) else { return [] }
        let items = items(in: column)
        if dropOperation == .on, items.indices.contains(row), items[row].isFolder {
            return DragSupport.operation(for: info, to: items[row].url)
        }
        tableView.setDropRow(-1, dropOperation: .on)
        return DragSupport.operation(for: info, to: column.path.fileURL)
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let column = column(for: tableView) else { return false }
        let items = items(in: column)
        let directory = dropOperation == .on && items.indices.contains(row) && items[row].isFolder ? items[row].url : column.path.fileURL
        let operation = DragSupport.operation(for: info, to: directory)
        guard !operation.isEmpty else { return false }
        return host?.drop(DragSupport.urls(from: info), into: directory, operation: operation) ?? false
    }
}

final class ColumnCell: NSTableCellView {
    let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage())

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        let image = NSImageView()
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingMiddle
        label.textColor = Theme.text
        chevron.contentTintColor = Theme.icon
        chevron.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
        for view in [image, label, chevron] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        imageView = image
        textField = label
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            image.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 4),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
