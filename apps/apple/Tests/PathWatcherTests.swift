import XCTest
@testable import CubbyCore

@MainActor
final class PathWatcherTests: XCTestCase {
    func testReportsDirectoryChanges() {
        let directory = makeTemporaryDirectory()
        let changed = expectation(description: "changed")
        changed.assertForOverFulfill = false
        let watcher = PathWatcher(path: directory.path, latency: 0.01) { changed.fulfill() }
        makeFile(directory, "new.txt")
        wait(for: [changed], timeout: 5)
        XCTAssertEqual(watcher.path, directory.path)
    }

    func testFollowsReplacedFile() {
        let directory = makeTemporaryDirectory()
        let file = makeFile(directory, "config.json", contents: "1")
        let first = expectation(description: "first")
        first.assertForOverFulfill = false
        var count = 0
        var second: XCTestExpectation?
        let watcher = PathWatcher(path: file.path, latency: 0.01) {
            count += 1
            if count == 1 { first.fulfill() } else { second?.fulfill() }
        }
        try! Data("2".utf8).write(to: file, options: .atomic)
        wait(for: [first], timeout: 5)
        let reopened = expectation(description: "reopened")
        reopened.assertForOverFulfill = false
        second = reopened
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let writer = FileHandle(forWritingAtPath: file.path)!
            writer.seekToEndOfFile()
            writer.write(Data("3".utf8))
            try? writer.close()
        }
        wait(for: [reopened], timeout: 5)
        XCTAssertEqual(watcher.path, file.path)
    }

    func testMissingPathIsHarmless() {
        let watcher = PathWatcher(path: "/nonexistent/\(UUID().uuidString)") {}
        XCTAssertNotNil(watcher)
    }
}
