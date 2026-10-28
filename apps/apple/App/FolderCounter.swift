import CoreServices
import Foundation

@MainActor
final class FolderCounter {
    let root: String
    var onChange: (() -> Void)?

    var visibility: Visibility {
        didSet {
            guard visibility != oldValue else { return }
            reset()
        }
    }

    private var counts: [String: Int] = [:]
    private var pending: Set<String> = []
    private var generation = 0
    private var notifyScheduled = false
    private var stream: FSEventStreamRef?
    private let resolvedRoot: String
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .utility
        return queue
    }()

    init(root: String, visibility: Visibility, latency: TimeInterval = 0.3) {
        self.root = root
        self.visibility = visibility
        resolvedRoot = realpath(root, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        } ?? root
        startStream(latency: latency)
    }

    deinit {
        queue.cancelAllOperations()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    func count(for path: String) -> Int? {
        if let count = counts[path] { return count < 0 ? nil : count }
        guard pending.insert(path).inserted else { return nil }
        let token = generation
        let visibility = visibility
        queue.addOperation { [weak self] in
            let count = (try? DirectoryReader.count(path, visibility: visibility)) ?? -1
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                self.pending.remove(path)
                self.counts[path] = count
                self.scheduleNotify()
            }
        }
        return nil
    }

    func isCounting(_ path: String) -> Bool {
        pending.contains(path)
    }

    func invalidate(_ path: String) {
        let path = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        guard counts.removeValue(forKey: path) != nil else { return }
        scheduleNotify()
    }

    func invalidateAll(under path: String) {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        let before = counts.count
        counts = counts.filter { $0.key != path && !$0.key.hasPrefix(prefix) }
        if counts.count != before { scheduleNotify() }
    }

    private func reset() {
        generation += 1
        queue.cancelAllOperations()
        counts = [:]
        pending = []
        scheduleNotify()
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
