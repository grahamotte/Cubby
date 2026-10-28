import XCTest
@testable import CubbyCore

final class CubbyPathsTests: XCTestCase {
    func testFilesLiveInDotConfig() {
        let paths = CubbyPaths(home: URL(filePath: "/Users/me", directoryHint: .isDirectory))
        XCTAssertEqual(paths.configDirectory.path, "/Users/me/.config/\(CubbyPaths.folderName)")
        XCTAssertEqual(paths.configFile.lastPathComponent, "config.json")
        XCTAssertEqual(paths.folderViewsFile.lastPathComponent, "folders.json")
        XCTAssertEqual(paths.sessionFile.lastPathComponent, "session.json")
        XCTAssertEqual(paths.themesDirectory.path, "/Users/me/.config/\(CubbyPaths.folderName)/themes")
        XCTAssertEqual(paths.configFile.deletingLastPathComponent().path, paths.configDirectory.path)
    }
}
