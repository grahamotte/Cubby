import Foundation

enum ColorScheme: String, Codable, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum ThemeRole: String, CaseIterable {
    case content
    case sidebar
    case card
    case divider
    case text
    case secondaryText
    case tertiaryText
    case icon
    case sidebarText
    case sidebarSecondaryText
    case accent
    case accentText
    case warning
}

enum ThemeColor: Equatable {
    case rgba(red: Double, green: Double, blue: Double, alpha: Double)
    case systemAccent

    init?(_ string: String) {
        if string == "system" {
            self = .systemAccent
            return
        }
        let hex = string.dropFirst()
        guard string.hasPrefix("#"), hex.count == 6 || hex.count == 8, hex.allSatisfy(\.isHexDigit), let value = UInt64(hex, radix: 16) else { return nil }
        let rgba = hex.count == 6 ? value << 8 | 0xFF : value
        self = .rgba(
            red: Double(rgba >> 24 & 0xFF) / 255,
            green: Double(rgba >> 16 & 0xFF) / 255,
            blue: Double(rgba >> 8 & 0xFF) / 255,
            alpha: Double(rgba & 0xFF) / 255,
        )
    }

    var string: String {
        switch self {
        case .systemAccent:
            return "system"
        case .rgba(let red, let green, let blue, let alpha):
            let components = [red, green, blue] + (alpha < 1 ? [alpha] : [])
            return "#" + components.map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
        }
    }
}

struct ThemePalette: Equatable {
    private(set) var colors: [ThemeRole: ThemeColor]

    init(_ colors: [ThemeRole: String]) {
        self.colors = colors.mapValues { ThemeColor($0)! }
    }

    init(colors: [ThemeRole: ThemeColor]) {
        self.colors = colors
    }

    subscript(role: ThemeRole) -> ThemeColor {
        colors[role] ?? .systemAccent
    }

    func merging(_ values: [String: String]) throws -> ThemePalette {
        var palette = self
        for (key, value) in values {
            guard let role = ThemeRole(rawValue: key) else { throw ThemeLibrary.ThemeError("\"\(key)\" is not a theme color role") }
            guard let color = ThemeColor(value) else { throw ThemeLibrary.ThemeError("\"\(value)\" for \(key) is not a color like #RRGGBB, #RRGGBBAA, or system") }
            palette.colors[role] = color
        }
        return palette
    }

    var strings: [String: String] {
        Dictionary(uniqueKeysWithValues: ThemeRole.allCases.map { ($0.rawValue, self[$0].string) })
    }
}

struct ThemeDefinition: Equatable {
    let id: String
    let name: String
    let light: ThemePalette
    let dark: ThemePalette

    func palette(dark isDark: Bool) -> ThemePalette {
        isDark ? dark : light
    }
}

struct ThemeLibrary: Equatable {
    struct ThemeError: LocalizedError {
        let message: String

        init(_ message: String) {
            self.message = message
        }

        var errorDescription: String? { message }
    }

    private struct ThemeFile: Codable {
        var name: String
        var light: [String: String]
        var dark: [String: String]
    }

    static let defaultID = "workbench"

    static let builtIn: [ThemeDefinition] = [
        ThemeDefinition(
            id: "workbench",
            name: "Workbench",
            light: ThemePalette([.content: "#FCFCFB", .sidebar: "#F1F1EF", .card: "#FFFFFF", .divider: "#00000012", .text: "#000000D9", .secondaryText: "#00000080", .tertiaryText: "#00000042", .icon: "#00000080", .sidebarText: "#000000D9", .sidebarSecondaryText: "#00000042", .accent: "system", .accentText: "#FFFFFF", .warning: "#FF9500"]),
            dark: ThemePalette([.content: "#1E1F21", .sidebar: "#17181A", .card: "#28292B", .divider: "#FFFFFF12", .text: "#FFFFFFD9", .secondaryText: "#FFFFFF8C", .tertiaryText: "#FFFFFF40", .icon: "#FFFFFF8C", .sidebarText: "#FFFFFFD9", .sidebarSecondaryText: "#FFFFFF40", .accent: "system", .accentText: "#FFFFFF", .warning: "#FF9F0A"]),
        ),
        ThemeDefinition(
            id: "t3-code",
            name: "T3 Code",
            light: ThemePalette([.content: "#FCFCFC", .sidebar: "#FAFAFA", .card: "#FFFFFF", .divider: "#E4E4E7", .text: "#27272A", .secondaryText: "#71717B", .tertiaryText: "#71717BB3", .icon: "#71717B", .sidebarText: "#27272A", .sidebarSecondaryText: "#71717B", .accent: "#1B4ED8", .accentText: "#FFFFFF", .warning: "#FE9A00"]),
            dark: ThemePalette([.content: "#0A0A0A", .sidebar: "#000000", .card: "#111111", .divider: "#191919", .text: "#F5F5F5", .secondaryText: "#818181", .tertiaryText: "#818181B3", .icon: "#818181", .sidebarText: "#F1F3F7", .sidebarSecondaryText: "#A3A3A3", .accent: "#346BF1", .accentText: "#FFFFFF", .warning: "#FE9A00"]),
        ),
        ThemeDefinition(
            id: "t3-chat",
            name: "T3 Chat",
            light: ThemePalette([.content: "#FDF7FD", .sidebar: "#F2E1F4", .card: "#FAF3FB", .divider: "#EEE1ED", .text: "#501854", .secondaryText: "#AC1668", .tertiaryText: "#AC1668B3", .icon: "#AC1668", .sidebarText: "#454554", .sidebarSecondaryText: "#AC1668", .accent: "#DB2777", .accentText: "#FFFFFF", .warning: "#F59E0B"]),
            dark: ThemePalette([.content: "#1F1A24", .sidebar: "#171018", .card: "#29232D", .divider: "#27242C", .text: "#F9F8FB", .secondaryText: "#E7D0DD", .tertiaryText: "#E7D0DDB3", .icon: "#D4C7E1", .sidebarText: "#F4F4F5", .sidebarSecondaryText: "#E7D0DD", .accent: "#A3004C", .accentText: "#FBD0E8", .warning: "#F59E0B"]),
        ),
        ThemeDefinition(
            id: "grove",
            name: "Grove",
            light: ThemePalette([.content: "#F3F7F4", .sidebar: "#E2EDE7", .card: "#F3F7F4", .divider: "#CBD5D1", .text: "#241523", .secondaryText: "#746C73", .tertiaryText: "#746C73B3", .icon: "#746C73", .sidebarText: "#241523", .sidebarSecondaryText: "#6B666C", .accent: "#1B7D50", .accentText: "#FFFAFF", .warning: "#FE9A00"]),
            dark: ThemePalette([.content: "#1B2821", .sidebar: "#21362B", .card: "#1B2821", .divider: "#415F4F", .text: "#FFFAFF", .secondaryText: "#919595", .tertiaryText: "#919595B3", .icon: "#919595", .sidebarText: "#FFFAFF", .sidebarSecondaryText: "#9DA3A2", .accent: "#69D69A", .accentText: "#241523", .warning: "#FE9A00"]),
        ),
        ThemeDefinition(
            id: "ocean",
            name: "Ocean",
            light: ThemePalette([.content: "#F5F7F8", .sidebar: "#E4ECF2", .card: "#F5F7F8", .divider: "#CDD4DC", .text: "#241523", .secondaryText: "#746C75", .tertiaryText: "#746C75B3", .icon: "#746C75", .sidebarText: "#241523", .sidebarSecondaryText: "#6C6570", .accent: "#2672AF", .accentText: "#FFFAFF", .warning: "#FE9A00"]),
            dark: ThemePalette([.content: "#17212B", .sidebar: "#1E2D3B", .card: "#17212B", .divider: "#405567", .text: "#FFFAFF", .secondaryText: "#8D8F97", .tertiaryText: "#8D8F97B3", .icon: "#8D8F97", .sidebarText: "#FFFAFF", .sidebarSecondaryText: "#989CA5", .accent: "#70B9EE", .accentText: "#241523", .warning: "#FE9A00"]),
        ),
        ThemeDefinition(
            id: "ember",
            name: "Ember",
            light: ThemePalette([.content: "#F9F7F5", .sidebar: "#F3EAE5", .card: "#F9F7F5", .divider: "#DDD2CE", .text: "#241523", .secondaryText: "#766C74", .tertiaryText: "#766C74B3", .icon: "#766C74", .sidebarText: "#241523", .sidebarSecondaryText: "#71646B", .accent: "#AE552A", .accentText: "#FFFAFF", .warning: "#FE9A00"]),
            dark: ThemePalette([.content: "#291E1A", .sidebar: "#39281F", .card: "#291E1A", .divider: "#664C3F", .text: "#FFFAFF", .secondaryText: "#968E8F", .tertiaryText: "#968E8FB3", .icon: "#968E8F", .sidebarText: "#FFFAFF", .sidebarSecondaryText: "#A49998", .accent: "#F09A64", .accentText: "#241523", .warning: "#FE9A00"]),
        ),
        ThemeDefinition(
            id: "iris",
            name: "Iris",
            light: ThemePalette([.content: "#F8F7F9", .sidebar: "#EDEAF4", .card: "#F8F7F9", .divider: "#D6D1DE", .text: "#241523", .secondaryText: "#766C76", .tertiaryText: "#766C76B3", .icon: "#766C76", .sidebarText: "#241523", .sidebarSecondaryText: "#6F6471", .accent: "#7253B9", .accentText: "#FFFAFF", .warning: "#FE9A00"]),
            dark: ThemePalette([.content: "#1D1929", .sidebar: "#272139", .card: "#1D1929", .divider: "#4D4366", .text: "#FFFAFF", .secondaryText: "#8E8A95", .tertiaryText: "#8E8A95B3", .icon: "#8E8A95", .sidebarText: "#FFFAFF", .sidebarSecondaryText: "#9792A0", .accent: "#9D7DF2", .accentText: "#241523", .warning: "#FE9A00"]),
        ),
    ]

    let themes: [ThemeDefinition]
    let errors: [String]

    init(themes: [ThemeDefinition] = ThemeLibrary.builtIn, errors: [String] = []) {
        self.themes = themes
        self.errors = errors
    }

    init(directory: URL) {
        var themes = ThemeLibrary.builtIn
        var errors: [String] = []
        for url in ThemeLibrary.files(in: directory) {
            let id = url.deletingPathExtension().lastPathComponent
            do {
                guard !themes.contains(where: { $0.id == id }) else { throw ThemeError("the theme id \(id) is already used") }
                themes.append(try ThemeLibrary.parse(try Data(contentsOf: url), id: id))
            } catch {
                errors.append("\(url.lastPathComponent): \(ConfigStore.describe(error))")
            }
        }
        self.init(themes: themes, errors: errors)
    }

    static func files(in directory: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return urls.filter { $0.pathExtension.lowercased() == "json" }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func theme(id: String) -> ThemeDefinition {
        themes.first { $0.id == id } ?? ThemeLibrary.builtIn[0]
    }

    func isBuiltIn(_ theme: ThemeDefinition) -> Bool {
        ThemeLibrary.builtIn.contains { $0.id == theme.id }
    }

    static func parse(_ data: Data, id: String) throws -> ThemeDefinition {
        let file = try JSONDecoder().decode(ThemeFile.self, from: data)
        let name = file.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ThemeError("the theme needs a name") }
        let base = builtIn[0]
        return ThemeDefinition(id: id, name: name, light: try base.light.merging(file.light), dark: try base.dark.merging(file.dark))
    }

    static func encode(_ theme: ThemeDefinition) throws -> Data {
        try JSONStore.encode(ThemeFile(name: theme.name, light: theme.light.strings, dark: theme.dark.strings))
    }

    func duplicate(_ theme: ThemeDefinition, into directory: URL) throws -> ThemeDefinition {
        let taken = Set(themes.map(\.id)).union(ThemeLibrary.files(in: directory).map { $0.deletingPathExtension().lastPathComponent })
        let name = "\(theme.name) Copy"
        let base = ThemeLibrary.slug(name)
        var id = base
        var number = 2
        while taken.contains(id) {
            id = "\(base)-\(number)"
            number += 1
        }
        let copy = ThemeDefinition(id: id, name: name, light: theme.light, dark: theme.dark)
        try JSONStore.write(try ThemeLibrary.encode(copy), to: directory.appending(path: "\(id).json"))
        return copy
    }

    static func slug(_ name: String) -> String {
        let words = name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return words.isEmpty ? "theme" : words.joined(separator: "-")
    }
}
