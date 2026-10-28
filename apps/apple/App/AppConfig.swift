import Foundation

struct AppConfig: Codable {
    var showHiddenFiles: Bool
    var defaultView: FolderView
    var terminal: String
    var sidebar: [SidebarNode]

    static var standard: AppConfig {
        AppConfig(
            showHiddenFiles: false,
            defaultView: .standard,
            terminal: "Terminal",
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

    init(showHiddenFiles: Bool, defaultView: FolderView, terminal: String, sidebar: [SidebarNode]) {
        self.showHiddenFiles = showHiddenFiles
        self.defaultView = defaultView
        self.terminal = terminal
        self.sidebar = sidebar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showHiddenFiles = try container.decodeIfPresent(Bool.self, forKey: .showHiddenFiles) ?? false
        defaultView = try container.decodeIfPresent(FolderView.self, forKey: .defaultView) ?? .standard
        terminal = try container.decodeIfPresent(String.self, forKey: .terminal) ?? "Terminal"
        sidebar = try container.decodeIfPresent([SidebarNode].self, forKey: .sidebar) ?? []
    }
}
