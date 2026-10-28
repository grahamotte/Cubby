import XCTest
@testable import CubbyCore

final class NavigationHistoryTests: XCTestCase {
    func testBackForwardAndTruncation() {
        var history = NavigationHistory()
        XCTAssertNil(history.current)
        history.visit("/a")
        history.visit("/b")
        history.visit("/b")
        history.visit("/c")
        XCTAssertEqual(history.entries, ["/a", "/b", "/c"])
        XCTAssertEqual(history.back(), "/b")
        XCTAssertEqual(history.back(), "/a")
        XCTAssertNil(history.back())
        XCTAssertEqual(history.forward(), "/b")
        history.visit("/d")
        XCTAssertEqual(history.entries, ["/a", "/b", "/d"])
        XCTAssertFalse(history.canGoForward)
        XCTAssertTrue(history.canGoBack)
    }

    func testLimitAndReplace() {
        var history = NavigationHistory()
        for index in 0..<150 { history.visit("/\(index)") }
        XCTAssertEqual(history.entries.count, NavigationHistory.limit)
        XCTAssertEqual(history.current, "/149")
        history.replaceCurrent(with: "/renamed")
        XCTAssertEqual(history.current, "/renamed")
        var empty = NavigationHistory()
        empty.replaceCurrent(with: "/x")
        XCTAssertEqual(empty.current, "/x")
    }
}
