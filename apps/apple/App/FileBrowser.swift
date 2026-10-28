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

    static func size(_ item: FileItem) -> String {
        item.isFolder ? "--" : ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
    }
}

final class RenameField: NSTextField {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    static func make() -> RenameField {
        let field = RenameField()
        field.isBordered = true
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.focusRingType = .default
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        return field
    }

    func begin(in view: NSView, frame: NSRect, text: String) {
        stringValue = text
        self.frame = frame
        view.addSubview(self)
        window?.makeFirstResponder(self)
        let (base, ext) = FileNaming.split(text)
        currentEditor()?.selectedRange = NSRange(location: 0, length: ext.isEmpty ? (text as NSString).length : (base as NSString).length)
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
