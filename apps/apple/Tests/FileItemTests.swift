import XCTest
@testable import CubbyCore

final class FileItemTests: XCTestCase {
    func testPathsAndKinds() {
        let file = FileItem(directory: "/tmp", name: "notes.txt", isDirectory: false)
        XCTAssertEqual(file.path, "/tmp/notes.txt")
        XCTAssertEqual(file.url.path, "/tmp/notes.txt")
        XCTAssertEqual(file.pathExtension, "txt")
        XCTAssertFalse(file.isFolder)
        XCTAssertEqual(FileItem(directory: "/", name: "Users", isDirectory: true).path, "/Users")
        XCTAssertEqual(FileItem(directory: "/", name: "Users", isDirectory: true).kind, "Folder")
        XCTAssertEqual(FileItem(directory: "/", name: "README", isDirectory: false).kind, "Document")
        XCTAssertEqual(FileItem(directory: "/", name: "a.zzqq", isDirectory: false).kind, "ZZQQ File")
        XCTAssertFalse(file.kind.isEmpty)
    }

    func testPackagesAreNotFolders() {
        XCTAssertTrue(KindCache.shared.isPackage(extension: "app"))
        XCTAssertFalse(KindCache.shared.isPackage(extension: "txt"))
        XCTAssertFalse(KindCache.shared.isPackage(extension: ""))
        let app = FileItem(directory: "/Applications", name: "Safari.app", isDirectory: true, isPackage: true)
        XCTAssertFalse(app.isFolder)
        XCTAssertNotEqual(app.kind, "Folder")
    }

    func testSameEntry() {
        let a = FileItem(directory: "/", name: "a", isDirectory: false, size: 1, modified: 2, fileID: 3)
        XCTAssertTrue(a.sameEntry(as: FileItem(directory: "/", name: "a", isDirectory: false, size: 1, modified: 2, fileID: 3)))
        let bigger = FileItem(directory: "/", name: "a", isDirectory: false, isHidden: true, size: 2, modified: 5, fileID: 3)
        XCTAssertFalse(a.sameEntry(as: bigger))
        a.update(from: bigger)
        XCTAssertTrue(a.sameEntry(as: bigger))
        XCTAssertTrue(a.isHidden)
    }

    func testPlacedCopiesAttributesIntoAnotherDirectory() {
        let original = FileItem(directory: "/a", name: "x.txt", isDirectory: false, isHidden: true, size: 4, modified: 5, created: 6, added: 7, fileID: 8)
        let placed = original.placed(in: "/b", name: "y.txt")
        XCTAssertEqual(placed.path, "/b/y.txt")
        XCTAssertTrue(placed.sameEntry(as: FileItem(directory: "/b", name: "y.txt", isDirectory: false, isHidden: true, size: 4, modified: 5, fileID: 8)))
        XCTAssertEqual(placed.created, 6)
        XCTAssertEqual(placed.added, 7)
        XCTAssertEqual(original.placed(in: "/c").path, "/c/x.txt")
    }
}
