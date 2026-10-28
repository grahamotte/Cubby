import Foundation

struct SessionState: Codable, Equatable {
    struct Tab: Codable, Equatable {
        var layout: PaneLayout
        var paths: [String]
        var activePane: Int

        init(layout: PaneLayout, paths: [String], activePane: Int) {
            self.layout = layout
            self.paths = paths
            self.activePane = activePane
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            layout = (try? container.decodeIfPresent(PaneLayout.self, forKey: .layout)) ?? .single
            paths = try container.decodeIfPresent([String].self, forKey: .paths) ?? []
            activePane = try container.decodeIfPresent(Int.self, forKey: .activePane) ?? 0
        }

        func normalized(home: String, exists: (String) -> Bool) -> Tab {
            let count = layout.paneCount
            var result = Array(paths.prefix(count)).map { exists($0) ? $0 : home }
            while result.count < count {
                result.append(result.last ?? home)
            }
            return Tab(layout: layout, paths: result, activePane: min(max(activePane, 0), count - 1))
        }
    }

    struct Window: Codable, Equatable {
        var frame: String?
        var sidebarWidth: Double?
        var tabs: [Tab]
        var selectedTab: Int
    }

    struct Column: Codable, Equatable {
        var id: String
        var width: Double
        var hidden: Bool
    }

    var windows: [Window]
    var listColumns: [Column]?

    static func load(from url: URL) -> SessionState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SessionState.self, from: data)
    }

    func save(to url: URL) throws {
        try JSONStore.write(try JSONStore.encode(self), to: url)
    }
}
