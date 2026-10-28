import Foundation

struct FolderIdentity: Codable, Hashable {
    let device: Int64
    let inode: UInt64

    init(device: Int64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }

    init?(path: String) {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        self.init(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
    }
}

final class FolderViewStore {
    struct Entry: Codable, Equatable {
        var view: FolderView
        var identity: FolderIdentity?
    }

    private struct File: Codable {
        var folders: [String: Entry]
    }

    static let pruneThreshold = 2000

    let url: URL
    private(set) var entries: [String: Entry] = [:]
    private var byIdentity: [FolderIdentity: String] = [:]
    private(set) var isDirty = false

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) {
            entries = file.folders
        }
        rebuildIndex()
    }

    func view(for path: String, identity: FolderIdentity?) -> FolderView? {
        if let entry = entries[path] {
            if entry.identity == nil || identity == nil || entry.identity == identity {
                return entry.view
            }
            entries[path] = nil
            isDirty = true
            rebuildIndex()
        }
        guard let identity, let oldPath = byIdentity[identity], let entry = entries[oldPath] else { return nil }
        entries[oldPath] = nil
        entries[path] = entry
        byIdentity[identity] = path
        isDirty = true
        return entry.view
    }

    func setView(_ view: FolderView, for path: String, identity: FolderIdentity?, defaultView: FolderView) {
        if let oldIdentity = entries[path]?.identity {
            byIdentity[oldIdentity] = nil
        }
        if view == defaultView {
            guard entries.removeValue(forKey: path) != nil else { return }
        } else {
            if let identity, let stalePath = byIdentity[identity], stalePath != path {
                entries[stalePath] = nil
            }
            entries[path] = Entry(view: view, identity: identity)
            if let identity { byIdentity[identity] = path }
        }
        isDirty = true
    }

    func prune(exists: (String) -> Bool) {
        guard entries.count > FolderViewStore.pruneThreshold else { return }
        let before = entries.count
        entries = entries.filter { exists($0.key) }
        guard entries.count != before else { return }
        isDirty = true
        rebuildIndex()
    }

    func save() throws {
        guard isDirty else { return }
        try JSONStore.write(try JSONStore.encode(File(folders: entries)), to: url)
        isDirty = false
    }

    private func rebuildIndex() {
        byIdentity = [:]
        for (path, entry) in entries {
            if let identity = entry.identity { byIdentity[identity] = path }
        }
    }
}
