import AppKit
import QuickLookThumbnailing
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

final class Thumbnail {
    let image: NSImage
    let rounded: Bool

    init(image: NSImage, rounded: Bool) {
        self.image = image
        self.rounded = rounded
    }
}

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, Thumbnail>()
    private var inFlight: [NSString: QLThumbnailGenerator.Request] = [:]
    private var waiters: [NSString: [(Thumbnail) -> Void]] = [:]

    init() {
        cache.countLimit = 1500
        cache.totalCostLimit = 400 * 1024 * 1024
    }

    static func wantsThumbnail(_ item: FileItem) -> Bool {
        !item.isFolder && !item.isSymlink && item.size > 0
    }

    static func requestSize(_ size: CGFloat) -> CGFloat {
        (size / 64).rounded(.up) * 64
    }

    func cached(for item: FileItem, size: CGFloat) -> Thumbnail? {
        cache.object(forKey: key(item, size))
    }

    func thumbnail(for item: FileItem, size: CGFloat, scale: CGFloat, completion: @escaping (Thumbnail) -> Void) {
        guard ThumbnailCache.wantsThumbnail(item) else { return }
        let key = key(item, size)
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }
        waiters[key, default: []].append(completion)
        guard inFlight[key] == nil else { return }
        let side = ThumbnailCache.requestSize(size)
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: side, height: side), scale: scale, representationTypes: [.icon, .thumbnail])
        request.iconMode = item.isPackage
        inFlight[key] = request
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            let image = representation?.nsImage
            let rounded = representation?.type == .thumbnail
            DispatchQueue.main.async {
                self.inFlight[key] = nil
                let completions = self.waiters.removeValue(forKey: key) ?? []
                guard let image else { return }
                let thumbnail = Thumbnail(image: image, rounded: rounded)
                let pixels = Int(image.size.width * image.size.height * scale * scale * 4)
                self.cache.setObject(thumbnail, forKey: key, cost: pixels)
                completions.forEach { $0(thumbnail) }
            }
        }
    }

    func cancel(for item: FileItem, size: CGFloat) {
        let key = key(item, size)
        waiters[key] = nil
        if let request = inFlight.removeValue(forKey: key) {
            QLThumbnailGenerator.shared.cancel(request)
        }
    }

    private func key(_ item: FileItem, _ size: CGFloat) -> NSString {
        "\(item.path)|\(item.modified)|\(Int(ThumbnailCache.requestSize(size)))" as NSString
    }
}
