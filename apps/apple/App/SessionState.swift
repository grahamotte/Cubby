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
        var tabs: [Tab?]
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

struct ProfileTabs: Equatable {
    private(set) var tabs: [SessionState.Tab?]
    private(set) var profile: Int?

    init(tabs: [SessionState.Tab?], profile: Int?) {
        self.tabs = tabs
        self.profile = profile
    }

    init(tab: SessionState.Tab, profile: Int) {
        tabs = Array(repeating: nil, count: max(profile, 0)) + [tab]
        self.profile = max(profile, 0)
    }

    func tab(for index: Int) -> SessionState.Tab? {
        tabs.indices.contains(index) ? tabs[index] : nil
    }

    mutating func select(_ index: Int, live: SessionState.Tab) -> SessionState.Tab? {
        if let profile {
            store(live, at: profile)
        }
        profile = index
        return tab(for: index)
    }

    mutating func remove(_ index: Int) {
        if tabs.indices.contains(index) {
            tabs.remove(at: index)
        }
        guard let current = profile else { return }
        if current == index {
            profile = nil
        } else if current > index {
            profile = current - 1
        }
    }

    func saving(_ live: SessionState.Tab) -> [SessionState.Tab?] {
        var copy = self
        if let profile {
            copy.store(live, at: profile)
        }
        return copy.tabs
    }

    private mutating func store(_ tab: SessionState.Tab, at index: Int) {
        guard index >= 0 else { return }
        while tabs.count <= index {
            tabs.append(nil)
        }
        tabs[index] = tab
    }
}
