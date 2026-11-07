import XCTest
@testable import CubbyCore

final class CrumbFitTests: XCTestCase {
    func testWidthsThatFitAreUnchanged() {
        XCTAssertEqual(CrumbFit.widths([40, 80, 60], available: 180), [40, 80, 60])
        XCTAssertEqual(CrumbFit.widths([40, 80, 60], available: 500), [40, 80, 60])
        XCTAssertEqual(CrumbFit.widths([], available: 100), [])
    }

    func testOnlyTheWidestShrinkWhenTheyStopFitting() {
        XCTAssertEqual(CrumbFit.widths([40, 200, 60], available: 200), [40, 100, 60])
    }

    func testWideCrumbsShareTheSpaceEvenly() {
        XCTAssertEqual(CrumbFit.widths([30, 200, 150, 120], available: 300), [30, 90, 90, 90])
    }

    func testNarrowCrumbsShrinkOnceEveryCrumbIsCapped() {
        XCTAssertEqual(CrumbFit.widths([30, 200, 150], available: 60), [20, 20, 20])
    }

    func testNoSpaceCollapsesEveryCrumb() {
        XCTAssertEqual(CrumbFit.widths([30, 200], available: 0), [0, 0])
        XCTAssertEqual(CrumbFit.widths([30, 200], available: -10), [0, 0])
    }
}
