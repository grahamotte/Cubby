import Foundation

final class SidebarNode: Codable {
    enum Kind: Equatable {
        case group
        case folder
    }

    let kind: Kind
    var name: String
    var path: String
    var isCollapsed: Bool
    var children: [SidebarNode]
    weak var parent: SidebarNode?

    private enum CodingKeys: String, CodingKey {
        case group
        case folder
        case name
        case items
        case collapsed
    }

    static func group(_ name: String, _ children: [SidebarNode] = [], collapsed: Bool = false) -> SidebarNode {
        let node = SidebarNode(kind: .group, name: name, path: "", isCollapsed: collapsed, children: children)
        children.forEach { $0.parent = node }
        return node
    }

    static func folder(_ path: String, name: String = "") -> SidebarNode {
        SidebarNode(kind: .folder, name: name, path: path, isCollapsed: false, children: [])
    }

    private init(kind: Kind, name: String, path: String, isCollapsed: Bool, children: [SidebarNode]) {
        self.kind = kind
        self.name = name
        self.path = path
        self.isCollapsed = isCollapsed
        self.children = children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let path = try container.decodeIfPresent(String.self, forKey: .folder) {
            kind = .folder
            self.path = path
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            isCollapsed = false
            children = []
        } else if let name = try container.decodeIfPresent(String.self, forKey: .group) {
            kind = .group
            self.name = name
            path = ""
            isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
            children = try container.decodeIfPresent([SidebarNode].self, forKey: .items) ?? []
            children.forEach { $0.parent = self }
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Sidebar items need a \"group\" or \"folder\" key"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch kind {
        case .folder:
            try container.encode(path, forKey: .folder)
            if !name.isEmpty {
                try container.encode(name, forKey: .name)
            }
        case .group:
            try container.encode(name, forKey: .group)
            if isCollapsed {
                try container.encode(true, forKey: .collapsed)
            }
            try container.encode(children, forKey: .items)
        }
    }

    var url: URL? {
        kind == .folder ? URL(filePath: (path as NSString).expandingTildeInPath, directoryHint: .isDirectory) : nil
    }

    var displayName: String {
        if !name.isEmpty { return name }
        guard let url else { return name }
        return url.path == "/" ? "Macintosh HD" : url.lastPathComponent
    }

    func isDescendant(of node: SidebarNode) -> Bool {
        var current = parent
        while let candidate = current {
            if candidate === node { return true }
            current = candidate.parent
        }
        return false
    }
}
