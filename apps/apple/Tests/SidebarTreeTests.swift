import XCTest
@testable import CubbyCore

final class SidebarTreeTests: XCTestCase {
    private func makeTree() -> (SidebarTree, SidebarNode, SidebarNode, SidebarNode) {
        let a = SidebarNode.group("A", [SidebarNode.folder("/a1"), SidebarNode.folder("/a2")])
        let b = SidebarNode.group("B")
        let loose = SidebarNode.folder("/loose")
        return (SidebarTree(nodes: [a, b, loose], home: "/Users/me"), a, b, loose)
    }

    func testInsertIntoGroupsOnly() {
        let (tree, a, _, loose) = makeTree()
        let folder = SidebarNode.folder("/new")
        XCTAssertFalse(tree.insert(folder, into: loose))
        XCTAssertTrue(tree.insert(folder, into: a, at: 1))
        XCTAssertEqual(a.children.map(\.path), ["/a1", "/new", "/a2"])
        XCTAssertTrue(folder.parent === a)
        XCTAssertTrue(tree.insert(SidebarNode.group("C"), into: nil, at: 99))
        XCTAssertEqual(tree.nodes.last?.name, "C")
    }

    func testMoveWithinSameParentAdjustsIndex() {
        let (tree, a, b, loose) = makeTree()
        XCTAssertTrue(tree.move(a, into: nil, at: 3))
        XCTAssertTrue(tree.nodes[2] === a)
        XCTAssertTrue(tree.move(a, into: nil, at: 0))
        XCTAssertTrue(tree.nodes[0] === a)
    }

    func testMoveIntoNestedGroupAndRejectCycles() {
        let (tree, a, b, loose) = makeTree()
        XCTAssertTrue(tree.move(b, into: a, at: 0))
        XCTAssertTrue(a.children[0] === b)
        XCTAssertFalse(tree.move(a, into: b, at: 0))
        XCTAssertFalse(tree.move(a, into: a, at: 0))
        XCTAssertFalse(tree.move(a, into: loose, at: 0))
        XCTAssertTrue(tree.move(loose, into: b, at: 0))
        XCTAssertTrue(loose.parent === b)
        XCTAssertEqual(tree.nodes.count, 1)
    }

    func testRemoveAndRename() {
        let (tree, a, b, _) = makeTree()
        tree.remove(b)
        XCTAssertEqual(tree.nodes.count, 2)
        XCTAssertNil(b.parent)
        XCTAssertFalse(tree.rename(a, to: "   "))
        XCTAssertTrue(tree.rename(a, to: "  Renamed "))
        XCTAssertEqual(a.name, "Renamed")
        let folder = a.children[0]
        XCTAssertTrue(tree.rename(folder, to: "Alias"))
        XCTAssertEqual(folder.displayName, "Alias")
        XCTAssertTrue(tree.rename(folder, to: "a1"))
        XCTAssertEqual(folder.name, "")
        XCTAssertTrue(tree.rename(folder, to: ""))
        XCTAssertEqual(folder.displayName, "a1")
    }

    func testAbbreviatesHome() {
        let (tree, _, _, _) = makeTree()
        XCTAssertEqual(tree.abbreviate("/Users/me"), "~")
        XCTAssertEqual(tree.abbreviate("/Users/me/"), "~")
        XCTAssertEqual(tree.abbreviate("/Users/me/Code/x"), "~/Code/x")
        XCTAssertEqual(tree.abbreviate("/Users/meow"), "/Users/meow")
        XCTAssertEqual(tree.abbreviate("/"), "/")
        XCTAssertEqual(tree.makeFolder(URL(filePath: "/Users/me/Desktop/")).path, "~/Desktop")
    }

    func testFoldersAndRenamedPaths() {
        let (tree, a, _, _) = makeTree()
        tree.insert(SidebarNode.folder("/a1/sub"), into: a)
        XCTAssertEqual(tree.folders().map(\.path), ["/a1", "/a2", "/a1/sub", "/loose"])
        XCTAssertTrue(tree.updateFolders(movedFrom: "/a1", to: "/Users/me/z"))
        XCTAssertEqual(tree.folders().map(\.path), ["~/z", "/a2", "~/z/sub", "/loose"])
        XCTAssertFalse(tree.updateFolders(movedFrom: "/nothing", to: "/x"))
    }
}
