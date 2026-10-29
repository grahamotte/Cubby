import XCTest
@testable import CubbyCore

final class FolderViewTests: XCTestCase {
    func testClampsIconSize() {
        XCTAssertEqual(FolderView(mode: .icons, sort: .name, ascending: true, iconSize: 4).iconSize, 32)
        XCTAssertEqual(FolderView(mode: .icons, sort: .name, ascending: true, iconSize: 999).iconSize, 512)
    }

    func testDecodesPartialAndUnknownValues() throws {
        let view = try JSONDecoder().decode(FolderView.self, from: Data(#"{"mode":"icons","sort":"bogus"}"#.utf8))
        XCTAssertEqual(view.mode, .icons)
        XCTAssertEqual(view.sort, .name)
        XCTAssertTrue(view.ascending)
        XCTAssertEqual(view.iconSize, FolderView.standard.iconSize)
    }

    func testDecodesRemovedGalleryAndUnknownModesAsIcons() throws {
        XCTAssertEqual(try JSONDecoder().decode(FolderView.self, from: Data(#"{"mode":"gallery","sort":"size","ascending":false}"#.utf8)), FolderView(mode: .icons, sort: .size, ascending: false, iconSize: FolderView.standard.iconSize))
        XCTAssertEqual(try JSONDecoder().decode(FolderView.self, from: Data(#"{"mode":"bogus"}"#.utf8)).mode, .icons)
        XCTAssertEqual(try JSONDecoder().decode(FolderView.self, from: Data(#"{"mode":"columns"}"#.utf8)).mode, .columns)
        XCTAssertEqual(ViewMode.allCases, [.list, .icons, .columns])
    }

    func testDefaultSortDirections() {
        XCTAssertTrue(SortKey.name.defaultAscending)
        XCTAssertTrue(SortKey.kind.defaultAscending)
        XCTAssertFalse(SortKey.modified.defaultAscending)
        XCTAssertFalse(SortKey.size.defaultAscending)
        XCTAssertEqual(Set(ViewMode.allCases.map(\.title)).count, ViewMode.allCases.count)
    }
}
