import XCTest
@testable import CubbyCore

final class FolderViewTests: XCTestCase {
    func testClampsIconSize() {
        XCTAssertEqual(FolderView(mode: .icons, sort: .name, ascending: true, iconSize: 4).iconSize, 32)
        XCTAssertEqual(FolderView(mode: .icons, sort: .name, ascending: true, iconSize: 999).iconSize, 512)
    }

    func testListIconSizeClampsStepsAndDecodes() throws {
        XCTAssertEqual(FolderView.standard.listIconSize, 16)
        XCTAssertEqual(FolderView(mode: .list, sort: .name, ascending: true, iconSize: 80, listIconSize: 4).listIconSize, 16)
        XCTAssertEqual(FolderView(mode: .list, sort: .name, ascending: true, iconSize: 80, listIconSize: 999).listIconSize, 128)
        var view = FolderView.standard
        XCTAssertEqual(view.steppedListIconSize(bigger: false), 16)
        XCTAssertEqual(view.steppedListIconSize(bigger: true), 24)
        view.listIconSize = 40
        XCTAssertEqual(view.steppedListIconSize(bigger: true), 48)
        XCTAssertEqual(view.steppedListIconSize(bigger: false), 32)
        view.listIconSize = 128
        XCTAssertEqual(view.steppedListIconSize(bigger: true), 128)
        let decoded = try JSONDecoder().decode(FolderView.self, from: Data(#"{"mode":"list","listIconSize":64}"#.utf8))
        XCTAssertEqual(decoded.listIconSize, 64)
        XCTAssertEqual(decoded.iconSize, FolderView.standard.iconSize)
        XCTAssertEqual(try JSONDecoder().decode(FolderView.self, from: JSONEncoder().encode(decoded)), decoded)
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
        XCTAssertTrue(SortKey.name.hasDirection)
        XCTAssertFalse(SortKey.random.hasDirection)
        XCTAssertEqual(try JSONDecoder().decode(FolderView.self, from: Data(#"{"sort":"random"}"#.utf8)).sort, .random)
        XCTAssertEqual(Set(ViewMode.allCases.map(\.title)).count, ViewMode.allCases.count)
    }
}
