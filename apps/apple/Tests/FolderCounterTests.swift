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
        let counter = FolderCounter(root: directory.path, visibility: .standard, cache: FolderCountCache())
        XCTAssertNil(counter.count(for: folder.path))
        XCTAssertTrue(counter.isCounting(folder.path))
        waitForChange(counter) { counter.count(for: folder.path) == 2 }
        XCTAssertFalse(counter.isCounting(folder.path))
        XCTAssertEqual(counter.count(for: folder.path), 2)
    }

    func testKnownCountsSkipFailures() {
        let directory = makeTemporaryDirectory()
        let folder = makeFolder(directory, "Folder")
        makeFile(folder, "a.txt")
        let missing = directory.appendingPathComponent("missing").path
        let counter = FolderCounter(root: directory.path, visibility: .standard, cache: FolderCountCache())
        _ = counter.count(for: folder.path)
        _ = counter.count(for: missing)
        waitForChange(counter) { !counter.isCounting(folder.path) && !counter.isCounting(missing) }
        XCTAssertEqual(counter.knownCounts, [folder.path: 1])
    }

    func testVisibilityChangeRecounts() {
        let directory = makeTemporaryDirectory()
        let folder = makeFolder(directory, "Folder")
        makeFile(folder, "a.txt")
        makeFile(folder, ".hidden")
        makeFile(folder, ".DS_Store")
        let counter = FolderCounter(root: directory.path, visibility: .standard, cache: FolderCountCache())
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
        let counter = FolderCounter(root: directory.path, visibility: .standard, cache: FolderCountCache())
        XCTAssertNil(counter.count(for: missing))
        waitForChange(counter) { !counter.isCounting(missing) }
        XCTAssertNil(counter.count(for: missing))
        XCTAssertFalse(counter.isCounting(missing))
    }

    func testUpdatesWhenFolderContentsChange() {
        let directory = makeTemporaryDirectory()
        let folder = makeFolder(directory, "Folder")
        makeFile(folder, "a.txt")
        let counter = FolderCounter(root: directory.path, visibility: .standard, latency: 0.05, cache: FolderCountCache(refreshInterval: 0))
        _ = counter.count(for: folder.path)
        waitForChange(counter) { counter.count(for: folder.path) == 1 }

        makeFile(folder, "b.txt")
        waitForChange(counter) { counter.count(for: folder.path) == 2 }
    }

    func testInvalidateKeepsCountUntilRecounted() {
        let directory = makeTemporaryDirectory()
        let folder = makeFolder(directory, "Folder")
        let nested = makeFolder(folder, "Nested")
        let counter = FolderCounter(root: directory.path, visibility: .standard, cache: FolderCountCache(refreshInterval: 0))
        _ = counter.count(for: folder.path)
        _ = counter.count(for: nested.path)
        waitForChange(counter) { counter.count(for: folder.path) == 1 && counter.count(for: nested.path) == 0 }

        makeFile(nested, "a.txt")
        counter.invalidate(nested.path + "/")
        XCTAssertEqual(counter.count(for: nested.path), 0)
        XCTAssertTrue(counter.isCounting(nested.path))
        waitForChange(counter) { counter.count(for: nested.path) == 1 }

        makeFile(folder, "b.txt")
        makeFile(nested, "c.txt")
        counter.invalidateAll(under: folder.path)
        XCTAssertEqual(counter.count(for: folder.path), 1)
        XCTAssertEqual(counter.count(for: nested.path), 1)
        waitForChange(counter) { counter.count(for: folder.path) == 2 && counter.count(for: nested.path) == 2 }
    }

    func testRefreshesChangedFolderAtMostOncePerInterval() {
        let directory = makeTemporaryDirectory()
        let folder = makeFolder(directory, "Folder")
        let cache = FolderCountCache(refreshInterval: 0.5)
        let counter = FolderCounter(root: directory.path, visibility: .standard, cache: cache)
        _ = counter.count(for: folder.path)
        waitForChange(counter) { counter.count(for: folder.path) == 0 }
        let countedAt = cache.entry(for: folder.path, visibility: .standard)!.countedAt

        makeFile(folder, "a.txt")
        counter.invalidate(folder.path)
        XCTAssertEqual(counter.count(for: folder.path), 0)
        XCTAssertFalse(counter.isCounting(folder.path))
        waitForChange(counter) { cache.entry(for: folder.path, visibility: .standard)?.count == 1 }
        XCTAssertGreaterThanOrEqual(cache.entry(for: folder.path, visibility: .standard)!.countedAt.timeIntervalSince(countedAt), 0.5)
    }

    func testReusesCachedCountsAcrossCounters() {
        let directory = makeTemporaryDirectory()
        let folder = makeFolder(directory, "Folder")
        makeFile(folder, "a.txt")
        let cache = FolderCountCache(refreshInterval: 0.3)
        let first = FolderCounter(root: directory.path, visibility: .standard, cache: cache)
        _ = first.count(for: folder.path)
        waitForChange(first) { first.count(for: folder.path) == 1 }

        makeFile(folder, "b.txt")
        let second = FolderCounter(root: directory.path, visibility: .standard, cache: cache)
        XCTAssertEqual(second.count(for: folder.path), 1)
        XCTAssertEqual(second.knownCounts, [folder.path: 1])
        XCTAssertFalse(second.isCounting(folder.path))
        waitForChange(second) { second.count(for: folder.path) == 2 }
    }

    func testUnchangedRecountDoesNotNotify() {
        let directory = makeTemporaryDirectory()
        let folder = makeFolder(directory, "Folder")
        let cache = FolderCountCache(refreshInterval: 0)
        let counter = FolderCounter(root: directory.path, visibility: .standard, cache: cache)
        _ = counter.count(for: folder.path)
        waitForChange(counter) { counter.count(for: folder.path) == 0 }

        var notified = false
        counter.onChange = { notified = true }
        let recounted = expectation(forNotification: .folderCountsChanged, object: cache)
        counter.invalidate(folder.path)
        wait(for: [recounted], timeout: 5)
        let drained = expectation(description: "drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)
        XCTAssertFalse(notified)
        XCTAssertFalse(cache.entry(for: folder.path, visibility: .standard)!.stale)
    }

    func testMapsResolvedEventPathsToRoot() {
        let directory = makeTemporaryDirectory()
        let link = FileManager.default.temporaryDirectory.appending(path: "CubbyLink-\(UUID().uuidString)").path
        try! FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: directory.path)
        let folder = makeFolder(directory, "Folder")
        let linked = link + "/Folder"
        let counter = FolderCounter(root: link, visibility: .standard, latency: 0.05, cache: FolderCountCache(refreshInterval: 0))
        _ = counter.count(for: linked)
        waitForChange(counter) { counter.count(for: linked) == 0 }

        makeFile(folder, "a.txt")
        waitForChange(counter) { counter.count(for: linked) == 1 }
    }
}
