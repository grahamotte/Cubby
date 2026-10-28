import XCTest
@testable import CubbyCore

final class VisibilityTests: XCTestCase {
    func testStandardShowsOnlyVisibleItems() {
        let visibility = Visibility.standard
        XCTAssertTrue(visibility.shows(name: "notes.md", isHidden: false))
        XCTAssertFalse(visibility.shows(name: ".git", isHidden: true))
        XCTAssertFalse(visibility.shows(name: "Icon\r", isHidden: true))
        XCTAssertFalse(visibility.shows(name: ".DS_Store", isHidden: true))
        XCTAssertFalse(visibility.showsEverything)
    }

    func testHiddenFilesStillHideDSStore() {
        let visibility = Visibility(showHidden: true, showDSStore: false)
        XCTAssertTrue(visibility.shows(name: ".git", isHidden: true))
        XCTAssertTrue(visibility.shows(name: "notes.md", isHidden: false))
        XCTAssertFalse(visibility.shows(name: ".DS_Store", isHidden: true))
        XCTAssertFalse(visibility.shows(name: ".DS_Store", isHidden: false))
        XCTAssertFalse(visibility.showsEverything)
    }

    func testDSStoreNeedsHiddenFiles() {
        let visibility = Visibility(showHidden: false, showDSStore: true)
        XCTAssertFalse(visibility.shows(name: ".DS_Store", isHidden: true))
        XCTAssertFalse(visibility.shows(name: ".git", isHidden: true))
        XCTAssertFalse(visibility.showsEverything)
    }

    func testShowsEverything() {
        let visibility = Visibility(showHidden: true, showDSStore: true)
        XCTAssertTrue(visibility.shows(name: ".DS_Store", isHidden: true))
        XCTAssertTrue(visibility.shows(name: ".git", isHidden: true))
        XCTAssertTrue(visibility.showsEverything)
    }

    func testShowsItems() {
        let hidden = item(".DS_Store", hidden: true)
        let visible = item("a.txt")
        XCTAssertFalse(Visibility(showHidden: true, showDSStore: false).shows(hidden))
        XCTAssertTrue(Visibility(showHidden: true, showDSStore: true).shows(hidden))
        XCTAssertTrue(Visibility.standard.shows(visible))
    }
}
