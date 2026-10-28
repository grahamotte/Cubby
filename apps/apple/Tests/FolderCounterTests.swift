import XCTest
@testable import CubbyCore

@MainActor
final class FolderCounterTests: XCTestCase {
    private func waitForChange(_ counter: FolderCounter, until done: @escaping () -> Bool) {
        let changed = expectation(description: "change")
        changed.assertForOverFulfill = false
        counter.onChange = { if done() { changed.fulfill() } }
        wait(for: [changed], timeout: 5)
    }

    func testCountsInBackgroundAndCaches() {
        let directory = makeTemporaryDirectory()
        let folder = makeFolder(directory, "Folder")
        makeFile(folder, "a.txt")
        makeFile(folder, "b.txt")
        makeFile(folder, ".hidden")
        let counter = FolderCounter(root: directory.path, visibility: .standard)
        XCTAssertNil(counter.count(for: folder.path))
        XCTAssertTrue(counter.isCounting(folder.path))
        waitForChange(counter) { counter.count(for: folder.path) == 2 }
        XCTAssertFalse(counter.isCounting(folder.path))
        XCTAssertEqual(counter.count(for: folder.path), 2)
    }

    func testVisibilityChangeRecounts() {
        let directory = makeTemporaryDirectory()
        let folder = makeFolder(directory, "Folder")
        makeFile(folder, "a.txt")
        makeFile(folder, ".hidden")
        makeFile(folder, ".DS_Store")
        let counter = FolderCounter(root: directory.path, visibility: .standard)
        _ = counter.count(for: folder.path)
        waitForChange(counter) { counter.count(for: folder.path) == 1 }

        counter.visibility = Visibility(showHidden: true, showDSStore: false)
        XCTAssertNil(counter.count(for: folder.path))
        waitForChange(counter) { counter.count(for: folder.path) == 2 }

        counter.visibility = Visibility(showHidden: true, showDSStore: true)
        _ = counter.count(for: folder.path)
        waitForChange(counter) { counter.count(for: folder.path) == 3 }
    }

    func testUnreadableFolderHasNoCount() {
        let directory = makeTemporaryDirectory()
        let missing = directory.appending(path: "missing").path
        let counter = FolderCounter(root: directory.path, visibility: .standard)
        XCTAssertNil(counter.count(for: missing))
        waitForChange(counter) { !counter.isCounting(missing) }
        XCTAssertNil(counter.count(for: missing))
        XCTAssertFalse(counter.isCounting(missing))
    }

    func testUpdatesWhenFolderContentsChange() {
        let directory = makeTemporaryDirectory()
        let folder = makeFolder(directory, "Folder")
        makeFile(folder, "a.txt")
        let counter = FolderCounter(root: directory.path, visibility: .standard, latency: 0.05)
        _ = counter.count(for: folder.path)
        waitForChange(counter) { counter.count(for: folder.path) == 1 }

        makeFile(folder, "b.txt")
        waitForChange(counter) { counter.count(for: folder.path) == 2 }
    }

    func testInvalidate() {
        let directory = makeTemporaryDirectory()
        let folder = makeFolder(directory, "Folder")
        let nested = makeFolder(folder, "Nested")
        let counter = FolderCounter(root: directory.path, visibility: .standard)
        _ = counter.count(for: folder.path)
        _ = counter.count(for: nested.path)
        waitForChange(counter) { counter.count(for: folder.path) == 1 && counter.count(for: nested.path) == 0 }

        counter.invalidate(nested.path + "/")
        XCTAssertNil(counter.count(for: nested.path))
        waitForChange(counter) { counter.count(for: nested.path) == 0 }

        counter.invalidateAll(under: folder.path)
        XCTAssertNil(counter.count(for: folder.path))
        XCTAssertNil(counter.count(for: nested.path))
        waitForChange(counter) { counter.count(for: folder.path) == 1 && counter.count(for: nested.path) == 0 }
    }

    func testMapsResolvedEventPathsToRoot() {
        let directory = makeTemporaryDirectory()
        let link = FileManager.default.temporaryDirectory.appending(path: "CubbyLink-\(UUID().uuidString)").path
        try! FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: directory.path)
        let folder = makeFolder(directory, "Folder")
        let linked = link + "/Folder"
        let counter = FolderCounter(root: link, visibility: .standard, latency: 0.05)
        _ = counter.count(for: linked)
        waitForChange(counter) { counter.count(for: linked) == 0 }

        makeFile(folder, "a.txt")
        waitForChange(counter) { counter.count(for: linked) == 1 }
    }
}
