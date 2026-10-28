import XCTest
@testable import CubbyCore

final class SessionStateTests: XCTestCase {
    func testRoundTrips() throws {
        let url = makeTemporaryDirectory().appending(path: "session.json")
        let state = SessionState(windows: [.init(frame: "0 0 800 600", sidebarWidth: 200, tabs: [.init(layout: .sideBySide, paths: ["/a", "/b"], activePane: 1)], selectedTab: 0)], listColumns: [.init(id: "size", width: 80, hidden: true)])
        try state.save(to: url)
        XCTAssertEqual(SessionState.load(from: url), state)
        XCTAssertNil(SessionState.load(from: url.appending(path: "missing")))
    }

    func testNormalizesTabs() {
        let tab = SessionState.Tab(layout: .grid, paths: ["/a", "/gone"], activePane: 9)
        let normalized = tab.normalized(home: "/home") { $0 != "/gone" }
        XCTAssertEqual(normalized.paths, ["/a", "/home", "/home", "/home"])
        XCTAssertEqual(normalized.activePane, 3)
        let trimmed = SessionState.Tab(layout: .single, paths: ["/a", "/b"], activePane: -1).normalized(home: "/h") { _ in true }
        XCTAssertEqual(trimmed.paths, ["/a"])
        XCTAssertEqual(trimmed.activePane, 0)
    }

    func testDecodesUnknownLayoutAsSingle() throws {
        let tab = try JSONDecoder().decode(SessionState.Tab.self, from: Data(#"{"layout":"weird","paths":["/x"]}"#.utf8))
        XCTAssertEqual(tab.layout, .single)
        XCTAssertEqual(tab.activePane, 0)
    }
}
