import XCTest
@testable import CubbyCore

final class HistoryUndoTests: XCTestCase {
    private let fileManager = FileManager.default

    private func entry(_ kind: HistoryEntry.Kind, _ result: OperationResult, items: [URL], destination: URL? = nil) -> HistoryEntry {
        var entry = HistoryEntry(kind, items: items, destination: destination, state: .finished)
        entry.record(result)
        return entry
    }

    private func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func testUndoesAMove() {
        let root = makeTemporaryDirectory()
        let source = makeFolder(root, "source")
        let destination = makeFolder(root, "destination")
        let files = [makeFile(source, "a"), makeFile(source, "b")]
        let operations = FileOperations()
        let move = entry(.move, operations.move(files, to: destination) { _ in .stop }, items: files, destination: destination)

        let undo = move.undoEntry
        XCTAssertEqual(undo.kind, .moveBack)
        XCTAssertEqual(undo.undoes, move.id)
        XCTAssertEqual(undo.destination, source.standardizedFileURL.path)
        XCTAssertEqual(move.undoChange.removed, [destination.appending(path: "a"), destination.appending(path: "b")])
        XCTAssertNil(move.undoPreflight())

        let result = move.undo(with: operations)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertTrue(files.allSatisfy(exists))
        XCTAssertFalse(exists(destination.appending(path: "a")))
        XCTAssertEqual(Set(result.transfers.map(\.destination)), Set(files))
    }

    func testUndoingAReplacingMoveRestoresTheReplacedItem() throws {
        let root = makeTemporaryDirectory()
        let source = makeFolder(root, "source")
        let destination = makeFolder(root, "destination")
        let file = makeFile(source, "a", contents: "new")
        makeFile(destination, "a", contents: "old")
        let operations = FileOperations()
        let move = entry(.move, operations.move([file], to: destination) { _ in .replace }, items: [file], destination: destination)
        XCTAssertEqual(move.replaced?.count, 1)
        XCTAssertNil(move.undoPreflight())

        XCTAssertTrue(move.undo(with: operations).errors.isEmpty)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "new")
        XCTAssertEqual(try String(contentsOf: destination.appending(path: "a"), encoding: .utf8), "old")
    }

    func testUndoesARename() throws {
        let root = makeTemporaryDirectory()
        let file = makeFile(root, "a")
        let renamed = try FileOperations().rename(file, to: "b")
        var rename = HistoryEntry(.rename, items: [file], target: "b", state: .finished)
        rename.record(inputs: [file], outputs: [renamed])

        let undo = rename.undoEntry
        XCTAssertEqual(undo.summary, "Renaming b to a")
        XCTAssertEqual(undo.undoes, rename.id)
        XCTAssertNil(rename.undoPreflight())
        XCTAssertTrue(rename.undo(with: FileOperations()).errors.isEmpty)
        XCTAssertTrue(exists(file))
        XCTAssertFalse(exists(renamed))
    }

    func testUndoesACaseOnlyRename() throws {
        let root = makeTemporaryDirectory()
        let file = makeFile(root, "name")
        let renamed = try FileOperations().rename(file, to: "Name")
        var rename = HistoryEntry(.rename, items: [file], target: "Name", state: .finished)
        rename.record(inputs: [file], outputs: [renamed])
        XCTAssertNil(rename.undoPreflight())
        XCTAssertTrue(rename.undo(with: FileOperations()).errors.isEmpty)
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: root.path), ["name"])
    }

    func testPutsBackTrashedItems() {
        let root = makeTemporaryDirectory()
        let file = makeFile(root, "a")
        let operations = FileOperations()
        let trash = entry(.trash, operations.trash([file]), items: [file])
        XCTAssertFalse(exists(file))

        let undo = trash.undoEntry
        XCTAssertEqual(undo.kind, .putBack)
        XCTAssertEqual(undo.destination, root.standardizedFileURL.path)
        XCTAssertNil(trash.undoPreflight())
        XCTAssertTrue(trash.undo(with: operations).errors.isEmpty)
        XCTAssertTrue(exists(file))
    }

    func testTrashesCreatedItems() throws {
        let root = makeTemporaryDirectory()
        let source = makeFolder(root, "source")
        let destination = makeFolder(root, "destination")
        let file = makeFile(source, "a", contents: "new")
        makeFile(destination, "a", contents: "old")
        let operations = FileOperations()
        let copy = entry(.copy, operations.copy([file], to: destination) { _ in .replace }, items: [file], destination: destination)
        XCTAssertEqual(copy.inputs, [])

        let undo = copy.undoEntry
        XCTAssertEqual(undo.kind, .trash)
        XCTAssertEqual(undo.undoes, copy.id)
        XCTAssertEqual(copy.undoChange.removed, [destination.appending(path: "a")])
        XCTAssertNil(copy.undoPreflight())
        XCTAssertTrue(copy.undo(with: operations).errors.isEmpty)
        XCTAssertTrue(exists(file))
        XCTAssertEqual(try String(contentsOf: destination.appending(path: "a"), encoding: .utf8), "old")

        let folder = try operations.makeFolder(in: root)
        var newFolder = HistoryEntry(.newFolder, items: [folder], state: .finished)
        newFolder.record(inputs: [], outputs: [folder])
        XCTAssertNil(newFolder.undoPreflight())
        XCTAssertTrue(newFolder.undo(with: operations).errors.isEmpty)
        XCTAssertFalse(exists(folder))
    }

    func testUndoesANewFolderWithItems() throws {
        let root = makeTemporaryDirectory()
        let files = [makeFile(root, "a"), makeFile(root, "b")]
        let operations = FileOperations()
        let folder = try operations.makeFolder(in: root, name: "New Folder With Items")
        let entry = entry(.newFolderWithItems, operations.move(files, to: folder) { _ in .keepBoth }, items: files, destination: folder)
        XCTAssertEqual(entry.undoEntry.kind, .moveBack)
        XCTAssertNil(entry.undoPreflight())
        XCTAssertTrue(entry.undo(with: operations).errors.isEmpty)
        XCTAssertTrue(files.allSatisfy(exists))
        XCTAssertFalse(exists(folder))
    }

    func testKeepsANewFolderWithItemsThatGainedOtherItems() throws {
        let root = makeTemporaryDirectory()
        let file = makeFile(root, "a")
        let operations = FileOperations()
        let folder = try operations.makeFolder(in: root, name: "New Folder With Items")
        let entry = entry(.newFolderWithItems, operations.move([file], to: folder) { _ in .keepBoth }, items: [file], destination: folder)
        makeFile(folder, "other")
        XCTAssertTrue(entry.undo(with: operations).errors.isEmpty)
        XCTAssertTrue(exists(file))
        XCTAssertTrue(exists(folder.appending(path: "other")))
    }

    func testPreflightRefusesChangedFiles() throws {
        let root = makeTemporaryDirectory()
        let source = makeFolder(root, "source")
        let destination = makeFolder(root, "destination")
        let file = makeFile(source, "a")
        let operations = FileOperations()
        let move = entry(.move, operations.move([file], to: destination) { _ in .stop }, items: [file], destination: destination)

        makeFile(source, "a")
        XCTAssertEqual(move.undoPreflight()?.message, "An item named “a” already exists where it was, so this can't be undone.")
        try fileManager.removeItem(at: source)
        XCTAssertEqual(move.undoPreflight()?.message, "The folder that held “a” no longer exists, so this can't be undone.")
        makeFolder(root, "source")
        XCTAssertNil(move.undoPreflight())
        try fileManager.removeItem(at: destination.appending(path: "a"))
        XCTAssertEqual(move.undoPreflight()?.message, "“a” is no longer where it was, so this can't be undone.")

        var replacing = HistoryEntry(.copy, items: [file], state: .finished)
        replacing.record(inputs: [], outputs: [source], replaced: [Transfer(source: source, destination: root.appending(path: "gone"))])
        XCTAssertEqual(replacing.undoPreflight()?.message, "The replaced “source” is no longer in the Trash, so this can't be undone.")

        XCTAssertEqual(HistoryEntry(.move, items: [file], state: .finished).undoPreflight()?.message, "This operation can't be undone.")
        XCTAssertNotNil(move.undoPreflight())
        XCTAssertNotNil(move.undo(with: operations).errors.first)
    }
}
