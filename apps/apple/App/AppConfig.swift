import Foundation

struct AppConfig: Codable {
    var showHiddenFiles: Bool
    var defaultView: FolderView
    var terminal: String
    var appearance: ColorScheme
    var theme: String
    private(set) var profiles: [SidebarProfile]
    private(set) var profile: Int

    private enum CodingKeys: String, CodingKey {
        case showHiddenFiles
        case defaultView
        case terminal
        case appearance
        case theme
        case profiles
        case profile
        case sidebar
    }

    static var standard: AppConfig {
        AppConfig(
            showHiddenFiles: false,
            defaultView: .standard,
            terminal: "Terminal",
            appearance: .system,
            theme: ThemeLibrary.defaultID,
            profiles: [
                SidebarProfile.personal([
                    SidebarNode.group("Favorites", [
                        SidebarNode.folder("~"),
                        SidebarNode.folder("~/Desktop"),
                        SidebarNode.folder("~/Documents"),
                        SidebarNode.folder("~/Downloads"),
                        SidebarNode.folder("/Applications"),
                    ]),
                ]),
            ],
        )
    }

    init(showHiddenFiles: Bool, defaultView: FolderView, terminal: String, appearance: ColorScheme, theme: String, profiles: [SidebarProfile], profile: Int = 0) {
        self.showHiddenFiles = showHiddenFiles
        self.defaultView = defaultView
        self.terminal = terminal
        self.appearance = appearance
        self.theme = theme
        self.profiles = profiles.isEmpty ? [SidebarProfile.personal([])] : profiles
        self.profile = min(max(profile, 0), self.profiles.count - 1)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var profiles = try container.decodeIfPresent([SidebarProfile].self, forKey: .profiles) ?? []
        if profiles.isEmpty {
            profiles = [SidebarProfile.personal(try container.decodeIfPresent([SidebarNode].self, forKey: .sidebar) ?? [])]
        }
        self.init(
            showHiddenFiles: try container.decodeIfPresent(Bool.self, forKey: .showHiddenFiles) ?? false,
            defaultView: try container.decodeIfPresent(FolderView.self, forKey: .defaultView) ?? .standard,
            terminal: try container.decodeIfPresent(String.self, forKey: .terminal) ?? "Terminal",
            appearance: try container.decodeIfPresent(ColorScheme.self, forKey: .appearance) ?? .system,
            theme: try container.decodeIfPresent(String.self, forKey: .theme) ?? ThemeLibrary.defaultID,
            profiles: profiles,
            profile: try container.decodeIfPresent(Int.self, forKey: .profile) ?? 0,
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showHiddenFiles, forKey: .showHiddenFiles)
        try container.encode(defaultView, forKey: .defaultView)
        try container.encode(terminal, forKey: .terminal)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(theme, forKey: .theme)
        try container.encode(profiles, forKey: .profiles)
        try container.encode(profile, forKey: .profile)
    }

    var sidebar: SidebarTree {
        profiles[profile].tree
    }

    @discardableResult
    mutating func addProfile() -> Int {
        profiles.append(SidebarProfile.make(after: profiles))
        return profiles.count - 1
    }

    @discardableResult
    mutating func removeProfile(at index: Int) -> Bool {
        guard profiles.count > 1, profiles.indices.contains(index) else { return false }
        profiles.remove(at: index)
        if index < profile || profile == profiles.count {
            profile -= 1
        }
        return true
    }

    @discardableResult
    mutating func selectProfile(_ index: Int) -> Bool {
        guard profiles.indices.contains(index), index != profile else { return false }
        profile = index
        return true
    }

    @discardableResult
    mutating func renameProfile(at index: Int, to name: String) -> Bool {
        guard profiles.indices.contains(index) else { return false }
        return profiles[index].rename(to: name)
    }

    @discardableResult
    mutating func setProfileIcon(at index: Int, to icon: String) -> Bool {
        guard profiles.indices.contains(index), profiles[index].icon != icon else { return false }
        profiles[index].icon = icon
        return true
    }

    func updateFolders(movedFrom oldPath: String, to newPath: String) -> Bool {
        profiles.map { $0.tree.updateFolders(movedFrom: oldPath, to: newPath) }.contains(true)
    }
}
