import AppKit

@MainActor
protocol FileBrowserHost: AnyObject {
    var model: DirectoryModel { get }
    var folderView: FolderView { get }
    func open(_ items: [FileItem])
    func browserSelectionChanged()
    func menu(for items: [FileItem], in directory: URL) -> NSMenu
    func drop(_ urls: [URL], into directory: URL, operation: NSDragOperation) -> Bool
    func browserDidBecomeActive()
    func toggleQuickLook()
    func rename(_ item: FileItem, to name: String)
    func setSort(_ key: SortKey, ascending: Bool)
    func setIconSize(_ size: Int)
    func setListIconSize(_ size: Int)
    func browseDirectoryChanged()
    func focusNextPane()
}

@MainActor
protocol FileBrowser: NSViewController {
    var host: FileBrowserHost? { get set }
    var selectedItems: [FileItem] { get }
    var browseDirectory: URL? { get }
    func reload(_ change: DirectoryModel.Change)
    func select(paths: Set<String>, scroll: Bool)
    func beginRename(path: String)
    func focus()
    func viewDidChange()
}

extension FileBrowser {
    var browseDirectory: URL? { nil }
    func viewDidChange() {}
}

@MainActor
enum DragSupport {
    static let types: [NSPasteboard.PasteboardType] = [.fileURL]

    static func showCountOnly(_ session: NSDraggingSession, count: Int, from view: NSView, at screenPoint: NSPoint) {
        guard count > 1, let window = view.window else { return }
        session.animatesToStartingPositionsOnCancelOrFail = false
        let point = view.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        session.draggingFormation = .stack
        session.enumerateDraggingItems(for: view, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
            item.setDraggingFrame(NSRect(origin: point, size: .zero), contents: nil)
        }
    }

    static func urls(from info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    static func operation(for info: NSDraggingInfo, to directory: URL) -> NSDragOperation {
        let urls = urls(from: info)
        guard !urls.isEmpty else { return [] }
        let target = directory.standardizedFileURL.path
        for url in urls {
            let path = url.standardizedFileURL.path
            if target == path || target.hasPrefix(path + "/") { return [] }
        }
        let mask = info.draggingSourceOperationMask
        let allInPlace = urls.allSatisfy { $0.deletingLastPathComponent().standardizedFileURL.path == target }
        if mask == .copy { return .copy }
        if allInPlace { return [] }
        if mask == .generic || mask == .move { return .move }
        return sameVolume(urls, directory) ? .move : .copy
    }

    static func sameVolume(_ urls: [URL], _ directory: URL) -> Bool {
        guard let target = volume(directory) else { return false }
        return urls.allSatisfy { volume($0) == target }
    }

    private static func volume(_ url: URL) -> NSObject? {
        (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
    }
}

@MainActor
enum FileFormat {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    static func date(_ seconds: Double) -> String {
        seconds > 0 ? dateFormatter.string(from: Date(timeIntervalSince1970: seconds)) : "--"
    }

    static func count(_ count: Int?) -> String {
        count.map { NumberFormatter.localizedString(from: NSNumber(value: $0), number: .decimal) } ?? "--"
    }

    static func name(_ name: String, query: String, font: NSFont, color: NSColor) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        let text = NSMutableAttributedString(string: name, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
        TileLabel.embolden(text, FileSorter.matchRanges(in: name, query: query), font: font)
        return text
    }

    static func size(_ item: FileItem) -> String {
        item.isFolder ? "--" : ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
    }
}

final class RenameField: NSTextField {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private var topEdge: CGFloat = 0

    var wrapsLines = false {
        didSet {
            cell?.wraps = wrapsLines
            cell?.isScrollable = !wrapsLines
            usesSingleLineMode = !wrapsLines
            lineBreakMode = wrapsLines ? .byWordWrapping : .byClipping
            focusRingType = wrapsLines ? .none : .default
        }
    }

    static func make() -> RenameField {
        let field = RenameField()
        field.isBordered = true
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = Theme.card
        field.textColor = Theme.text
        field.focusRingType = .default
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        return field
    }

    func begin(in view: NSView, frame: NSRect, text: String) {
        stringValue = text
        self.frame = frame
        topEdge = view.isFlipped ? frame.minY : frame.maxY
        view.addSubview(self)
        fitHeight()
        window?.makeFirstResponder(self)
        let (base, ext) = FileNaming.split(text)
        currentEditor()?.selectedRange = NSRange(location: 0, length: ext.isEmpty ? (text as NSString).length : (base as NSString).length)
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        fitHeight()
    }

    private func fitHeight() {
        guard wrapsLines, let measuring = cell?.copy() as? NSCell else { return }
        measuring.stringValue = stringValue
        let height = measuring.cellSize(forBounds: NSRect(x: 0, y: 0, width: frame.width, height: .greatestFiniteMagnitude)).height.rounded(.up)
        guard height != frame.height else { return }
        let flipped = superview?.isFlipped ?? true
        setFrameSize(NSSize(width: frame.width, height: height))
        setFrameOrigin(NSPoint(x: frame.minX, y: flipped ? topEdge : topEdge - height))
    }

    override func textDidEndEditing(_ notification: Notification) {
        let movement = notification.userInfo?["NSTextMovement"] as? Int
        let value = stringValue
        removeFromSuperview()
        if movement == NSTextMovement.cancel.rawValue {
            onCancel?()
        } else {
            onCommit?(value)
        }
        onCommit = nil
        onCancel = nil
    }

    override func cancelOperation(_ sender: Any?) {
        abortEditing()
        removeFromSuperview()
        onCancel?()
        onCommit = nil
        onCancel = nil
    }
}
