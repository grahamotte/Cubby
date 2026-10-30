import Foundation

extension Notification.Name {
    static let pendingChangesChanged = Notification.Name("CubbyPendingChangesChanged")
}

struct PendingChange {
    var removed: [URL] = []
    var added: [Transfer] = []

    static func move(_ urls: [URL], to directory: URL) -> PendingChange {
        let transfers = placements(urls, in: directory)
        return PendingChange(removed: transfers.map(\.source), added: transfers)
    }

    static func copy(_ urls: [URL], to directory: URL) -> PendingChange {
        PendingChange(added: placements(urls, in: directory))
    }

    static func remove(_ urls: [URL]) -> PendingChange {
        PendingChange(removed: urls)
    }

    static func moveBack(_ transfers: [Transfer]) -> PendingChange {
        PendingChange(removed: transfers.map(\.destination), added: transfers.map { Transfer(source: $0.destination, destination: $0.source) })
    }

    private static func placements(_ urls: [URL], in directory: URL) -> [Transfer] {
        let directoryPath = PendingSnapshot.resolve(directory.path)
        var resolved: [String: String] = [:]
        return urls
            .filter { url in
                let parent = url.deletingLastPathComponent().path
                if resolved[parent] == nil { resolved[parent] = PendingSnapshot.resolve(parent) }
                return resolved[parent] != directoryPath
            }
            .map { Transfer(source: $0, destination: directory.appending(path: $0.lastPathComponent)) }
    }
}

struct DirectoryChanges: Equatable {
    var removed: Set<String> = []
    var added: Set<String> = []

    func isSubset(of other: DirectoryChanges) -> Bool {
        removed.isSubset(of: other.removed) && added.isSubset(of: other.added)
    }
}

struct PendingSnapshot: Equatable {
    fileprivate(set) var removed: [String: Set<String>] = [:]
    fileprivate(set) var added: [String: [String: FileItem]] = [:]

    var isEmpty: Bool { removed.isEmpty && added.isEmpty }

    static func == (lhs: PendingSnapshot, rhs: PendingSnapshot) -> Bool {
        lhs.removed == rhs.removed && lhs.added.mapValues { Set($0.keys) } == rhs.added.mapValues { Set($0.keys) }
    }

    func changes(in directory: String) -> DirectoryChanges {
        guard !isEmpty else { return DirectoryChanges() }
        let key = Self.resolve(directory)
        return DirectoryChanges(removed: removed[key] ?? [], added: Set((added[key] ?? [:]).keys))
    }

    func applied(to items: [FileItem], in directory: String) -> [FileItem] {
        guard !isEmpty else { return items }
        let key = Self.resolve(directory)
        let removed = removed[key] ?? []
        let added = added[key] ?? [:]
        var result = removed.isEmpty ? items : items.filter { !removed.contains($0.name) }
        guard !added.isEmpty else { return result }
        let present = Set(result.map(\.name))
        for (name, item) in added.sorted(by: { $0.key < $1.key }) where !present.contains(name) && !removed.contains(name) {
            result.append(item.directory == directory ? item : item.placed(in: directory))
        }
        return result
    }

    static func resolve(_ directory: String) -> String {
        URL(filePath: directory, directoryHint: .isDirectory).resolvingSymlinksInPath().path
    }
}

@MainActor
final class PendingChanges {
    static let shared = PendingChanges()

    private(set) var snapshot = PendingSnapshot()
    private var entries: [Int: PendingSnapshot] = [:]
    private var nextToken = 1

    func begin(_ change: PendingChange) -> Int {
        let token = nextToken
        nextToken += 1
        guard !change.removed.isEmpty || !change.added.isEmpty else { return token }
        var entry = PendingSnapshot()
        var directories: [String: String] = [:]
        func split(_ url: URL) -> (String, String) {
            let path = url.standardizedFileURL.path as NSString
            let parent = path.deletingLastPathComponent
            if directories[parent] == nil { directories[parent] = PendingSnapshot.resolve(parent) }
            return (directories[parent]!, path.lastPathComponent)
        }
        for url in change.removed {
            let (directory, name) = split(url)
            entry.removed[directory, default: []].insert(name)
        }
        for transfer in change.added {
            guard !FileManager.default.fileExists(atPath: transfer.destination.path), let item = DirectoryReader.item(at: transfer.source) else { continue }
            let (directory, name) = split(transfer.destination)
            entry.added[directory, default: [:]][name] = item.placed(in: transfer.destination.deletingLastPathComponent().standardizedFileURL.path, name: name)
        }
        entries[token] = entry
        rebuild()
        return token
    }

    func end(_ token: Int) {
        guard entries.removeValue(forKey: token) != nil else { return }
        rebuild()
    }

    private func rebuild() {
        var snapshot = PendingSnapshot()
        for entry in entries.values {
            snapshot.removed.merge(entry.removed) { $0.union($1) }
            snapshot.added.merge(entry.added) { $0.merging($1) { first, _ in first } }
        }
        self.snapshot = snapshot
        NotificationCenter.default.post(name: .pendingChangesChanged, object: self)
    }
}
