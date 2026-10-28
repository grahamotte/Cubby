import XCTest
@testable import CubbyCore

final class DirectoryReaderTests: XCTestCase {
    func testReadsEntriesWithMetadata() throws {
        let directory = makeTemporaryDirectory()
        makeFile(directory, "a.txt", contents: "hello")
        makeFile(directory, ".hidden")
        makeFolder(directory, "Folder")
        makeFolder(directory, "Thing.app")
        try FileManager.default.createSymbolicLink(atPath: directory.appending(path: "link").path, withDestinationPath: directory.appending(path: "Folder").path)

        let items = try DirectoryReader.read(directory.path)
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })
        XCTAssertEqual(Set(byName.keys), ["a.txt", ".hidden", "Folder", "Thing.app", "link"])
        XCTAssertEqual(byName["a.txt"]?.size, 5)
        XCTAssertEqual(byName["a.txt"]?.directory, directory.path)
        XCTAssertFalse(byName["a.txt"]!.isDirectory)
        XCTAssertGreaterThan(byName["a.txt"]!.modified, 1_000_000_000)
        XCTAssertGreaterThan(byName["a.txt"]!.fileID, 0)
        XCTAssertTrue(byName[".hidden"]!.isHidden)
        XCTAssertTrue(byName["Folder"]!.isFolder)
        XCTAssertEqual(byName["Folder"]?.size, 0)
        XCTAssertTrue(byName["Thing.app"]!.isPackage)
        XCTAssertTrue(byName["link"]!.isSymlink)
        XCTAssertTrue(byName["link"]!.isFolder)
    }

    func testReadsManyEntriesAcrossBuffers() throws {
        let directory = makeTemporaryDirectory()
        for index in 0..<3000 {
            FileManager.default.createFile(atPath: directory.appending(path: "file-with-a-longish-name-\(index).dat").path, contents: nil)
        }
        XCTAssertEqual(try DirectoryReader.read(directory.path).count, 3000)
    }

    func testCountsChildrenWithVisibility() throws {
        let directory = makeTemporaryDirectory()
        makeFile(directory, "a.txt")
        makeFile(directory, ".hidden")
        makeFile(directory, ".DS_Store")
        makeFolder(directory, "Folder")
        makeFile(makeFolder(directory, "Nested"), "deep.txt")
        XCTAssertEqual(try DirectoryReader.count(directory.path, visibility: .standard), 3)
        XCTAssertEqual(try DirectoryReader.count(directory.path, visibility: Visibility(showHidden: true, showDSStore: false)), 4)
        XCTAssertEqual(try DirectoryReader.count(directory.path, visibility: Visibility(showHidden: true, showDSStore: true)), 5)
        XCTAssertEqual(try DirectoryReader.count(directory.appending(path: "Folder").path, visibility: .standard), 0)
        XCTAssertThrowsError(try DirectoryReader.count("/nonexistent/\(UUID().uuidString)", visibility: .standard))
    }

    func testCountsManyEntriesAcrossBuffers() throws {
        let directory = makeTemporaryDirectory()
        for index in 0..<3000 {
            FileManager.default.createFile(atPath: directory.appending(path: "file-with-a-longish-name-\(index).dat").path, contents: nil)
        }
        XCTAssertEqual(try DirectoryReader.count(directory.path, visibility: .standard), 3000)
    }

    func testTrailingSlashAndMissingDirectory() throws {
        let directory = makeTemporaryDirectory()
        makeFile(directory, "x")
        XCTAssertEqual(try DirectoryReader.read(directory.path + "/").first?.path, directory.path + "/x")
        XCTAssertThrowsError(try DirectoryReader.read(directory.appending(path: "missing").path)) { error in
            XCTAssertNotNil((error as? DirectoryReader.ReadError)?.errorDescription)
        }
    }

    func testCancellationStopsEarly() throws {
        let directory = makeTemporaryDirectory()
        makeFile(directory, "x")
        XCTAssertTrue(try DirectoryReader.read(directory.path, isCancelled: { true }).isEmpty)
    }
}
