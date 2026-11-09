import XCTest
@testable import CubbyCore

final class CubbyPathsTests: XCTestCase {
    func testFilesLiveInDotConfig() {
        let paths = CubbyPaths(home: URL(filePath: "/Users/me", directoryHint: .isDirectory))
        XCTAssertEqual(paths.configDirectory.path, "/Users/me/.config/\(CubbyPaths.folderName)")
        XCTAssertEqual(paths.configFile.lastPathComponent, "config.json")
        XCTAssertEqual(paths.folderViewsFile.lastPathComponent, "folders.json")
        XCTAssertEqual(paths.sessionFile.lastPathComponent, "session.json")
        XCTAssertEqual(paths.historyFile.lastPathComponent, "history.json")
        XCTAssertEqual(paths.themesDirectory.path, "/Users/me/.config/\(CubbyPaths.folderName)/themes")
        XCTAssertEqual(paths.configFile.deletingLastPathComponent().path, paths.configDirectory.path)
    }

    func testDevFolderKeepsMainCheckoutName() {
        XCTAssertEqual(CubbyPaths.devFolderName(bundleIdentifier: "com.grahamotte.cubby.debug"), "cubby-dev")
        XCTAssertEqual(CubbyPaths.devFolderName(bundleIdentifier: nil), "cubby-dev")
        XCTAssertEqual(CubbyPaths.devFolderName(bundleIdentifier: "com.grahamotte.cubby"), "cubby-dev")
    }

    func testDevFolderFollowsWorktreeBundleIdentifier() {
        XCTAssertEqual(CubbyPaths.devFolderName(bundleIdentifier: "com.grahamotte.cubby.debug.cub-12"), "cubby-dev.cub-12")
        XCTAssertNotEqual(
            CubbyPaths.devFolderName(bundleIdentifier: "com.grahamotte.cubby.debug.cub-12"),
            CubbyPaths.devFolderName(bundleIdentifier: "com.grahamotte.cubby.debug.cub-13")
        )
    }
}
