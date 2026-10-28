import XCTest
@testable import CubbyCore

final class AppConfigTests: XCTestCase {
    func testStandardHasFavorites() {
        let config = AppConfig.standard
        XCTAssertFalse(config.showHiddenFiles)
        XCTAssertEqual(config.defaultView, .standard)
        XCTAssertEqual(config.terminal, "Terminal")
        XCTAssertEqual(config.sidebar.map(\.name), ["Favorites"])
        XCTAssertTrue(config.sidebar[0].children.allSatisfy { $0.kind == .folder })
    }

    func testDecodesMissingKeysWithDefaults() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        XCTAssertFalse(config.showHiddenFiles)
        XCTAssertEqual(config.defaultView, .standard)
        XCTAssertTrue(config.sidebar.isEmpty)
        XCTAssertEqual(config.terminal, "Terminal")
    }
}
