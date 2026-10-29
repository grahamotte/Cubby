import XCTest
@testable import CubbyCore

final class ArchiveTests: XCTestCase {
    private let folder = URL(filePath: "/Users/me/Stuff", directoryHint: .isDirectory)

    func testNoItemsHasNoPlan() {
        XCTAssertNil(Archive.plan(for: []) { _ in false })
    }

    func testSingleItemUsesDittoWithAbsolutePaths() {
        let item = folder.appending(path: "Photos")
        let archive = Archive.plan(for: [item]) { _ in false }
        XCTAssertEqual(archive?.executable.path, "/usr/bin/ditto")
        XCTAssertEqual(archive?.arguments, ["-c", "-k", "--sequesterRsrc", "--keepParent", "/Users/me/Stuff/Photos", "/Users/me/Stuff/Photos.zip"])
        XCTAssertNil(archive?.directory)
        XCTAssertEqual(archive?.destination.path, "/Users/me/Stuff/Photos.zip")
    }

    func testMultipleItemsEndOptionsBeforeNames() {
        let urls = ["-m", "notes.txt", "-T"].map { folder.appending(path: $0) }
        let archive = Archive.plan(for: urls) { _ in false }
        XCTAssertEqual(archive?.executable.path, "/usr/bin/zip")
        XCTAssertEqual(archive?.arguments, ["-r", "-y", "-q", "/Users/me/Stuff/Archive.zip", "--", "-m", "notes.txt", "-T"])
        XCTAssertEqual(archive?.directory?.path, "/Users/me/Stuff")
    }

    func testDestinationAvoidsExistingArchive() {
        let urls = [folder.appending(path: "a.txt"), folder.appending(path: "b.txt")]
        let archive = Archive.plan(for: urls) { $0 == "/Users/me/Stuff/Archive.zip" }
        XCTAssertEqual(archive?.destination.lastPathComponent, "Archive 2.zip")
        XCTAssertEqual(archive?.arguments[3], "/Users/me/Stuff/Archive 2.zip")
    }
}
