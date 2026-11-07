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
        var profiles: [String: [String: Entry]]?
        var folders: [String: Entry]?
    }

    static let pruneThreshold = 2000

    let url: URL
    private(set) var profiles: [String: [String: Entry]] = [:]
    private var legacy: [String: Entry]?
    private var byIdentity: [String: [FolderIdentity: String]] = [:]
    private(set) var isDirty = false

    init(url: URL, legacyProfile: String?) {
        self.url = url
        if let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) {
            profiles = file.profiles ?? [:]
            if let folders = file.folders {
                if let legacyProfile {
                    profiles[legacyProfile] = folders.merging(profiles[legacyProfile] ?? [:]) { _, current in current }
                    isDirty = true
                } else {
                    legacy = folders
                }
            }
        }
        profiles = profiles.filter { !$0.value.isEmpty }
        for profile in profiles.keys {
            rebuildIndex(profile)
        }
    }

    var count: Int {
        profiles.values.reduce(0) { $0 + $1.count }
    }

    func entries(for profile: String) -> [String: Entry] {
        profiles[profile] ?? [:]
    }

    func view(for path: String, identity: FolderIdentity?, profile: String) -> FolderView? {
        if let entry = profiles[profile]?[path] {
            if entry.identity == nil || identity == nil || entry.identity == identity {
                return entry.view
            }
            update(profile) { $0[path] = nil }
            isDirty = true
            rebuildIndex(profile)
        }
        guard let identity, let oldPath = byIdentity[profile]?[identity], let entry = profiles[profile]?[oldPath] else { return nil }
        update(profile) {
            $0[oldPath] = nil
            $0[path] = entry
        }
        byIdentity[profile, default: [:]][identity] = path
        isDirty = true
        return entry.view
    }

    func setView(_ view: FolderView, for path: String, identity: FolderIdentity?, profile: String, defaultView: FolderView) {
        if let oldIdentity = profiles[profile]?[path]?.identity {
            byIdentity[profile]?[oldIdentity] = nil
        }
        if view == defaultView {
            guard profiles[profile]?[path] != nil else { return }
            update(profile) { $0[path] = nil }
        } else {
            let stalePath = identity.flatMap { byIdentity[profile]?[$0] }
            update(profile) { entries in
                if let stalePath, stalePath != path {
                    entries[stalePath] = nil
                }
                entries[path] = Entry(view: view, identity: identity)
            }
            if let identity { byIdentity[profile, default: [:]][identity] = path }
        }
        isDirty = true
    }

    func removeProfile(_ profile: String) {
        byIdentity[profile] = nil
        guard profiles.removeValue(forKey: profile) != nil else { return }
        isDirty = true
    }

    func prune(exists: (String) -> Bool) {
        guard count > FolderViewStore.pruneThreshold else { return }
        let before = count
        profiles = profiles.mapValues { $0.filter { exists($0.key) } }.filter { !$0.value.isEmpty }
        guard count != before else { return }
        isDirty = true
        byIdentity = [:]
        for profile in profiles.keys {
            rebuildIndex(profile)
        }
    }

    func save() throws {
        guard isDirty else { return }
        try JSONStore.write(try JSONStore.encode(File(profiles: profiles, folders: legacy)), to: url)
        isDirty = false
    }

    private func update(_ profile: String, _ change: (inout [String: Entry]) -> Void) {
        var entries = profiles[profile] ?? [:]
        change(&entries)
        profiles[profile] = entries.isEmpty ? nil : entries
    }

    private func rebuildIndex(_ profile: String) {
        var index: [FolderIdentity: String] = [:]
        for (path, entry) in profiles[profile] ?? [:] {
            if let identity = entry.identity { index[identity] = path }
        }
        byIdentity[profile] = index.isEmpty ? nil : index
    }
}
