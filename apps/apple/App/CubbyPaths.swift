import Foundation

struct CubbyPaths {
    #if CUBBY_DEV
    static let folderName = devFolderName(bundleIdentifier: Bundle.main.bundleIdentifier)
    #else
    static let folderName = "cubby"
    #endif

    static func devFolderName(bundleIdentifier: String?) -> String {
        let components = bundleIdentifier?.split(separator: ".") ?? []
        guard let debug = components.firstIndex(of: "debug"), debug + 1 < components.count else { return "cubby-dev" }
        return (["cubby-dev"] + components[(debug + 1)...]).joined(separator: ".")
    }

    let home: URL
    let configDirectory: URL

    init(home: URL) {
        self.home = home
        configDirectory = home.appending(path: ".config/\(CubbyPaths.folderName)", directoryHint: .isDirectory)
    }

    static var standard: CubbyPaths {
        CubbyPaths(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    var configFile: URL { configDirectory.appending(path: "config.json") }
    var folderViewsFile: URL { configDirectory.appending(path: "folders.json") }
    var sessionFile: URL { configDirectory.appending(path: "session.json") }
    var historyFile: URL { configDirectory.appending(path: "history.json") }
    var themesDirectory: URL { configDirectory.appending(path: "themes", directoryHint: .isDirectory) }
}
