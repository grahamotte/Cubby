import Foundation

struct AppConfig: Codable {
    var showHiddenFiles: Bool
    var defaultView: FolderView
    var terminal: String
    var appearance: ColorScheme
    var theme: String
    var sidebar: [SidebarNode]

    static var standard: AppConfig {
        AppConfig(
            showHiddenFiles: false,
            defaultView: .standard,
            terminal: "Terminal",
            appearance: .system,
            theme: ThemeLibrary.defaultID,
            sidebar: [
                SidebarNode.group("Favorites", [
                    SidebarNode.folder("~"),
                    SidebarNode.folder("~/Desktop"),
                    SidebarNode.folder("~/Documents"),
                    SidebarNode.folder("~/Downloads"),
                    SidebarNode.folder("/Applications"),
                ]),
            ],
        )
    }

    init(showHiddenFiles: Bool, defaultView: FolderView, terminal: String, appearance: ColorScheme, theme: String, sidebar: [SidebarNode]) {
        self.showHiddenFiles = showHiddenFiles
        self.defaultView = defaultView
        self.terminal = terminal
        self.appearance = appearance
        self.theme = theme
        self.sidebar = sidebar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showHiddenFiles = try container.decodeIfPresent(Bool.self, forKey: .showHiddenFiles) ?? false
        defaultView = try container.decodeIfPresent(FolderView.self, forKey: .defaultView) ?? .standard
        terminal = try container.decodeIfPresent(String.self, forKey: .terminal) ?? "Terminal"
        appearance = try container.decodeIfPresent(ColorScheme.self, forKey: .appearance) ?? .system
        theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? ThemeLibrary.defaultID
        sidebar = try container.decodeIfPresent([SidebarNode].self, forKey: .sidebar) ?? []
    }
}
