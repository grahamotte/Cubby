import XCTest
@testable import CubbyCore

final class DirectoryListingTests: XCTestCase {
    func testMergeReusesUnchangedItems() {
        let a = FileItem(directory: "/d", name: "a", isDirectory: false, size: 1, fileID: 1)
        let folder = FileItem(directory: "/d", name: "f", isDirectory: true, modified: 1, fileID: 2)
        folder.children = [FileItem(directory: "/d/f", name: "x", isDirectory: false)]
        let changedA = FileItem(directory: "/d", name: "a", isDirectory: false, size: 2, fileID: 1)
        let touchedFolder = FileItem(directory: "/d", name: "f", isDirectory: true, modified: 2, fileID: 2)
        let b = FileItem(directory: "/d", name: "b", isDirectory: false, fileID: 3)

        let merged = DirectoryListing.merge(old: [a, folder], new: [FileItem(directory: "/d", name: "a", isDirectory: false, size: 1, fileID: 1), b])
        XCTAssertTrue(merged[0] === a)
        XCTAssertTrue(merged[1] === b)

        let changed = DirectoryListing.merge(old: [a, folder], new: [changedA, touchedFolder])
        XCTAssertTrue(changed[0] === a)
        XCTAssertEqual(a.size, 2)
        XCTAssertTrue(changed[1] === folder)
        XCTAssertEqual(folder.modified, 2)
        XCTAssertEqual(folder.children?.map(\.name), ["x"])

        let replaced = FileItem(directory: "/d", name: "a", isDirectory: false, size: 2, fileID: 99)
        XCTAssertTrue(DirectoryListing.merge(old: [a], new: [replaced])[0] === replaced)
        XCTAssertTrue(DirectoryListing.merge(old: [], new: [b])[0] === b)
    }

    func testIndexesOfNames() {
        let items = ["a", "b", "c"].map { FileItem(directory: "/", name: $0, isDirectory: false) }
        XCTAssertEqual(DirectoryListing.indexes(of: ["a", "c", "z"], in: items), IndexSet([0, 2]))
    }
}

final class DirectoryListingReconcileTests: XCTestCase {
    func testReconcileMapsVisibleItemsToKeptInstances() {
        let kept = FileItem(directory: "/d", name: "a", isDirectory: false, size: 1, fileID: 1)
        let freshA = FileItem(directory: "/d", name: "a", isDirectory: false, size: 3, fileID: 1)
        let freshB = FileItem(directory: "/d", name: "b", isDirectory: false, fileID: 2)
        let result = DirectoryListing.reconcile(old: [kept], new: [freshA, freshB], visible: [freshB, freshA])
        XCTAssertTrue(result.all[0] === kept)
        XCTAssertTrue(result.visible[0] === freshB)
        XCTAssertTrue(result.visible[1] === kept)
        XCTAssertEqual(kept.size, 3)
        let first = DirectoryListing.reconcile(old: [], new: [freshB], visible: [freshB])
        XCTAssertTrue(first.visible[0] === freshB)
    }
}
