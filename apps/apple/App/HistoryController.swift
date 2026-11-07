import AppKit

final class HistoryRow: NSTableCellView {
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let undoButton = NSButton(title: "Undo", target: nil, action: nil)
    private var titleTrailing: NSLayoutConstraint!
    private var titleBeforeUndo: NSLayoutConstraint!
    private var undoable = false
    private var hovering = false
    private var onUndo: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        icon.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingMiddle
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.font = .systemFont(ofSize: 11)
        detail.lineBreakMode = .byTruncatingTail
        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        undoButton.isBordered = false
        undoButton.target = self
        undoButton.action = #selector(undo(_:))
        undoButton.translatesAutoresizingMaskIntoConstraints = false
        undoButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        undoButton.isHidden = true
        addSubview(icon)
        addSubview(title)
        addSubview(detail)
        addSubview(undoButton)
        titleTrailing = title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        titleBeforeUndo = title.trailingAnchor.constraint(lessThanOrEqualTo: undoButton.leadingAnchor, constant: -8)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        NSLayoutConstraint.activate([
            titleTrailing,
            undoButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            undoButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            title.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            detail.topAnchor.constraint(equalTo: centerYAnchor, constant: 2),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        updateUndo()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        updateUndo()
    }

    @objc private func undo(_ sender: NSButton) {
        onUndo?()
    }

    private func updateUndo() {
        let shown = undoable && hovering
        undoButton.isHidden = !shown
        titleTrailing.isActive = !shown
        titleBeforeUndo.isActive = shown
    }

    func show(_ entry: HistoryEntry, now: Date, undoable: Bool, onUndo: @escaping () -> Void) {
        self.undoable = undoable
        self.onUndo = onUndo
        undoButton.attributedTitle = NSAttributedString(string: "Undo", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: Theme.accent,
        ])
        updateUndo()
        let failed = entry.state == .failed
        icon.image = NSImage(systemSymbolName: entry.symbolName, accessibilityDescription: nil)
        icon.contentTintColor = failed ? Theme.warning : entry.state == .running ? Theme.accent : Theme.icon
        title.stringValue = entry.summary
        title.textColor = Theme.text
        title.toolTip = entry.summary
        detail.stringValue = "\(HistoryRow.time(entry.started, now: now)) · \(entry.stateDescription)"
        detail.textColor = failed ? Theme.warning : Theme.secondaryText
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private static func time(_ date: Date, now: Date) -> String {
        now.timeIntervalSince(date) < 60 ? "Just now" : formatter.localizedString(for: date, relativeTo: now)
    }
}

final class HistoryController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private static let width: CGFloat = 380
    private static let rowHeight: CGFloat = 46
    private static let maxHeight: CGFloat = 440

    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "No file operations in the last 30 days.")
    private var entries: [HistoryEntry] = []
    private var undoable: Set<UUID> = []
    private var now = Date()
    private var observer: NSObjectProtocol?

    override func loadView() {
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.selectionHighlightStyle = .none
        tableView.intercellSpacing = .zero
        tableView.rowHeight = HistoryController.rowHeight
        tableView.gridStyleMask = []
        tableView.focusRingType = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry")))

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        let root = FillView()
        root.color = Theme.card
        root.addSubview(scroll)
        root.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        view = root
        observer = NotificationCenter.default.addObserver(forName: .taskQueueChanged, object: TaskQueue.shared, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        reload()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func reload() {
        now = Date()
        entries = TaskQueue.shared.history.recent
        undoable = TaskQueue.shared.history.undoable
        emptyLabel.isHidden = !entries.isEmpty
        tableView.reloadData()
        let height = entries.isEmpty ? 80 : min(CGFloat(entries.count) * HistoryController.rowHeight + 12, HistoryController.maxHeight)
        preferredContentSize = NSSize(width: HistoryController.width, height: height)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("HistoryRow")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? HistoryRow ?? {
            let cell = HistoryRow()
            cell.identifier = identifier
            return cell
        }()
        let entry = entries[row]
        cell.show(entry, now: now, undoable: undoable.contains(entry.id)) { FileActions.undo(entry) }
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        false
    }
}
