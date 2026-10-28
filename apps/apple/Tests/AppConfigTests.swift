import XCTest
@testable import CubbyCore

final class AppConfigTests: XCTestCase {
    func testStandardHasFavorites() {
        let config = AppConfig.standard
        XCTAssertFalse(config.showHiddenFiles)
        XCTAssertEqual(config.defaultView, .standard)
        XCTAssertEqual(config.terminal, "Terminal")
        XCTAssertEqual(config.appearance, .system)
        XCTAssertEqual(config.theme, "workbench")
        XCTAssertEqual(config.sidebar.map(\.name), ["Favorites"])
        XCTAssertTrue(config.sidebar[0].children.allSatisfy { $0.kind == .folder })
    }

    func testDecodesMissingKeysWithDefaults() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        XCTAssertFalse(config.showHiddenFiles)
        XCTAssertEqual(config.defaultView, .standard)
        XCTAssertTrue(config.sidebar.isEmpty)
        XCTAssertEqual(config.terminal, "Terminal")
        XCTAssertEqual(config.appearance, .system)
        XCTAssertEqual(config.theme, ThemeLibrary.defaultID)
    }

    func testDecodesAppearanceAndTheme() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"appearance":"dark","theme":"grove"}"#.utf8))
        XCTAssertEqual(config.appearance, .dark)
        XCTAssertEqual(config.theme, "grove")
    }

    func testRejectsUnknownAppearance() {
        XCTAssertThrowsError(try JSONDecoder().decode(AppConfig.self, from: Data(#"{"appearance":"sepia"}"#.utf8)))
    }
}
