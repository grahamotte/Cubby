import XCTest
@testable import CubbyCore

final class PaneLayoutTests: XCTestCase {
    func testPaneCounts() {
        XCTAssertEqual(PaneLayout.allCases.map(\.paneCount), [1, 2, 2, 3, 4])
        XCTAssertEqual(PaneLayout.stacked.rows, [1, 1])
        XCTAssertEqual(PaneLayout.grid.rows, [2, 2])
        XCTAssertEqual(Set(PaneLayout.allCases.map(\.title)).count, PaneLayout.allCases.count)
    }
}
