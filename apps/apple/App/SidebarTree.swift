import Foundation

final class SidebarTree {
    let root: SidebarNode
    let home: String

    init(nodes: [SidebarNode], home: String = NSHomeDirectory()) {
        root = SidebarNode.group("", nodes)
        self.home = home
    }

    var nodes: [SidebarNode] { root.children }

    func children(of parent: SidebarNode?) -> [SidebarNode] {
        (parent ?? root).children
    }

    func canInsert(into parent: SidebarNode?) -> Bool {
        (parent ?? root).kind == .group
    }

    @discardableResult
    func insert(_ node: SidebarNode, into parent: SidebarNode?, at index: Int? = nil) -> Bool {
        let target = parent ?? root
        guard target.kind == .group, target !== node, !target.isDescendant(of: node) else { return false }
        let position = min(max(index ?? target.children.count, 0), target.children.count)
        target.children.insert(node, at: position)
        node.parent = target
        return true
    }

    @discardableResult
    func move(_ node: SidebarNode, into parent: SidebarNode?, at index: Int) -> Bool {
        let target = parent ?? root
        guard node !== root, target.kind == .group, target !== node, !target.isDescendant(of: node), let source = node.parent,
              let sourceIndex = source.children.firstIndex(where: { $0 === node }) else { return false }
        var position = min(max(index, 0), target.children.count)
        if source === target && sourceIndex < position {
            position -= 1
        }
        source.children.remove(at: sourceIndex)
        target.children.insert(node, at: min(position, target.children.count))
        node.parent = target
        return true
    }

    func remove(_ node: SidebarNode) {
        guard let parent = node.parent else { return }
        parent.children.removeAll { $0 === node }
        node.parent = nil
    }

    @discardableResult
    func rename(_ node: SidebarNode, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch node.kind {
        case .group:
            guard !trimmed.isEmpty else { return false }
            node.name = trimmed
        case .folder:
            node.name = trimmed == node.url?.lastPathComponent ? "" : trimmed
        }
        return true
    }

    func makeFolder(_ url: URL) -> SidebarNode {
        SidebarNode.folder(abbreviate(url.standardizedFileURL.path))
    }

    func abbreviate(_ path: String) -> String {
        var trimmed = path
        while trimmed.count > 1 && trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if trimmed == home { return "~" }
        if trimmed.hasPrefix(home + "/") { return "~" + trimmed.dropFirst(home.count) }
        return trimmed
    }

    func folders() -> [SidebarNode] {
        var result: [SidebarNode] = []
        func walk(_ node: SidebarNode) {
            if node.kind == .folder { result.append(node) }
            node.children.forEach(walk)
        }
        root.children.forEach(walk)
        return result
    }

    func updateFolders(movedFrom oldPath: String, to newPath: String) -> Bool {
        var changed = false
        for folder in folders() {
            guard let path = folder.url?.standardizedFileURL.path else { continue }
            if path == oldPath {
                folder.path = abbreviate(newPath)
                changed = true
            } else if path.hasPrefix(oldPath + "/") {
                folder.path = abbreviate(newPath + path.dropFirst(oldPath.count))
                changed = true
            }
        }
        return changed
    }
}
