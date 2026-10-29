import AppKit

final class FileTileItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("FileTileItem")
    static let labelHeight: CGFloat = 36
    static let labelFont = NSFont.systemFont(ofSize: 12)

    private let thumbnail = ThumbnailView()
    private let label = PassthroughLabel(wrappingLabelWithString: "")
    private let selectionBackground = FillView()
    private let labelBackground = FillView()
    private var item: FileItem?
    private var iconSize: CGFloat = 64
    private var labelWidth: CGFloat = 0
    private var labelSelected = false
    private var query = ""
    var isRenaming = false {
        didSet { updateSelection() }
    }

    override func loadView() {
        view = NSView()
        selectionBackground.color = Theme.inactiveSelection
        selectionBackground.cornerRadius = 10
        labelBackground.cornerRadius = 4
        label.maximumNumberOfLines = 2
        label.isSelectable = false
        label.cell?.truncatesLastVisibleLine = true
        view.addSubview(selectionBackground)
        view.addSubview(thumbnail)
        view.addSubview(labelBackground)
        view.addSubview(label)
        textField = label
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let bounds = view.bounds
        let labelHeight = FileTileItem.labelHeight
        let side = max(min(iconSize, bounds.width - 16, bounds.height - labelHeight - 16), 0)
        thumbnail.frame = NSRect(x: ((bounds.width - side) / 2).rounded(), y: (labelHeight + (bounds.height - labelHeight - side) / 2).rounded(), width: side, height: side)
        selectionBackground.frame = thumbnail.frame.insetBy(dx: -6, dy: -6)
        let width = labelFrame.width
        if width != labelWidth {
            labelWidth = width
            updateLabel()
        }
        layoutLabel()
    }

    override var isSelected: Bool {
        didSet { updateSelection() }
    }

    override var highlightState: NSCollectionViewItem.HighlightState {
        didSet { updateSelection() }
    }

    var labelFrame: NSRect {
        NSRect(x: 4, y: 0, width: max(view.bounds.width - 8, 0), height: FileTileItem.labelHeight)
    }

    func configure(_ item: FileItem, iconSize: CGFloat, cut: Bool, query: String) {
        let previous = self.item
        if let previous, previous !== item {
            ThumbnailCache.shared.cancel(for: previous, size: self.iconSize)
        }
        self.item = item
        self.iconSize = iconSize
        view.alphaValue = item.isHidden || cut ? 0.5 : 1
        if let cached = ThumbnailCache.shared.cached(for: item, size: iconSize) {
            thumbnail.show(cached)
        } else if previous !== item || thumbnail.image == nil {
            thumbnail.show(IconCache.shared.icon(for: item))
        }
        if ThumbnailCache.wantsThumbnail(item) {
            let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            ThumbnailCache.shared.thumbnail(for: item, size: iconSize, scale: scale) { [weak self] thumbnail in
                guard let self, self.item === item else { return }
                self.thumbnail.show(thumbnail)
            }
        }
        if previous?.name != item.name || self.query != query {
            labelWidth = 0
        }
        self.query = query
        view.needsLayout = true
        updateSelection()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if let item {
            ThumbnailCache.shared.cancel(for: item, size: iconSize)
        }
        item = nil
        isRenaming = false
        thumbnail.show(nil)
    }

    func updateSelection() {
        let selected = isSelected || highlightState == .forSelection
        let focused = (collectionView as? FileCollectionView)?.isFocused == true
        selectionBackground.isHidden = !selected
        labelBackground.color = focused ? Theme.accent : Theme.inactiveSelection
        labelBackground.isHidden = !selected || isRenaming
        label.isHidden = isRenaming
        let emphasized = selected && focused
        if emphasized != labelSelected {
            labelSelected = emphasized
            updateLabel()
        }
    }

    private func updateLabel() {
        guard let item, labelWidth > 0 else { return }
        let color = labelSelected ? Theme.accentText : Theme.text
        label.attributedStringValue = TileLabel.text(item.name, width: labelWidth - 10, font: FileTileItem.labelFont, color: color, bold: FileSorter.matchRanges(in: item.name, query: query))
        layoutLabel()
    }

    private func layoutLabel() {
        let area = labelFrame
        guard area.width > 0, let cell = label.cell else { return }
        let size = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: area.width, height: area.height))
        let width = min(size.width.rounded(.up), area.width)
        let height = min(size.height.rounded(.up), area.height)
        label.frame = NSRect(x: (area.midX - width / 2).rounded(), y: area.maxY - height, width: width, height: height)
        labelBackground.frame = label.frame.insetBy(dx: -2, dy: 0)
    }
}

class FileCollectionView: NSCollectionView {
    weak var browser: TileBrowser?
    private var hasFocus = false

    var isFocused: Bool {
        hasFocus && window?.isKeyWindow == true
    }

    override func keyDown(with event: NSEvent) {
        if browser?.handleKey(event) == true { return }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        if let indexPath = indexPathForItem(at: point) {
            if !selectionIndexPaths.contains(indexPath) {
                selectionIndexPaths = [indexPath]
                browser?.selectionChanged()
            }
        } else {
            selectionIndexPaths = []
            browser?.selectionChanged()
        }
        return browser?.contextMenu()
    }

    override func becomeFirstResponder() -> Bool {
        browser?.host?.browserDidBecomeActive()
        let became = super.becomeFirstResponder()
        if became {
            hasFocus = true
            browser?.refreshSelection()
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            hasFocus = false
            browser?.refreshSelection()
        }
        return resigned
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        guard let newWindow else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(windowKeyChanged(_:)), name: NSWindow.didBecomeKeyNotification, object: newWindow)
        NotificationCenter.default.addObserver(self, selector: #selector(windowKeyChanged(_:)), name: NSWindow.didResignKeyNotification, object: newWindow)
    }

    @objc private func windowKeyChanged(_ notification: Notification) {
        browser?.refreshSelection()
    }

    override func mouseDown(with event: NSEvent) {
        browser?.host?.browserDidBecomeActive()
        super.mouseDown(with: event)
        if event.clickCount == 2, let indexPath = indexPathForItem(at: convert(event.locationInWindow, from: nil)), let item = browser?.item(at: indexPath.item) {
            browser?.host?.open([item])
        }
    }
}

class TileBrowser: NSViewController, FileBrowser, NSCollectionViewDataSource, NSCollectionViewDelegate {
    weak var host: FileBrowserHost?
    let collectionView = FileCollectionView()
    let scrollView = NSScrollView()
    let renameField = RenameField.make()
    private var applyingSelection = false
    private var typeSelectBuffer = ""
    private var typeSelectTime = Date.distantPast
    private var laidOutWidth: CGFloat = 0

    private(set) var items: [FileItem] = []
    var iconSize: CGFloat { CGFloat(host?.folderView.iconSize ?? 80) }

    func item(at index: Int) -> FileItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    func makeLayout() -> NSCollectionViewLayout {
        NSCollectionViewFlowLayout()
    }

    func updateLayout() {}

    override func loadView() {
        collectionView.browser = self
        collectionView.collectionViewLayout = makeLayout()
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(FileTileItem.self, forItemWithIdentifier: FileTileItem.identifier)
        collectionView.registerForDraggedTypes(DragSupport.types)
        collectionView.setDraggingSourceOperationMask([.copy, .move, .link, .generic], forLocal: false)
        collectionView.setDraggingSourceOperationMask([.copy, .move, .link, .generic], forLocal: true)
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        view = scrollView
        updateLayout()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let width = scrollView.contentSize.width
        guard width != laidOutWidth else { return }
        laidOutWidth = width
        updateLayout()
    }

    func refreshSelection() {
        for case let tile as FileTileItem in collectionView.visibleItems() {
            tile.updateSelection()
        }
    }

    var selectedItems: [FileItem] {
        collectionView.selectionIndexPaths.sorted().compactMap { item(at: $0.item) }
    }

    func reload(_ change: DirectoryModel.Change) {
        if case .children = change { return }
        let selected = Set(selectedItems.map(\.path))
        items = host?.model.items ?? []
        if case .loaded = change {
            collectionView.selectionIndexPaths = []
            collectionView.reloadData()
            collectionView.scroll(.zero)
            selectionChanged()
            return
        }
        collectionView.reloadData()
        select(paths: selected, scroll: false)
    }

    func viewDidChange() {
        let selected = Set(selectedItems.map(\.path))
        updateLayout()
        collectionView.reloadData()
        select(paths: selected, scroll: false)
    }

    func select(paths: Set<String>, scroll: Bool) {
        let names = Set(paths.map { ($0 as NSString).lastPathComponent })
        let indexes = DirectoryListing.indexes(of: names, in: items).filter { paths.contains(items[$0].path) }
        applyingSelection = true
        collectionView.selectionIndexPaths = Set(indexes.map { IndexPath(item: $0, section: 0) })
        applyingSelection = false
        if scroll, let first = indexes.first {
            collectionView.layoutSubtreeIfNeeded()
            let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: first, section: 0))?.frame
            if frame.map({ !visibleArea.contains($0) }) ?? true {
                collectionView.scrollToItems(at: [IndexPath(item: first, section: 0)], scrollPosition: .centeredVertically)
            }
        }
        selectionChanged()
    }

    func focus() {
        view.window?.makeFirstResponder(collectionView)
    }

    private var visibleArea: NSRect {
        var rect = collectionView.visibleRect
        let inset = ScrollAnchoring.topInset(collectionView)
        rect.origin.y += inset
        rect.size.height -= inset
        return rect
    }

    func scrollAnchor() -> ScrollAnchor? {
        let visible = visibleArea
        let top = collectionView.indexPathsForVisibleItems().map(\.item).sorted().first { index in
            (collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame.maxY ?? 0) > visible.minY
        }
        guard let top, let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: top, section: 0))?.frame else { return nil }
        return ScrollAnchoring.anchor(top: top, count: items.count, offset: visible.minY - frame.minY) { item(at: $0)?.path }
    }

    func restoreScroll(_ anchor: ScrollAnchor) {
        let names = Dictionary(items.enumerated().map { ($1.path, $0) }, uniquingKeysWith: { first, _ in first })
        guard let target = anchor.resolve({ names[$0] }) else { return }
        view.superview?.layoutSubtreeIfNeeded()
        collectionView.layoutSubtreeIfNeeded()
        guard let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: target.index, section: 0))?.frame else { return }
        collectionView.scroll(NSPoint(x: 0, y: frame.minY + CGFloat(target.offset) - ScrollAnchoring.topInset(collectionView)))
    }

    func beginRename(path: String) {
        select(paths: [path], scroll: true)
        guard let index = items.firstIndex(where: { $0.path == path }) else { return }
        collectionView.layoutSubtreeIfNeeded()
        guard let tile = collectionView.item(at: IndexPath(item: index, section: 0)) as? FileTileItem else { return }
        let item = items[index]
        let frame = collectionView.convert(tile.labelFrame, from: tile.view)
        renameField.font = FileTileItem.labelFont
        renameField.alignment = .center
        renameField.wrapsLines = true
        tile.isRenaming = true
        let finish: () -> Void = { [weak self, weak tile] in
            tile?.isRenaming = false
            self?.focus()
        }
        renameField.onCommit = { [weak self] name in
            self?.host?.rename(item, to: name)
            finish()
        }
        renameField.onCancel = finish
        renameField.begin(in: collectionView, frame: NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: 0), text: item.name)
    }

    func selectionChanged() {
        guard !applyingSelection else { return }
        host?.browserSelectionChanged()
    }

    func contextMenu() -> NSMenu? {
        host?.menu(for: selectedItems, in: host?.model.path.fileURL ?? URL(filePath: "/"))
    }

    func handleKey(_ event: NSEvent) -> Bool {
        switch KeyCombo(event: event).flatMap({ Shortcuts.action(for: $0, in: .browsing) }) {
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
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift).isEmpty, let characters = event.characters, !characters.isEmpty, characters.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.punctuationCharacters).union(.symbols).contains($0) || $0 == " " }) {
                typeSelect(characters)
                return true
            }
        }
        return false
    }

    private func typeSelect(_ characters: String) {
        let now = Date()
        if now.timeIntervalSince(typeSelectTime) > 1 { typeSelectBuffer = "" }
        typeSelectTime = now
        typeSelectBuffer += characters.lowercased()
        let buffer = typeSelectBuffer
        let match = items.firstIndex { $0.name.lowercased().hasPrefix(buffer) }
            ?? items.firstIndex { FileSorter.naturalCompare(Array($0.name.lowercased().utf16), Array(buffer.utf16)) != .orderedAscending }
        guard let match else { return }
        select(paths: [items[match].path], scroll: true)
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let tile = collectionView.makeItem(withIdentifier: FileTileItem.identifier, for: indexPath) as! FileTileItem
        if let item = item(at: indexPath.item) {
            configure(tile, item)
        }
        return tile
    }

    func configure(_ tile: FileTileItem, _ item: FileItem) {
        let cut = AppState.shared.cutURLs.contains { $0.path == item.path }
        tile.configure(item, iconSize: iconSize, cut: cut, query: host?.model.query ?? "")
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        selectionChanged()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        selectionChanged()
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        item(at: indexPath.item)?.url as NSURL?
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
        DragSupport.showCountOnly(session, count: indexPaths.count, from: collectionView, at: screenPoint)
    }

    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        let index = proposedIndexPath.pointee.item
        if dropOperation.pointee == .on, let target = item(at: index), target.isFolder {
            return DragSupport.operation(for: draggingInfo, to: target.url)
        }
        dropOperation.pointee = .before
        proposedIndexPath.pointee = NSIndexPath(forItem: items.count, inSection: 0)
        return DragSupport.operation(for: draggingInfo, to: host?.model.path.fileURL ?? URL(filePath: "/"))
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        var directory = host?.model.path.fileURL ?? URL(filePath: "/")
        if dropOperation == .on, let target = item(at: indexPath.item), target.isFolder {
            directory = target.url
        }
        let operation = DragSupport.operation(for: draggingInfo, to: directory)
        guard !operation.isEmpty else { return false }
        return host?.drop(DragSupport.urls(from: draggingInfo), into: directory, operation: operation) ?? false
    }
}

final class IconBrowser: TileBrowser {
    override func updateLayout() {
        guard let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
        let size = iconSize
        let inset: CGFloat = 16
        let available = max(scrollView.contentSize.width - inset * 2, 1)
        let columns = max(Int(available / max(size + 48, 112)), 1)
        layout.itemSize = NSSize(width: (available / CGFloat(columns)).rounded(.down), height: size + 20 + FileTileItem.labelHeight)
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 12
        layout.sectionInset = NSEdgeInsets(top: 12, left: inset, bottom: 16, right: inset)
    }

    override func magnify(with event: NSEvent) {
        let size = Int(iconSize * (1 + event.magnification))
        host?.setIconSize(size)
    }
}
