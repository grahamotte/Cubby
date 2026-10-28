import XCTest
@testable import CubbyCore

final class FolderViewStoreTests: XCTestCase {
    private let icons = FolderView(mode: .icons, sort: .size, ascending: false, iconSize: 128)
    private let one = FolderIdentity(device: 1, inode: 10)
    private let two = FolderIdentity(device: 1, inode: 20)

    func testStoresAndPersistsViews() throws {
        let url = makeTemporaryDirectory().appending(path: "folders.json")
        let store = FolderViewStore(url: url)
        XCTAssertNil(store.view(for: "/a", identity: one))
        store.setView(icons, for: "/a", identity: one, defaultView: .standard)
        XCTAssertTrue(store.isDirty)
        try store.save()
        XCTAssertFalse(store.isDirty)
        let reloaded = FolderViewStore(url: url)
        XCTAssertEqual(reloaded.view(for: "/a", identity: one), icons)
    }

    func testDefaultViewRemovesEntry() {
        let store = FolderViewStore(url: makeTemporaryDirectory().appending(path: "f.json"))
        store.setView(icons, for: "/a", identity: one, defaultView: .standard)
        store.setView(.standard, for: "/a", identity: one, defaultView: .standard)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNil(store.view(for: "/b", identity: one))
    }

    func testFollowsRenamedFolderByIdentity() {
        let store = FolderViewStore(url: makeTemporaryDirectory().appending(path: "f.json"))
        store.setView(icons, for: "/old", identity: one, defaultView: .standard)
        XCTAssertEqual(store.view(for: "/new", identity: one), icons)
        XCTAssertNil(store.entries["/old"])
        XCTAssertEqual(store.entries["/new"]?.identity, one)
    }

    func testReplacedFolderAtSamePathDropsStaleEntry() {
        let store = FolderViewStore(url: makeTemporaryDirectory().appending(path: "f.json"))
        store.setView(icons, for: "/a", identity: one, defaultView: .standard)
        XCTAssertNil(store.view(for: "/a", identity: two))
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testSettingViewMovesEntryWithSameIdentity() {
        let store = FolderViewStore(url: makeTemporaryDirectory().appending(path: "f.json"))
        store.setView(icons, for: "/old", identity: one, defaultView: .standard)
        store.setView(icons, for: "/new", identity: one, defaultView: .standard)
        XCTAssertEqual(Array(store.entries.keys), ["/new"])
    }

    func testPrunesMissingPathsOnlyAboveThreshold() {
        let store = FolderViewStore(url: makeTemporaryDirectory().appending(path: "f.json"))
        store.setView(icons, for: "/gone", identity: nil, defaultView: .standard)
        store.prune { _ in false }
        XCTAssertEqual(store.entries.count, 1)
        for index in 0...FolderViewStore.pruneThreshold {
            store.setView(icons, for: "/keep/\(index)", identity: nil, defaultView: .standard)
        }
        store.prune { $0.hasPrefix("/keep") }
        XCTAssertNil(store.entries["/gone"])
        XCTAssertEqual(store.entries.count, FolderViewStore.pruneThreshold + 1)
    }

    func testIdentityFromPath() {
        let directory = makeTemporaryDirectory()
        XCTAssertNotNil(FolderIdentity(path: directory.path))
        XCTAssertEqual(FolderIdentity(path: directory.path), FolderIdentity(path: directory.path))
        XCTAssertNil(FolderIdentity(path: directory.appending(path: "missing").path))
    }
}
