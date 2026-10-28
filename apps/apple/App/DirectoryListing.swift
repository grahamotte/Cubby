import Foundation

enum DirectoryListing {
    static func merge(old: [FileItem], new: [FileItem]) -> [FileItem] {
        guard !old.isEmpty else { return new }
        var existing: [String: FileItem] = [:]
        existing.reserveCapacity(old.count)
        for item in old {
            existing[item.name] = item
        }
        return new.map { item in
            guard let previous = existing[item.name], previous.isDirectory == item.isDirectory, previous.fileID == item.fileID else { return item }
            if !previous.sameEntry(as: item) {
                previous.update(from: item)
            }
            return previous
        }
    }

    static func reconcile(old: [FileItem], new: [FileItem], visible: [FileItem]) -> (all: [FileItem], visible: [FileItem]) {
        let all = merge(old: old, new: new)
        guard !old.isEmpty else { return (all, visible) }
        var canonical: [ObjectIdentifier: FileItem] = [:]
        canonical.reserveCapacity(all.count)
        for (fresh, kept) in zip(new, all) where fresh !== kept {
            canonical[ObjectIdentifier(fresh)] = kept
        }
        return (all, visible.map { canonical[ObjectIdentifier($0)] ?? $0 })
    }

    static func indexes(of names: Set<String>, in items: [FileItem]) -> IndexSet {
        var result = IndexSet()
        for (index, item) in items.enumerated() where names.contains(item.name) {
            result.insert(index)
        }
        return result
    }
}
