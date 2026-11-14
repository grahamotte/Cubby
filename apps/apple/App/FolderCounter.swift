import CoreServices
import Foundation

@MainActor
final class FolderCounter {
    let root: String
    var onChange: (() -> Void)?

    var visibility: Visibility {
        didSet {
            guard visibility != oldValue else { return }
            waiting = []
            scheduleNotify()
        }
    }

    private let cache: FolderCountCache
    private let startedAt = Date()
    private var waiting: Set<String> = []
    private var wakeAt: Date?
    private var wakeToken = 0
    private var notifyScheduled = false
    private var stream: FSEventStreamRef?
    private var observer: NSObjectProtocol?
    private let resolvedRoot: String

    init(root: String, visibility: Visibility, latency: TimeInterval = 0.3, cache: FolderCountCache? = nil) {
        self.root = root
        self.visibility = visibility
        self.cache = cache ?? .shared
        resolvedRoot = realpath(root, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        } ?? root
        observer = NotificationCenter.default.addObserver(forName: .folderCountsChanged, object: self.cache, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated { self?.counted(notification) }
        }
        startStream(latency: latency)
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    func count(for path: String) -> Int? {
        guard let entry = cache.entry(for: path, visibility: visibility) else {
            cache.recount(path, visibility: visibility)
            return nil
        }
        refreshIfNeeded(path, entry: entry)
        return entry.count < 0 ? nil : entry.count
    }

    var knownCounts: [String: Int] {
        cache.knownCounts(for: visibility)
    }

    func isCounting(_ path: String) -> Bool {
        cache.isCounting(path, visibility: visibility)
    }

    func invalidate(_ path: String) {
        let path = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        cache.markStale(path)
        if let entry = cache.entry(for: path, visibility: visibility) {
            refreshIfNeeded(path, entry: entry)
        }
    }

    func invalidateAll(under path: String) {
        for marked in cache.markStale(under: path) {
            if let entry = cache.entry(for: marked, visibility: visibility) {
                refreshIfNeeded(marked, entry: entry)
            }
        }
    }

    private func refreshIfNeeded(_ path: String, entry: FolderCountCache.Entry) {
        let visited = entry.countedAt < startedAt
        guard entry.stale || visited else { return }
        let due = visited ? entry.countedAt : entry.countedAt.addingTimeInterval(cache.refreshInterval)
        if due <= Date() {
            waiting.remove(path)
            cache.recount(path, visibility: visibility)
        } else {
            waiting.insert(path)
            scheduleWake(at: due)
        }
    }

    private func scheduleWake(at date: Date) {
        if let wakeAt, wakeAt <= date { return }
        wakeAt = date
        wakeToken += 1
        let token = wakeToken
        DispatchQueue.main.asyncAfter(deadline: .now() + max(date.timeIntervalSinceNow, 0)) { [weak self] in
            guard let self, token == self.wakeToken else { return }
            self.wakeAt = nil
            self.wake()
        }
    }

    private func wake() {
        let paths = waiting
        waiting = []
        for path in paths {
            if let entry = cache.entry(for: path, visibility: visibility) {
                refreshIfNeeded(path, entry: entry)
            } else {
                cache.recount(path, visibility: visibility)
            }
        }
    }

    private func counted(_ notification: Notification) {
        guard let path = notification.userInfo?["path"] as? String, notification.userInfo?["visibility"] as? Visibility == visibility, path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/") else { return }
        if let entry = cache.entry(for: path, visibility: visibility), entry.stale {
            refreshIfNeeded(path, entry: entry)
        }
        if notification.userInfo?["changed"] as? Bool == true {
            scheduleNotify()
        }
    }

    private func scheduleNotify() {
        guard !notifyScheduled else { return }
        notifyScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.notifyScheduled = false
            self.onChange?()
        }
    }

    private func handle(_ paths: [String], flags: [FSEventStreamEventFlags]) {
        for (path, flag) in zip(paths, flags) {
            let local = localPath(path)
            if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0 || flag & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
                invalidateAll(under: local)
            } else {
                invalidate(local)
            }
        }
    }

    private func localPath(_ path: String) -> String {
        let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        guard resolvedRoot != root else { return trimmed }
        if trimmed == resolvedRoot { return root }
        if trimmed.hasPrefix(resolvedRoot + "/") { return root + trimmed.dropFirst(resolvedRoot.count) }
        return trimmed
    }

    private func startStream(latency: TimeInterval) {
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let counter = Unmanaged<FolderCounter>.fromOpaque(info).takeUnretainedValue()
            let list = UnsafeBufferPointer(start: paths.assumingMemoryBound(to: UnsafePointer<CChar>.self), count: count).map { String(cString: $0) }
            let flagList = Array(UnsafeBufferPointer(start: flags, count: count))
            MainActor.assumeIsolated { counter.handle(list, flags: flagList) }
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, [root] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }
}
