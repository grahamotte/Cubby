import Foundation

extension Notification.Name {
    static let folderCountsChanged = Notification.Name("CubbyFolderCountsChanged")
}

@MainActor
final class FolderCountCache {
    struct Entry: Equatable {
        var count: Int
        var countedAt: Date
        var stale = false
    }

    private struct Key: Hashable {
        let path: String
        let visibility: Visibility
    }

    static let shared = FolderCountCache()

    let refreshInterval: TimeInterval

    private var entries: [Visibility: [String: Entry]] = [:]
    private var known: [Visibility: [String: Int]] = [:]
    private var pending: Set<Key> = []
    private var changedWhileCounting: Set<Key> = []
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .utility
        return queue
    }()

    init(refreshInterval: TimeInterval = 60) {
        self.refreshInterval = refreshInterval
    }

    func entry(for path: String, visibility: Visibility) -> Entry? {
        entries[visibility]?[path]
    }

    func knownCounts(for visibility: Visibility) -> [String: Int] {
        known[visibility] ?? [:]
    }

    func isCounting(_ path: String, visibility: Visibility) -> Bool {
        pending.contains(Key(path: path, visibility: visibility))
    }

    func recount(_ path: String, visibility: Visibility) {
        let key = Key(path: path, visibility: visibility)
        guard pending.insert(key).inserted else { return }
        let started = Date()
        queue.addOperation { [weak self] in
            let count = (try? DirectoryReader.count(path, visibility: visibility)) ?? -1
            DispatchQueue.main.async {
                self?.finish(key, count: count, countedAt: started)
            }
        }
    }

    func markStale(_ path: String) {
        for visibility in entries.keys where entries[visibility]?[path] != nil {
            entries[visibility]?[path]?.stale = true
        }
        for key in pending where key.path == path {
            changedWhileCounting.insert(key)
        }
    }

    @discardableResult
    func markStale(under path: String) -> [String] {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        let inside = { (candidate: String) in candidate == path || candidate.hasPrefix(prefix) }
        var marked = Set<String>()
        for (visibility, list) in entries {
            for candidate in list.keys where inside(candidate) {
                entries[visibility]?[candidate]?.stale = true
                marked.insert(candidate)
            }
        }
        for key in pending where inside(key.path) {
            changedWhileCounting.insert(key)
        }
        return Array(marked)
    }

    private func finish(_ key: Key, count: Int, countedAt: Date) {
        pending.remove(key)
        let previous = entries[key.visibility]?[key.path]
        let stale = changedWhileCounting.remove(key) != nil
        entries[key.visibility, default: [:]][key.path] = Entry(count: count, countedAt: countedAt, stale: stale)
        if count >= 0 {
            known[key.visibility, default: [:]][key.path] = count
        } else {
            known[key.visibility]?[key.path] = nil
        }
        NotificationCenter.default.post(name: .folderCountsChanged, object: self, userInfo: [
            "path": key.path,
            "visibility": key.visibility,
            "changed": previous?.count != count,
        ])
    }
}
