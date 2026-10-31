import XCTest
@testable import CubbyCore

final class SessionStateTests: XCTestCase {
    func testRoundTrips() throws {
        let url = makeTemporaryDirectory().appending(path: "session.json")
        let state = SessionState(windows: [.init(frame: "0 0 800 600", sidebarWidth: 200, tabs: [.init(layout: .sideBySide, paths: ["/a", "/b"], activePane: 1), nil, .init(layout: .single, paths: ["/c"], activePane: 0)])], listColumns: [.init(id: "size", width: 80, hidden: true)], lastFrame: "10 20 900 700")
        try state.save(to: url)
        XCTAssertEqual(SessionState.load(from: url), state)
        XCTAssertNil(SessionState.load(from: url.appending(path: "missing")))
    }

    func testDecodesSessionWithoutLastFrame() throws {
        let state = try JSONDecoder().decode(SessionState.self, from: Data(#"{"windows":[]}"#.utf8))
        XCTAssertEqual(state.windows, [])
        XCTAssertNil(state.lastFrame)
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

    func testDecodesLegacyWindowTabs() throws {
        let window = try JSONDecoder().decode(SessionState.Window.self, from: Data(#"{"tabs":[{"layout":"single","paths":["/x"]}],"selectedTab":0}"#.utf8))
        XCTAssertEqual(window.tabs, [.init(layout: .single, paths: ["/x"], activePane: 0)])
    }

    func testProfileTabsStartWithOneProfile() {
        let tab = SessionState.Tab(layout: .single, paths: ["/a"], activePane: 0)
        let tabs = ProfileTabs(tab: tab, profile: 2)
        XCTAssertEqual(tabs.tabs, [nil, nil, tab])
        XCTAssertEqual(tabs.profile, 2)
        XCTAssertEqual(tabs.tab(for: 2), tab)
        XCTAssertNil(tabs.tab(for: 0))
        XCTAssertNil(tabs.tab(for: 5))
        XCTAssertEqual(ProfileTabs(tab: tab, profile: -1).tabs, [tab])
    }

    func testProfileTabsSwitchKeepsEachProfilesTab() {
        let personal = SessionState.Tab(layout: .single, paths: ["/personal"], activePane: 0)
        let work = SessionState.Tab(layout: .sideBySide, paths: ["/work", "/code"], activePane: 1)
        var tabs = ProfileTabs(tab: personal, profile: 0)
        XCTAssertNil(tabs.select(1, live: SessionState.Tab(layout: .single, paths: ["/personal/moved"], activePane: 0)))
        XCTAssertEqual(tabs.profile, 1)
        XCTAssertEqual(tabs.select(0, live: work), SessionState.Tab(layout: .single, paths: ["/personal/moved"], activePane: 0))
        XCTAssertEqual(tabs.tab(for: 1), work)
        XCTAssertEqual(tabs.saving(personal), [personal, work])
        XCTAssertEqual(tabs.tabs, [SessionState.Tab(layout: .single, paths: ["/personal/moved"], activePane: 0), work])
    }

    func testProfileTabsRemoveShiftsProfiles() {
        let a = SessionState.Tab(layout: .single, paths: ["/a"], activePane: 0)
        let b = SessionState.Tab(layout: .single, paths: ["/b"], activePane: 0)
        let c = SessionState.Tab(layout: .single, paths: ["/c"], activePane: 0)
        var tabs = ProfileTabs(tabs: [a, b, c], profile: 2)
        tabs.remove(0)
        XCTAssertEqual(tabs.profile, 1)
        XCTAssertEqual(tabs.tabs, [b, c])
        tabs.remove(1)
        XCTAssertNil(tabs.profile)
        XCTAssertEqual(tabs.tabs, [b])
        XCTAssertEqual(tabs.saving(a), [b])
        XCTAssertEqual(tabs.select(0, live: a), b)
        XCTAssertEqual(tabs.tabs, [b])
        tabs.remove(4)
        XCTAssertEqual(tabs.profile, 0)
        XCTAssertEqual(tabs.tabs, [b])
    }
}
