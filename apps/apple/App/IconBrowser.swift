import AppKit

final class FileTileItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("FileTileItem")

    private let thumbnail = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private let selectionBackground = NSView()
    private var item: FileItem?
    private var iconSize: CGFloat = 64
    var showsLabel = true

    override func loadView() {
        view = NSView()
        selectionBackground.wantsLayer = true
        selectionBackground.layer?.cornerRadius = 6
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingMiddle
        label.font = .systemFont(ofSize: 12)
        label.cell?.truncatesLastVisibleLine = true
        view.addSubview(selectionBackground)
        view.addSubview(thumbnail)
        view.addSubview(label)
        imageView = thumbnail
        textField = label
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let bounds = view.bounds
        let labelHeight: CGFloat = showsLabel ? 32 : 0
        let side = min(iconSize, bounds.width - 8, bounds.height - labelHeight - 8)
        thumbnail.frame = NSRect(x: (bounds.width - side) / 2, y: labelHeight + (bounds.height - labelHeight - side) / 2, width: side, height: side)
        selectionBackground.frame = thumbnail.frame.insetBy(dx: -4, dy: -4)
        label.isHidden = !showsLabel
        label.frame = NSRect(x: 2, y: 0, width: bounds.width - 4, height: labelHeight)
    }

    override var isSelected: Bool {
        didSet { updateSelection() }
    }

    override var highlightState: NSCollectionViewItem.HighlightState {
        didSet { updateSelection() }
    }

    var labelFrame: NSRect { label.frame }

    func configure(_ item: FileItem, iconSize: CGFloat, cut: Bool) {
        if let previous = self.item, previous !== item {
            ThumbnailCache.shared.cancel(for: previous, size: self.iconSize)
        }
        self.item = item
        self.iconSize = iconSize
        label.stringValue = item.name
        view.alphaValue = item.isHidden || cut ? 0.5 : 1
        thumbnail.image = ThumbnailCache.shared.cached(for: item, size: iconSize) ?? IconCache.shared.icon(for: item)
        if ThumbnailCache.wantsThumbnail(item) {
            let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            ThumbnailCache.shared.thumbnail(for: item, size: iconSize, scale: scale) { [weak self] image in
                guard let self, self.item === item else { return }
                self.thumbnail.image = image
            }
        }
        view.needsLayout = true
        updateSelection()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if let item {
            ThumbnailCache.shared.cancel(for: item, size: iconSize)
        }
        item = nil
    }

    private func updateSelection() {
        let selected = isSelected || highlightState == .forSelection
        selectionBackground.layer?.backgroundColor = selected ? NSColor.unemphasizedSelectedContentBackgroundColor.cgColor : nil
        label.textColor = .labelColor
        if selected, view.window?.firstResponder is NSCollectionView {
            selectionBackground.layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35).cgColor
        }
    }
}

class FileCollectionView: NSCollectionView {
    weak var browser: TileBrowser?

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
        return super.becomeFirstResponder()
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
        updateLayout()
        collectionView.reloadData()
    }

    func select(paths: Set<String>, scroll: Bool) {
        let names = Set(paths.map { ($0 as NSString).lastPathComponent })
        let indexes = DirectoryListing.indexes(of: names, in: items).filter { paths.contains(items[$0].path) }
        applyingSelection = true
        collectionView.selectionIndexPaths = Set(indexes.map { IndexPath(item: $0, section: 0) })
        applyingSelection = false
        if scroll, let first = indexes.first {
            collectionView.scrollToItems(at: [IndexPath(item: first, section: 0)], scrollPosition: .centeredVertically)
        }
        selectionChanged()
    }

    func focus() {
        view.window?.makeFirstResponder(collectionView)
    }

    func beginRename(path: String) {
        select(paths: [path], scroll: true)
        guard let index = items.firstIndex(where: { $0.path == path }) else { return }
        collectionView.layoutSubtreeIfNeeded()
        guard let tile = collectionView.item(at: IndexPath(item: index, section: 0)) as? FileTileItem else { return }
        let item = items[index]
        var frame = collectionView.convert(tile.labelFrame, from: tile.view)
        frame.size.height = 22
        frame.origin.y = collectionView.convert(tile.labelFrame, from: tile.view).maxY - 22
        renameField.font = .systemFont(ofSize: 12)
        renameField.alignment = .center
        renameField.onCommit = { [weak self] name in
            self?.host?.rename(item, to: name)
            self?.focus()
        }
        renameField.onCancel = { [weak self] in self?.focus() }
        renameField.begin(in: collectionView, frame: frame, text: item.name)
    }

    func selectionChanged() {
        guard !applyingSelection else { return }
        host?.browserSelectionChanged()
    }

    func contextMenu() -> NSMenu? {
        host?.menu(for: selectedItems, in: host?.model.path.fileURL ?? URL(filePath: "/"))
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
            if flags.subtracting(.shift).isEmpty, let characters = event.characters, !characters.isEmpty, characters.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.punctuationCharacters).union(.symbols).contains($0) || $0 == " " }) {
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
        tile.configure(item, iconSize: iconSize, cut: cut)
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
        layout.itemSize = NSSize(width: max(size + 28, 96), height: size + 44)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    }

    override func magnify(with event: NSEvent) {
        let size = Int(iconSize * (1 + event.magnification))
        host?.setIconSize(size)
    }
}
