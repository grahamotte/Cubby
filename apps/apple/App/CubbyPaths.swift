import Foundation

struct CubbyPaths {
    #if CUBBY_DEV
    static let folderName = "cubby-dev"
    #else
    static let folderName = "cubby"
    #endif

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
}
