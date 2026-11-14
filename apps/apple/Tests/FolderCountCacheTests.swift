import XCTest
@testable import CubbyCore

@MainActor
final class FolderCountCacheTests: XCTestCase {
    private func recount(_ cache: FolderCountCache, _ path: String, visibility: Visibility = .standard) -> Notification {
        var received: Notification?
        let counted = expectation(forNotification: .folderCountsChanged, object: cache) { notification in
            received = notification
            return notification.userInfo?["path"] as? String == path && notification.userInfo?["visibility"] as? Visibility == visibility
        }
        cache.recount(path, visibility: visibility)
        wait(for: [counted], timeout: 5)
        return received!
    }

    func testRecountStoresCountsPerVisibility() {
        let directory = makeTemporaryDirectory()
        let folder = makeFolder(directory, "Folder")
        makeFile(folder, "a.txt")
        makeFile(folder, ".hidden")
        let cache = FolderCountCache()
        XCTAssertEqual(cache.refreshInterval, 60)
        XCTAssertNil(cache.entry(for: folder.path, visibility: .standard))

        let before = Date()
        cache.recount(folder.path, visibility: .standard)
        XCTAssertTrue(cache.isCounting(folder.path, visibility: .standard))
        let hidden = Visibility(showHidden: true, showDSStore: false)
        XCTAssertFalse(cache.isCounting(folder.path, visibility: hidden))
        let notification = recount(cache, folder.path)
        XCTAssertEqual(notification.userInfo?["changed"] as? Bool, true)
        XCTAssertFalse(cache.isCounting(folder.path, visibility: .standard))
        let entry = cache.entry(for: folder.path, visibility: .standard)!
        XCTAssertEqual(entry.count, 1)
        XCTAssertFalse(entry.stale)
        XCTAssertGreaterThanOrEqual(entry.countedAt, before)

        _ = recount(cache, folder.path, visibility: hidden)
        XCTAssertEqual(cache.knownCounts(for: .standard), [folder.path: 1])
        XCTAssertEqual(cache.knownCounts(for: hidden), [folder.path: 2])
    }

    func testUnchangedRecountReportsNoChange() {
        let directory = makeTemporaryDirectory()
        let folder = makeFolder(directory, "Folder")
        let cache = FolderCountCache()
        _ = recount(cache, folder.path)
        XCTAssertEqual(recount(cache, folder.path).userInfo?["changed"] as? Bool, false)
        makeFile(folder, "a.txt")
        XCTAssertEqual(recount(cache, folder.path).userInfo?["changed"] as? Bool, true)
    }

    func testFailedCountIsStoredButNotKnown() {
        let directory = makeTemporaryDirectory()
        let folder = makeFolder(directory, "Folder")
        let cache = FolderCountCache()
        _ = recount(cache, folder.path)
        XCTAssertEqual(cache.knownCounts(for: .standard), [folder.path: 0])

        try! FileManager.default.removeItem(atPath: folder.path)
        _ = recount(cache, folder.path)
        XCTAssertEqual(cache.entry(for: folder.path, visibility: .standard)?.count, -1)
        XCTAssertEqual(cache.knownCounts(for: .standard), [:])
    }

    func testMarkStale() {
        let directory = makeTemporaryDirectory()
        let folder = makeFolder(directory, "Folder")
        let nested = makeFolder(folder, "Nested")
        let sibling = makeFolder(directory, "Folder2")
        let hidden = Visibility(showHidden: true, showDSStore: false)
        let cache = FolderCountCache()
        _ = recount(cache, folder.path)
        _ = recount(cache, folder.path, visibility: hidden)
        _ = recount(cache, nested.path)
        _ = recount(cache, sibling.path)

        cache.markStale(folder.path)
        XCTAssertTrue(cache.entry(for: folder.path, visibility: .standard)!.stale)
        XCTAssertTrue(cache.entry(for: folder.path, visibility: hidden)!.stale)
        XCTAssertFalse(cache.entry(for: nested.path, visibility: .standard)!.stale)
        XCTAssertEqual(cache.knownCounts(for: .standard)[folder.path], 1)

        _ = recount(cache, folder.path)
        XCTAssertFalse(cache.entry(for: folder.path, visibility: .standard)!.stale)

        XCTAssertEqual(Set(cache.markStale(under: folder.path)), [folder.path, nested.path])
        XCTAssertTrue(cache.entry(for: folder.path, visibility: .standard)!.stale)
        XCTAssertTrue(cache.entry(for: nested.path, visibility: .standard)!.stale)
        XCTAssertFalse(cache.entry(for: sibling.path, visibility: .standard)!.stale)
    }

    func testChangeDuringCountLeavesEntryStale() {
        let directory = makeTemporaryDirectory()
        let folder = makeFolder(directory, "Folder")
        let cache = FolderCountCache()
        let counted = expectation(forNotification: .folderCountsChanged, object: cache)
        cache.recount(folder.path, visibility: .standard)
        cache.markStale(folder.path)
        wait(for: [counted], timeout: 5)
        XCTAssertTrue(cache.entry(for: folder.path, visibility: .standard)!.stale)

        cache.recount(folder.path, visibility: .standard)
        cache.markStale(under: directory.path)
        _ = recount(cache, folder.path)
        XCTAssertTrue(cache.entry(for: folder.path, visibility: .standard)!.stale)
    }
}
