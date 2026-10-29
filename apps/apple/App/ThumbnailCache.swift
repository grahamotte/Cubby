import AppKit
import QuickLookThumbnailing

final class Thumbnail {
    let image: NSImage
    let rounded: Bool

    init(image: NSImage, rounded: Bool) {
        self.image = image
        self.rounded = rounded
    }
}

struct ThumbnailGenerator {
    var generate: (_ url: URL, _ side: CGFloat, _ scale: CGFloat, _ iconMode: Bool, _ completion: @escaping (NSImage?, Bool) -> Void) -> AnyObject
    var cancel: (AnyObject) -> Void

    static let quickLook = ThumbnailGenerator { url, side, scale, iconMode, completion in
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: scale, representationTypes: [.icon, .thumbnail])
        request.iconMode = iconMode
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            completion(representation?.nsImage, representation?.type == .thumbnail)
        }
        return request
    } cancel: { request in
        if let request = request as? QLThumbnailGenerator.Request {
            QLThumbnailGenerator.shared.cancel(request)
        }
    }
}

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let generator: ThumbnailGenerator
    private let cache = NSCache<NSString, Thumbnail>()
    private var inFlight: [NSString: AnyObject] = [:]
    private var waiters: [NSString: [(Thumbnail) -> Void]] = [:]

    init(generator: ThumbnailGenerator = .quickLook) {
        self.generator = generator
        cache.countLimit = 1500
        cache.totalCostLimit = 400 * 1024 * 1024
    }

    static func wantsThumbnail(_ item: FileItem) -> Bool {
        !item.isFolder && !item.isSymlink && item.size > 0
    }

    static func requestSize(_ size: CGFloat) -> CGFloat {
        size <= 64 ? (size / 16).rounded(.up) * 16 : (size / 64).rounded(.up) * 64
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
        var request: AnyObject?
        request = generator.generate(item.url, ThumbnailCache.requestSize(size), scale, item.isPackage) { image, rounded in
            DispatchQueue.main.async {
                guard let request, self.inFlight[key] === request else { return }
                self.inFlight[key] = nil
                let completions = self.waiters.removeValue(forKey: key) ?? []
                guard let image else { return }
                let thumbnail = Thumbnail(image: image, rounded: rounded)
                let pixels = Int(image.size.width * image.size.height * scale * scale * 4)
                self.cache.setObject(thumbnail, forKey: key, cost: pixels)
                completions.forEach { $0(thumbnail) }
            }
        }
        inFlight[key] = request
    }

    func cancel(for item: FileItem, size: CGFloat) {
        let key = key(item, size)
        waiters[key] = nil
        if let request = inFlight.removeValue(forKey: key) {
            generator.cancel(request)
        }
    }

    private func key(_ item: FileItem, _ size: CGFloat) -> NSString {
        "\(item.path)|\(item.modified)|\(Int(ThumbnailCache.requestSize(size)))" as NSString
    }
}
