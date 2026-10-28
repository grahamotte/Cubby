import Foundation

struct SidebarProfile: Codable {
    static let icons = [
        "person",
        "briefcase",
        "house",
        "star",
        "heart",
        "bolt",
        "leaf",
        "flame",
        "book",
        "hammer",
        "paintbrush",
        "music.note",
        "gamecontroller",
        "camera",
        "globe.americas",
        "graduationcap",
        "building.2",
        "airplane",
        "terminal",
        "moon",
    ]

    var name: String
    var icon: String
    let tree: SidebarTree

    private enum CodingKeys: String, CodingKey {
        case name
        case icon
        case sidebar
    }

    init(name: String, icon: String, sidebar: [SidebarNode] = []) {
        self.name = name
        self.icon = icon
        tree = SidebarTree(nodes: sidebar)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Profile"
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? SidebarProfile.icons[0]
        tree = SidebarTree(nodes: try container.decodeIfPresent([SidebarNode].self, forKey: .sidebar) ?? [])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)
        try container.encode(tree.nodes, forKey: .sidebar)
    }

    static func personal(_ sidebar: [SidebarNode]) -> SidebarProfile {
        SidebarProfile(name: "Personal", icon: "person", sidebar: sidebar)
    }

    static func make(after profiles: [SidebarProfile]) -> SidebarProfile {
        let names = Set(profiles.map(\.name))
        let name = (1...).lazy.map { $0 == 1 ? "New Profile" : "New Profile \($0)" }.first { !names.contains($0) }!
        let used = Set(profiles.map(\.icon))
        let icon = icons.first { !used.contains($0) } ?? icons[profiles.count % icons.count]
        return SidebarProfile(name: name, icon: icon)
    }

    @discardableResult
    mutating func rename(to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != self.name else { return false }
        self.name = trimmed
        return true
    }
}
