import XCTest
@testable import CubbyCore

final class FolderViewStoreTests: XCTestCase {
    private let icons = FolderView(mode: .icons, sort: .size, ascending: false, iconSize: 128)
    private let one = FolderIdentity(device: 1, inode: 10)
    private let two = FolderIdentity(device: 1, inode: 20)

    private func makeStore() -> FolderViewStore {
        FolderViewStore(url: makeTemporaryDirectory().appending(path: "f.json"), legacyProfile: "p")
    }

    func testStoresAndPersistsViews() throws {
        let url = makeTemporaryDirectory().appending(path: "folders.json")
        let store = FolderViewStore(url: url, legacyProfile: "p")
        XCTAssertFalse(store.isDirty)
        XCTAssertNil(store.view(for: "/a", identity: one, profile: "p"))
        store.setView(icons, for: "/a", identity: one, profile: "p", defaultView: .standard)
        XCTAssertTrue(store.isDirty)
        try store.save()
        XCTAssertFalse(store.isDirty)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        XCTAssertNil(json?["folders"])
        XCTAssertNotNil((json?["profiles"] as? [String: Any])?["p"])
        let reloaded = FolderViewStore(url: url, legacyProfile: "p")
        XCTAssertEqual(reloaded.view(for: "/a", identity: one, profile: "p"), icons)
        XCTAssertFalse(reloaded.isDirty)
    }

    func testPersistsColumns() throws {
        let url = makeTemporaryDirectory().appending(path: "folders.json")
        var view = FolderView.standard
        view.columns = [.init(id: "kind", width: 90, hidden: false), .init(id: "name", width: 300, hidden: false)]
        let store = FolderViewStore(url: url, legacyProfile: nil)
        store.setView(view, for: "/a", identity: one, profile: "p", defaultView: .standard)
        try store.save()
        XCTAssertEqual(FolderViewStore(url: url, legacyProfile: nil).view(for: "/a", identity: one, profile: "p")?.columns, view.columns)
    }

    func testViewsAreScopedToProfile() {
        let store = makeStore()
        var list = FolderView.standard
        list.columns = [.init(id: "size", width: 80, hidden: true)]
        store.setView(icons, for: "/a", identity: one, profile: "work", defaultView: .standard)
        store.setView(list, for: "/a", identity: one, profile: "home", defaultView: .standard)
        XCTAssertEqual(store.view(for: "/a", identity: one, profile: "work"), icons)
        XCTAssertEqual(store.view(for: "/a", identity: one, profile: "home"), list)
        XCTAssertNil(store.view(for: "/a", identity: one, profile: "other"))
        XCTAssertNil(store.view(for: "/b", identity: two, profile: "work"))
        store.setView(.standard, for: "/a", identity: one, profile: "work", defaultView: .standard)
        XCTAssertNil(store.view(for: "/a", identity: one, profile: "work"))
        XCTAssertEqual(store.view(for: "/a", identity: one, profile: "home"), list)
        XCTAssertNil(store.profiles["work"])
    }

    func testDefaultViewRemovesEntry() {
        let store = makeStore()
        store.setView(icons, for: "/a", identity: one, profile: "p", defaultView: .standard)
        store.setView(.standard, for: "/a", identity: one, profile: "p", defaultView: .standard)
        XCTAssertTrue(store.entries(for: "p").isEmpty)
        XCTAssertNil(store.view(for: "/b", identity: one, profile: "p"))
    }

    func testColumnsMakeViewDifferFromDefault() {
        let store = makeStore()
        var view = FolderView.standard
        view.columns = [.init(id: "name", width: 200, hidden: false)]
        store.setView(view, for: "/a", identity: one, profile: "p", defaultView: .standard)
        XCTAssertEqual(store.view(for: "/a", identity: one, profile: "p"), view)
    }

    func testFollowsRenamedFolderByIdentity() {
        let store = makeStore()
        store.setView(icons, for: "/old", identity: one, profile: "p", defaultView: .standard)
        store.setView(icons, for: "/old", identity: one, profile: "q", defaultView: .standard)
        XCTAssertEqual(store.view(for: "/new", identity: one, profile: "p"), icons)
        XCTAssertNil(store.entries(for: "p")["/old"])
        XCTAssertEqual(store.entries(for: "p")["/new"]?.identity, one)
        XCTAssertNotNil(store.entries(for: "q")["/old"])
    }

    func testReplacedFolderAtSamePathDropsStaleEntry() {
        let store = makeStore()
        store.setView(icons, for: "/a", identity: one, profile: "p", defaultView: .standard)
        XCTAssertNil(store.view(for: "/a", identity: two, profile: "p"))
        XCTAssertTrue(store.entries(for: "p").isEmpty)
    }

    func testSettingViewMovesEntryWithSameIdentity() {
        let store = makeStore()
        store.setView(icons, for: "/old", identity: one, profile: "p", defaultView: .standard)
        store.setView(icons, for: "/new", identity: one, profile: "p", defaultView: .standard)
        XCTAssertEqual(Array(store.entries(for: "p").keys), ["/new"])
    }

    func testRemoveProfileDropsItsEntries() throws {
        let url = makeTemporaryDirectory().appending(path: "folders.json")
        let store = FolderViewStore(url: url, legacyProfile: nil)
        store.setView(icons, for: "/a", identity: one, profile: "p", defaultView: .standard)
        store.setView(icons, for: "/a", identity: one, profile: "q", defaultView: .standard)
        try store.save()
        store.removeProfile("missing")
        XCTAssertFalse(store.isDirty)
        store.removeProfile("p")
        XCTAssertTrue(store.isDirty)
        XCTAssertNil(store.view(for: "/b", identity: one, profile: "p"))
        try store.save()
        let reloaded = FolderViewStore(url: url, legacyProfile: nil)
        XCTAssertEqual(Array(reloaded.profiles.keys), ["q"])
    }

    func testMigratesLegacyFoldersToProfile() throws {
        let url = makeTemporaryDirectory().appending(path: "folders.json")
        try JSONStore.write(Data(#"{"folders":{"/a":{"view":{"mode":"icons","sort":"size","ascending":false,"iconSize":128},"identity":{"device":1,"inode":10}}}}"#.utf8), to: url)
        let store = FolderViewStore(url: url, legacyProfile: "p")
        XCTAssertTrue(store.isDirty)
        XCTAssertEqual(store.view(for: "/renamed", identity: one, profile: "p"), icons)
        try store.save()
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        XCTAssertNil(json?["folders"])
        XCTAssertEqual(FolderViewStore(url: url, legacyProfile: "x").view(for: "/renamed", identity: one, profile: "p"), icons)
    }

    func testKeepsLegacyFoldersWithoutProfile() throws {
        let url = makeTemporaryDirectory().appending(path: "folders.json")
        try JSONStore.write(Data(#"{"folders":{"/a":{"view":{"mode":"icons","sort":"size","ascending":false,"iconSize":128}}}}"#.utf8), to: url)
        let store = FolderViewStore(url: url, legacyProfile: nil)
        XCTAssertFalse(store.isDirty)
        XCTAssertTrue(store.profiles.isEmpty)
        store.setView(icons, for: "/b", identity: nil, profile: "p", defaultView: .standard)
        try store.save()
        let migrated = FolderViewStore(url: url, legacyProfile: "q")
        XCTAssertEqual(migrated.view(for: "/a", identity: nil, profile: "q"), icons)
        XCTAssertEqual(migrated.view(for: "/b", identity: nil, profile: "p"), icons)
    }

    func testPrunesMissingPathsAcrossProfilesOnlyAboveThreshold() {
        let store = makeStore()
        store.setView(icons, for: "/gone", identity: nil, profile: "p", defaultView: .standard)
        store.setView(icons, for: "/gone", identity: one, profile: "q", defaultView: .standard)
        store.prune { _ in false }
        XCTAssertEqual(store.count, 2)
        for index in 0..<FolderViewStore.pruneThreshold {
            store.setView(icons, for: "/keep/\(index)", identity: nil, profile: "p", defaultView: .standard)
        }
        store.prune { $0.hasPrefix("/keep") }
        XCTAssertNil(store.entries(for: "p")["/gone"])
        XCTAssertNil(store.profiles["q"])
        XCTAssertEqual(store.count, FolderViewStore.pruneThreshold)
        XCTAssertNil(store.view(for: "/elsewhere", identity: one, profile: "q"))
    }

    func testIdentityFromPath() {
        let directory = makeTemporaryDirectory()
        XCTAssertNotNil(FolderIdentity(path: directory.path))
        XCTAssertEqual(FolderIdentity(path: directory.path), FolderIdentity(path: directory.path))
        XCTAssertNil(FolderIdentity(path: directory.appending(path: "missing").path))
    }
}
