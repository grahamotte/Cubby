import AppKit

final class BulkRenameRow: NSTableCellView {
    private let original = NSTextField(labelWithString: "")
    private let arrow = NSImageView()
    private let renamed = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        original.font = .systemFont(ofSize: 12)
        original.lineBreakMode = .byTruncatingMiddle
        renamed.font = .systemFont(ofSize: 12)
        renamed.lineBreakMode = .byTruncatingMiddle
        arrow.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)
        arrow.symbolConfiguration = .init(pointSize: 10, weight: .medium)
        for view in [original, arrow, renamed] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            original.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            original.centerYAnchor.constraint(equalTo: centerYAnchor),
            original.trailingAnchor.constraint(lessThanOrEqualTo: arrow.leadingAnchor, constant: -8),
            arrow.centerXAnchor.constraint(equalTo: centerXAnchor),
            arrow.centerYAnchor.constraint(equalTo: centerYAnchor),
            renamed.leadingAnchor.constraint(equalTo: arrow.trailingAnchor, constant: 8),
            renamed.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            renamed.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func show(_ row: BulkRename.Row) {
        original.stringValue = row.url.lastPathComponent
        original.textColor = Theme.secondaryText
        original.toolTip = row.url.path
        arrow.contentTintColor = row.problem != nil ? Theme.warning : row.changed ? Theme.icon : Theme.tertiaryText
        renamed.stringValue = row.name
        renamed.textColor = row.problem != nil ? Theme.warning : row.changed ? Theme.text : Theme.tertiaryText
        renamed.toolTip = row.problem ?? row.name
    }
}

final class BulkRenameController: NSViewController, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let title = "Rename Items"

    private let items: [BulkRename.Item]
    private let onRename: ([Transfer]) -> Void
    private var rename = BulkRename()
    private var rows: [BulkRename.Row] = []
    private let findField = BulkRenameController.field("Text to find")
    private let replaceField = BulkRenameController.field("Replace with")
    private let prefixField = BulkRenameController.field("Add before")
    private let suffixField = BulkRenameController.field("Add after")
    private let removeFirstField = BulkRenameController.field("0")
    private let removeLastField = BulkRenameController.field("0")
    private let startField = BulkRenameController.field("1")
    private let separatorField = BulkRenameController.field("")
    private let numberingPopup = BulkRenameController.popup(BulkRename.Numbering.allCases.map(\.title))
    private let casePopup = BulkRenameController.popup(BulkRename.LetterCase.allCases.map(\.title))
    private let regexSwitch = ThemedSwitch()
    private let tableView = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private let renameButton = ThemedButton(title: "Rename", target: nil, action: nil)
    private let cancelButton = ThemedButton(title: "Cancel", target: nil, action: nil)

    init(items: [BulkRename.Item], onRename: @escaping ([Transfer]) -> Void) {
        self.items = items
        self.onRename = onRename
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    private static func field(_ placeholder: String) -> ThemedField {
        let field = ThemedField()
        field.placeholderString = placeholder
        return field
    }

    private static func popup(_ titles: [String]) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.isBordered = false
        popup.font = .systemFont(ofSize: 13)
        popup.contentTintColor = Theme.secondaryText
        popup.addItems(withTitles: titles)
        return popup
    }

    private static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = Theme.secondaryText
        label.alignment = .right
        return label
    }

    override func loadView() {
        separatorField.stringValue = rename.separator
        startField.stringValue = String(rename.start)
        for field in [findField, replaceField, prefixField, suffixField, removeFirstField, removeLastField, startField, separatorField] {
            field.delegate = self
        }
        for field in [removeFirstField, removeLastField, startField] {
            field.alignment = .right
        }
        for popup in [numberingPopup, casePopup] {
            popup.target = self
            popup.action = #selector(optionsChanged(_:))
        }
        regexSwitch.target = self
        regexSwitch.action = #selector(optionsChanged(_:))
        regexSwitch.setAccessibilityLabel("Regular Expression")

        let header = NSTextField(labelWithString: "Rename \(items.count.formatted()) Items")
        header.font = .systemFont(ofSize: 13, weight: .semibold)
        header.textColor = Theme.text

        let regexLabel = NSTextField(labelWithString: "Regular expression")
        regexLabel.font = .systemFont(ofSize: 12)
        regexLabel.textColor = Theme.secondaryText
        let regexRow = NSStackView(views: [regexSwitch, regexLabel])
        regexRow.spacing = 8

        let numbers = NSStackView(views: [Self.label("Start"), startField, Self.label("Separator"), separatorField])
        numbers.spacing = 8
        let removes = NSStackView(views: [removeFirstField, Self.label("Remove Last"), removeLastField])
        removes.spacing = 8

        let grid = NSGridView(views: [
            [Self.label("Find"), findField],
            [Self.label("Replace"), replaceField],
            [NSGridCell.emptyContentView, regexRow],
            [Self.label("Add Before"), prefixField],
            [Self.label("Add After"), suffixField],
            [Self.label("Remove First"), removes],
            [Self.label("Number"), numberingPopup],
            [NSGridCell.emptyContentView, numbers],
            [Self.label("Case"), casePopup],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        for index in 0..<grid.numberOfRows {
            grid.row(at: index).yPlacement = .center
        }
        grid.row(at: 2).topPadding = -2
        grid.row(at: 3).topPadding = 8
        grid.row(at: 6).topPadding = 8
        grid.row(at: 8).topPadding = 8
        grid.translatesAutoresizingMaskIntoConstraints = false

        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(grid)

        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.selectionHighlightStyle = .none
        tableView.intercellSpacing = .zero
        tableView.rowHeight = 24
        tableView.gridStyleMask = []
        tableView.focusRingType = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row")))
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let preview = CardView()
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.addSubview(scroll)

        status.font = .systemFont(ofSize: 12)
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cancelButton.isBordered = false
        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))
        cancelButton.keyEquivalent = "\u{1b}"
        renameButton.isBordered = false
        renameButton.isPrimary = true
        renameButton.target = self
        renameButton.action = #selector(commit(_:))
        renameButton.keyEquivalent = "\r"

        let root = FillView()
        root.color = Theme.content
        for view in [header, card, preview, status, cancelButton, renameButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 560),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            card.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            grid.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            grid.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            grid.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            findField.widthAnchor.constraint(equalToConstant: 400),
            replaceField.widthAnchor.constraint(equalTo: findField.widthAnchor),
            prefixField.widthAnchor.constraint(equalTo: findField.widthAnchor),
            suffixField.widthAnchor.constraint(equalTo: findField.widthAnchor),
            removeFirstField.widthAnchor.constraint(equalToConstant: 56),
            removeLastField.widthAnchor.constraint(equalToConstant: 56),
            startField.widthAnchor.constraint(equalToConstant: 56),
            separatorField.widthAnchor.constraint(equalToConstant: 56),
            preview.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 12),
            preview.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            preview.heightAnchor.constraint(equalToConstant: CGFloat(min(max(items.count, 3), 8)) * tableView.rowHeight + 12),
            scroll.topAnchor.constraint(equalTo: preview.topAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: preview.bottomAnchor, constant: -6),
            scroll.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: 1),
            scroll.trailingAnchor.constraint(equalTo: preview.trailingAnchor, constant: -1),
            renameButton.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 16),
            renameButton.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            renameButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            cancelButton.centerYAnchor.constraint(equalTo: renameButton.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: renameButton.leadingAnchor, constant: -8),
            status.centerYAnchor.constraint(equalTo: renameButton.centerYAnchor),
            status.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 4),
            status.trailingAnchor.constraint(lessThanOrEqualTo: cancelButton.leadingAnchor, constant: -12),
        ])
        view = root
        update()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(findField)
    }

    func controlTextDidChange(_ notification: Notification) {
        update()
    }

    @objc private func optionsChanged(_ sender: Any?) {
        update()
    }

    private static func count(_ field: NSTextField) -> Int {
        max(Int(field.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0, 0)
    }

    private func update() {
        rename.find = findField.stringValue
        rename.replace = replaceField.stringValue
        rename.regex = regexSwitch.state == .on
        rename.prefix = prefixField.stringValue
        rename.suffix = suffixField.stringValue
        rename.removeFirst = Self.count(removeFirstField)
        rename.removeLast = Self.count(removeLastField)
        rename.numbering = BulkRename.Numbering.allCases[max(numberingPopup.indexOfSelectedItem, 0)]
        rename.start = Int(startField.stringValue.trimmingCharacters(in: .whitespaces)).map { max($0, 0) } ?? 1
        rename.separator = separatorField.stringValue
        rename.letterCase = BulkRename.LetterCase.allCases[max(casePopup.indexOfSelectedItem, 0)]
        let numbered = rename.numbering != .none
        startField.isEnabled = numbered
        separatorField.isEnabled = numbered
        startField.alphaValue = numbered ? 1 : 0.5
        separatorField.alphaValue = numbered ? 1 : 0.5
        rows = rename.plan(items)
        tableView.reloadData()
        let changed = rows.filter(\.changed).count
        let problems = rows.filter { $0.problem != nil }
        if let error = rename.regexError {
            status.stringValue = error
            status.textColor = Theme.warning
        } else if let first = problems.first {
            status.stringValue = problems.count == 1 ? "“\(first.name)”: \(first.problem ?? "")" : "\(problems.count.formatted()) names have problems."
            status.textColor = Theme.warning
        } else {
            status.stringValue = changed == 0 ? "No names change yet." : changed == 1 ? "1 name changes." : "\(changed.formatted()) names change."
            status.textColor = Theme.secondaryText
        }
        renameButton.isEnabled = changed > 0 && problems.isEmpty && rename.regexError == nil
    }

    @objc private func cancel(_ sender: Any?) {
        close()
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    @objc private func commit(_ sender: Any?) {
        guard renameButton.isEnabled else { return }
        let renames = rows.filter(\.changed).map { Transfer(source: $0.url, destination: $0.url.deletingLastPathComponent().appending(path: $0.name)) }
        close()
        onRename(renames)
    }

    private func close() {
        guard let window = view.window else { return }
        window.sheetParent?.endSheet(window)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("BulkRenameRow")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? BulkRenameRow ?? {
            let cell = BulkRenameRow()
            cell.identifier = identifier
            return cell
        }()
        cell.show(rows[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        false
    }

    static func present(_ items: [BulkRename.Item], for window: NSWindow, onRename: @escaping ([Transfer]) -> Void) {
        let controller = BulkRenameController(items: items, onRename: onRename)
        let sheet = NSWindow(contentViewController: controller)
        sheet.styleMask = [.titled]
        sheet.title = title
        window.beginSheet(sheet)
    }
}
