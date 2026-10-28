import XCTest
@testable import CubbyCore

final class SidebarNodeTests: XCTestCase {
    func testDecodesNestedGroupsAndFolders() throws {
        let json = #"[{"group":"Work","collapsed":true,"items":[{"folder":"~/Code","name":"Code"},{"group":"Inner","items":[{"folder":"/tmp"}]}]}]"#
        let nodes = try JSONDecoder().decode([SidebarNode].self, from: Data(json.utf8))
        XCTAssertEqual(nodes.count, 1)
        let work = nodes[0]
        XCTAssertEqual(work.kind, .group)
        XCTAssertEqual(work.name, "Work")
        XCTAssertTrue(work.isCollapsed)
        XCTAssertEqual(work.children.count, 2)
        XCTAssertEqual(work.children[0].kind, .folder)
        XCTAssertEqual(work.children[0].path, "~/Code")
        XCTAssertEqual(work.children[0].displayName, "Code")
        XCTAssertTrue(work.children[0].parent === work)
        XCTAssertTrue(work.children[1].children[0].isDescendant(of: work))
        XCTAssertFalse(work.isDescendant(of: work.children[1]))
    }

    func testRejectsItemsWithoutKind() {
        XCTAssertThrowsError(try JSONDecoder().decode([SidebarNode].self, from: Data(#"[{"name":"x"}]"#.utf8)))
    }

    func testEncodesCompactly() {
        let nodes = [SidebarNode.group("A", [SidebarNode.folder("/tmp"), SidebarNode.folder("~/x", name: "X")]), SidebarNode.group("B", collapsed: true)]
        let json = sidebarJSON(nodes)
        XCTAssertTrue(json.contains(#""folder" : "/tmp""#))
        XCTAssertTrue(json.contains(#""name" : "X""#))
        XCTAssertTrue(json.contains(#""collapsed" : true"#))
        XCTAssertEqual(json.components(separatedBy: "collapsed").count, 2)
        let decoded = try! JSONDecoder().decode([SidebarNode].self, from: Data(json.utf8))
        XCTAssertEqual(sidebarJSON(decoded), json)
    }

    func testURLExpandsTildeAndDisplayNameFallsBack() {
        let folder = SidebarNode.folder("~/Downloads")
        XCTAssertEqual(folder.url?.path, NSHomeDirectory() + "/Downloads")
        XCTAssertEqual(folder.displayName, "Downloads")
        XCTAssertEqual(SidebarNode.folder("/").displayName, "Macintosh HD")
        XCTAssertNil(SidebarNode.group("G").url)
    }
}
