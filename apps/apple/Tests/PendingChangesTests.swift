import XCTest
@testable import CubbyCore

@MainActor
final class PendingChangesTests: XCTestCase {
    func testMoveRemovesSourcesAndAddsThemToTheDestination() {
        let directory = makeTemporaryDirectory()
        let source = makeFolder(directory, "source")
        let destination = makeFolder(directory, "destination")
        let a = makeFile(source, "a.txt", contents: "12")
        let b = makeFile(destination, "b.txt")
        let change = PendingChange.move([a, b], to: destination)
        XCTAssertEqual(change.removed, [a])
        XCTAssertEqual(change.added, [Transfer(source: a, destination: destination.appending(path: "a.txt"))])
        XCTAssertTrue(PendingChange.copy([a, b], to: destination).removed.isEmpty)
        XCTAssertEqual(PendingChange.copy([a, b], to: destination).added, change.added)
        XCTAssertEqual(PendingChange.remove([a]).removed, [a])

        let back = PendingChange.moveBack([Transfer(source: a, destination: b)])
        XCTAssertEqual(back.removed, [b])
        XCTAssertEqual(back.added, [Transfer(source: b, destination: a)])

        let changes = PendingChanges()
        let token = changes.begin(change)
        XCTAssertEqual(changes.snapshot.changes(in: source.path), DirectoryChanges(removed: ["a.txt"]))
        XCTAssertEqual(changes.snapshot.changes(in: destination.path), DirectoryChanges(added: ["a.txt"]))
        let shown = changes.snapshot.applied(to: [FileItem(directory: destination.path, name: "b.txt", isDirectory: false)], in: destination.path)
        XCTAssertEqual(names(shown), ["b.txt", "a.txt"])
        XCTAssertEqual(shown[1].path, destination.appending(path: "a.txt").path)
        XCTAssertEqual(shown[1].size, 2)
        XCTAssertTrue(changes.snapshot.applied(to: [FileItem(directory: source.path, name: "a.txt", isDirectory: false)], in: source.path).isEmpty)

        changes.end(token)
        XCTAssertTrue(changes.snapshot.isEmpty)
        XCTAssertEqual(changes.snapshot, PendingSnapshot())
    }

    func testSkipsAddingOverExistingOrMissingItems() {
        let directory = makeTemporaryDirectory()
        let destination = makeFolder(directory, "destination")
        let a = makeFile(directory, "a.txt")
        makeFile(destination, "a.txt")
        let missing = directory.appending(path: "missing.txt")
        let changes = PendingChanges()
        _ = changes.begin(.copy([a, missing], to: destination))
        XCTAssertTrue(changes.snapshot.isEmpty)
    }

    func testKeepsChangesUntilEveryTaskEnds() {
        let directory = makeTemporaryDirectory()
        let a = directory.appending(path: "a.txt")
        let b = directory.appending(path: "b.txt")
        let changes = PendingChanges()
        let first = changes.begin(.remove([a, b]))
        let second = changes.begin(.remove([a]))
        XCTAssertEqual(changes.snapshot.changes(in: directory.path).removed, ["a.txt", "b.txt"])
        changes.end(first)
        XCTAssertEqual(changes.snapshot.changes(in: directory.path).removed, ["a.txt"])
        changes.end(first)
        changes.end(second)
        XCTAssertTrue(changes.snapshot.isEmpty)
        XCTAssertTrue(DirectoryChanges(removed: ["a"]).isSubset(of: DirectoryChanges(removed: ["a", "b"], added: ["c"])))
        XCTAssertFalse(DirectoryChanges(added: ["c"]).isSubset(of: DirectoryChanges(removed: ["c"])))
    }

    func testMatchesDirectoriesThroughSymlinks() {
        let directory = makeTemporaryDirectory()
        let real = makeFolder(directory, "real")
        let link = directory.appending(path: "link")
        try! FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let source = makeFile(directory, "c.txt")
        let changes = PendingChanges()
        _ = changes.begin(PendingChange(removed: [real.appending(path: "a.txt")], added: [Transfer(source: source, destination: real.appending(path: "c.txt"))]))
        let items = [FileItem(directory: link.path, name: "a.txt", isDirectory: false), FileItem(directory: link.path, name: "b.txt", isDirectory: false)]
        let shown = changes.snapshot.applied(to: items, in: link.path)
        XCTAssertEqual(names(shown), ["b.txt", "c.txt"])
        XCTAssertEqual(shown[1].directory, link.path)
        XCTAssertEqual(changes.snapshot.changes(in: link.path), DirectoryChanges(removed: ["a.txt"], added: ["c.txt"]))
    }

    func testPostsChangesFromItself() {
        let changes = PendingChanges()
        var posts = 0
        let observer = NotificationCenter.default.addObserver(forName: .pendingChangesChanged, object: changes, queue: nil) { _ in posts += 1 }
        let empty = changes.begin(PendingChange())
        changes.end(empty)
        let token = changes.begin(.remove([URL(filePath: "/tmp/a.txt")]))
        changes.end(token)
        XCTAssertEqual(posts, 2)
        NotificationCenter.default.removeObserver(observer)
    }
}
