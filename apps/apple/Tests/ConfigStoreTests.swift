import XCTest
@testable import CubbyCore

final class ConfigStoreTests: XCTestCase {
    func testCreatesStandardConfigWhenMissing() throws {
        let home = makeTemporaryDirectory()
        let store = ConfigStore(paths: CubbyPaths(home: home))
        guard case .created(let config) = store.load() else { return XCTFail("expected created") }
        XCTAssertEqual(config.sidebar.nodes.first?.name, "Favorites")
        let data = try Data(contentsOf: store.paths.configFile)
        XCTAssertTrue(store.isOwnWrite(data))
        guard case .loaded = store.load() else { return XCTFail("expected loaded") }
    }

    func testRoundTripsEdits() throws {
        let home = makeTemporaryDirectory()
        let store = ConfigStore(paths: CubbyPaths(home: home))
        var config = AppConfig.standard
        config.showHiddenFiles = true
        config.sidebar.insert(SidebarNode.group("Mine", [SidebarNode.group("Nested", [SidebarNode.folder("/tmp")])]), into: nil, at: 0)
        try store.save(config)
        guard case .loaded(let loaded) = store.load() else { return XCTFail("expected loaded") }
        XCTAssertTrue(loaded.showHiddenFiles)
        XCTAssertEqual(loaded.sidebar.nodes[0].children[0].children[0].path, "/tmp")
        XCTAssertFalse(store.isOwnWrite(Data("other".utf8)))
        XCTAssertFalse(store.isOwnWrite(nil))
    }

    func testInvalidConfigIsReportedAndNotOverwritten() throws {
        let home = makeTemporaryDirectory()
        let store = ConfigStore(paths: CubbyPaths(home: home))
        try JSONStore.write(Data(#"{"sidebar":[{"oops":1}]}"#.utf8), to: store.paths.configFile)
        guard case .invalid(let config, let message) = store.load() else { return XCTFail("expected invalid") }
        XCTAssertEqual(config.sidebar.nodes.first?.name, "Favorites")
        XCTAssertTrue(message.contains("sidebar"), message)
        XCTAssertEqual(try String(contentsOf: store.paths.configFile, encoding: .utf8), #"{"sidebar":[{"oops":1}]}"#)
    }

    func testDescribesSyntaxErrors() {
        do {
            _ = try JSONDecoder().decode(AppConfig.self, from: Data("{".utf8))
            XCTFail("expected error")
        } catch {
            XCTAssertFalse(ConfigStore.describe(error).isEmpty)
        }
    }
}
