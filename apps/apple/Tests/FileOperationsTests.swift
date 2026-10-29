import XCTest
@testable import CubbyCore

final class FileOperationsTests: XCTestCase {
    private let operations = FileOperations()

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func testMoveAndMoveBack() {
        let root = makeTemporaryDirectory()
        let source = makeFile(root, "a.txt")
        let target = makeFolder(root, "target")
        let result = operations.move([source], to: target) { _ in .stop }
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.transfers, [Transfer(source: source, destination: target.appending(path: "a.txt"))])
        XCTAssertFalse(exists(source))
        let undone = operations.moveBack(result.transfers)
        XCTAssertTrue(undone.errors.isEmpty)
        XCTAssertTrue(exists(source))
    }

    func testMoveWithinSameDirectoryIsNoOp() {
        let root = makeTemporaryDirectory()
        let source = makeFile(root, "a.txt")
        let result = operations.move([source], to: root) { _ in .stop }
        XCTAssertTrue(result.transfers.isEmpty)
        XCTAssertTrue(exists(source))
    }

    func testCopyIntoSameDirectoryMakesCopy() {
        let root = makeTemporaryDirectory()
        let source = makeFile(root, "a.txt")
        let result = operations.copy([source], to: root) { _ in .stop }
        XCTAssertEqual(result.transfers.first?.destination.lastPathComponent, "a copy.txt")
        XCTAssertTrue(exists(source))
    }

    func testConflictChoices() throws {
        let root = makeTemporaryDirectory()
        let source = makeFile(root, "a.txt", contents: "new")
        let target = makeFolder(root, "target")
        makeFile(target, "a.txt", contents: "old")

        var asked: [URL] = []
        let skipped = operations.copy([source], to: target) { asked.append($0); return .skip }
        XCTAssertEqual(asked, [target.appending(path: "a.txt")])
        XCTAssertTrue(skipped.transfers.isEmpty)

        let kept = operations.copy([source], to: target) { _ in .keepBoth }
        XCTAssertEqual(kept.transfers.first?.destination.lastPathComponent, "a 2.txt")

        let replaced = operations.copy([source], to: target) { _ in .replace }
        XCTAssertEqual(replaced.transfers.count, 1)
        XCTAssertEqual(try String(contentsOf: target.appending(path: "a.txt"), encoding: .utf8), "new")

        let second = makeFile(root, "b.txt")
        makeFile(target, "b.txt")
        let stopped = operations.copy([source, second], to: target) { _ in .stop }
        XCTAssertTrue(stopped.stopped)
        XCTAssertTrue(stopped.transfers.isEmpty)
    }

    func testRejectsMovingFolderIntoItself() {
        let root = makeTemporaryDirectory()
        let folder = makeFolder(root, "folder")
        let inner = makeFolder(folder, "inner")
        let result = operations.move([folder], to: inner) { _ in .stop }
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(exists(inner))
    }

    func testFailedReplacePutsBackReplacedItem() throws {
        let root = makeTemporaryDirectory()
        let missing = root.appending(path: "a.txt")
        let target = makeFolder(root, "target")
        let existing = makeFile(target, "a.txt", contents: "old")
        for transfer in [operations.move, operations.copy] {
            let result = transfer([missing], target) { _ in .replace }
            XCTAssertEqual(result.errors.count, 1)
            XCTAssertTrue(result.transfers.isEmpty)
            XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "old")
        }
    }

    func testRenameValidatesAndAllowsCaseChange() throws {
        let root = makeTemporaryDirectory()
        let file = makeFile(root, "a.txt")
        makeFile(root, "taken.txt")
        XCTAssertThrowsError(try operations.rename(file, to: "taken.txt"))
        XCTAssertThrowsError(try operations.rename(file, to: "bad/name"))
        XCTAssertEqual(try operations.rename(file, to: "a.txt"), file)
        let upper = try operations.rename(file, to: "A.txt")
        XCTAssertEqual(upper.lastPathComponent, "A.txt")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).contains("A.txt"))
    }

    func testMakeFolderFileAndDuplicate() throws {
        let root = makeTemporaryDirectory()
        XCTAssertEqual(try operations.makeFolder(in: root).lastPathComponent, "untitled folder")
        XCTAssertEqual(try operations.makeFolder(in: root).lastPathComponent, "untitled folder 2")
        let file = try operations.makeFile(in: root)
        XCTAssertEqual(file.lastPathComponent, "untitled.txt")
        let duplicated = operations.duplicate([file, file])
        XCTAssertEqual(duplicated.transfers.map(\.destination.lastPathComponent), ["untitled copy.txt", "untitled copy 2.txt"])
    }
}

final class FileOperationsReplaceSafetyTests: XCTestCase {
    func testReplaceNeverTrashesTheSourceOrItsParent() {
        let root = makeTemporaryDirectory()
        let outer = makeFolder(root, "x")
        let inner = makeFolder(outer, "x")
        makeFile(inner, "keep.txt")
        let result = FileOperations().move([inner], to: root) { _ in .replace }
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: inner.appending(path: "keep.txt").path))
    }

    func testSameDirectoryThroughSymlinkIsDetected() throws {
        let root = makeTemporaryDirectory()
        let real = makeFolder(root, "real")
        let file = makeFile(real, "a.txt")
        let link = root.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let result = FileOperations().move([file], to: link) { _ in .replace }
        XCTAssertTrue(result.transfers.isEmpty)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
}
