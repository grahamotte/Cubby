import AppKit
import UniformTypeIdentifiers

@MainActor
final class IconCache {
    static let shared = IconCache()

    private var byType: [String: NSImage] = [:]
    private let byPath = NSCache<NSString, NSImage>()
    private lazy var folder = NSWorkspace.shared.icon(for: .folder)
    private lazy var document = NSWorkspace.shared.icon(for: .data)

    init() {
        byPath.countLimit = 2000
    }

    func icon(for item: FileItem) -> NSImage {
        if item.isFolder && !item.isSymlink {
            return folder
        }
        if item.isPackage || item.isSymlink {
            let key = item.path as NSString
            if let cached = byPath.object(forKey: key) { return cached }
            let icon = NSWorkspace.shared.icon(forFile: item.path)
            byPath.setObject(icon, forKey: key)
            return icon
        }
        let ext = item.pathExtension.lowercased()
        guard !ext.isEmpty else { return document }
        if let cached = byType[ext] { return cached }
        let icon = UTType(filenameExtension: ext).map { NSWorkspace.shared.icon(for: $0) } ?? document
        byType[ext] = icon
        return icon
    }
}
