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

    private struct Record: Codable {
        var path: String
        var showHidden: Bool
        var showDSStore: Bool
        var count: Int
        var countedAt: Date
    }

    private struct File: Codable {
        var counts: [Record]
    }

    static let shared = FolderCountCache(url: CubbyPaths.standard.countsFile)
    static let retention: TimeInterval = 30 * 24 * 60 * 60
    static let limit = 20000

    let url: URL?
    let refreshInterval: TimeInterval
    let saveDelay: TimeInterval

    private var entries: [Visibility: [String: Entry]] = [:]
    private var known: [Visibility: [String: Int]] = [:]
    private var pending: Set<Key> = []
    private var changedWhileCounting: Set<Key> = []
    private var saveScheduled = false
    private let writer = DispatchQueue(label: "cubby.counts", qos: .utility)
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .utility
        return queue
    }()

    init(url: URL? = nil, refreshInterval: TimeInterval = 60, saveDelay: TimeInterval = 5) {
        self.url = url
        self.refreshInterval = refreshInterval
        self.saveDelay = saveDelay
        guard let url, let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) else { return }
        let cutoff = Date().addingTimeInterval(-FolderCountCache.retention)
        for record in file.counts where record.count >= 0 && record.countedAt >= cutoff {
            let visibility = Visibility(showHidden: record.showHidden, showDSStore: record.showDSStore)
            entries[visibility, default: [:]][record.path] = Entry(count: record.count, countedAt: record.countedAt)
            known[visibility, default: [:]][record.path] = record.count
        }
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
        scheduleSave()
        NotificationCenter.default.post(name: .folderCountsChanged, object: self, userInfo: [
            "path": key.path,
            "visibility": key.visibility,
            "changed": previous?.count != count,
        ])
    }

    func flush() {
        saveScheduled = false
        guard let data = encoded(), let url else { return }
        writer.sync { try? JSONStore.write(data, to: url) }
    }

    private func scheduleSave() {
        guard url != nil, !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay) { [weak self] in
            guard let self, self.saveScheduled else { return }
            self.saveScheduled = false
            guard let data = self.encoded(), let url = self.url else { return }
            self.writer.async { try? JSONStore.write(data, to: url) }
        }
    }

    private func encoded() -> Data? {
        let cutoff = Date().addingTimeInterval(-FolderCountCache.retention)
        var records: [Record] = []
        for (visibility, list) in entries {
            for (path, entry) in list where entry.count >= 0 && entry.countedAt >= cutoff {
                records.append(Record(path: path, showHidden: visibility.showHidden, showDSStore: visibility.showDSStore, count: entry.count, countedAt: entry.countedAt))
            }
        }
        records.sort { ($0.countedAt, $0.path) > ($1.countedAt, $1.path) }
        return try? JSONStore.encode(File(counts: Array(records.prefix(FolderCountCache.limit))))
    }
}
