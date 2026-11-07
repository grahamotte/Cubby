import XCTest
import AppKit
@testable import CubbyCore

final class FileHistoryTests: XCTestCase {
    private let downloads = URL(filePath: "/Users/me/Downloads", directoryHint: .isDirectory)
    private let projects = URL(filePath: "/Users/me/Projects", directoryHint: .isDirectory)

    private func files(_ names: String..., in directory: URL? = nil) -> [URL] {
        names.map { (directory ?? downloads).appending(path: $0) }
    }

    private func finished(_ entry: HistoryEntry) -> HistoryEntry {
        var entry = entry
        entry.state = .finished
        return entry
    }

    func testDescribesBatchesFromTheirItems() {
        let single = HistoryEntry(.move, items: files("report.pdf"), destination: projects)
        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(single.name, "report.pdf")
        XCTAssertEqual(single.source, "/Users/me/Downloads")
        XCTAssertEqual(single.destination, "/Users/me/Projects")
        XCTAssertEqual(single.state, .running)
        XCTAssertNil(single.finished)
        XCTAssertEqual(single.errors, 0)

        let many = HistoryEntry(.move, items: files("a", "b", "c"), destination: projects)
        XCTAssertEqual(many.count, 3)
        XCTAssertNil(many.name)
        XCTAssertEqual(many.source, "/Users/me/Downloads")

        let mixed = HistoryEntry(.copy, items: [downloads.appending(path: "a"), projects.appending(path: "b")], destination: downloads)
        XCTAssertNil(mixed.source)

        let done = HistoryEntry(.newFolder, items: files("New Folder"), state: .finished)
        XCTAssertNotNil(done.finished)
        XCTAssertEqual(done.errors, 0)
        let failed = HistoryEntry(.rename, items: files("a"), target: "b", state: .failed)
        XCTAssertEqual(failed.errors, 1)
    }

    func testFindsTheCommonFolder() {
        XCTAssertEqual(HistoryEntry.folder(of: files("a", "b"))?.path, "/Users/me/Downloads")
        XCTAssertNil(HistoryEntry.folder(of: [downloads.appending(path: "a"), projects.appending(path: "b")]))
        XCTAssertNil(HistoryEntry.folder(of: []))
    }

    func testPhrasesEachKind() {
        XCTAssertEqual(HistoryEntry(.move, items: files("report.pdf"), destination: projects).summary, "Moving report.pdf from Downloads to Projects")
        XCTAssertEqual(finished(HistoryEntry(.move, items: files("report.pdf"), destination: projects)).summary, "Moved report.pdf from Downloads to Projects")
        XCTAssertEqual(finished(HistoryEntry(.move, items: [downloads.appending(path: "a"), projects.appending(path: "b")], destination: downloads)).summary, "Moved 2 items to Downloads")
        let many = Array(repeating: downloads.appending(path: "a"), count: 1200)
        XCTAssertEqual(finished(HistoryEntry(.copy, items: many, destination: projects)).summary, "Copied \(1200.formatted()) items from Downloads to Projects")
        XCTAssertEqual(finished(HistoryEntry(.trash, items: files("a", "b"))).summary, "Moved 2 items from Downloads to the Trash")
        XCTAssertEqual(finished(HistoryEntry(.putBack, items: files("a"), destination: downloads)).summary, "Put back a to Downloads")
        XCTAssertEqual(HistoryEntry(.putBack, items: files("a"), destination: downloads).summary, "Putting back a to Downloads")
        XCTAssertEqual(finished(HistoryEntry(.moveBack, items: files("a", in: projects), destination: downloads)).summary, "Moved a back to Downloads")
        XCTAssertEqual(finished(HistoryEntry(.duplicate, items: files("a", "b"))).summary, "Duplicated 2 items in Downloads")
        XCTAssertEqual(HistoryEntry(.rename, items: files("a.txt"), target: "b.txt", state: .finished).summary, "Renamed a.txt to b.txt")
        XCTAssertEqual(HistoryEntry(.newFolder, items: files("untitled folder"), state: .finished).summary, "Created folder untitled folder in Downloads")
        XCTAssertEqual(HistoryEntry(.newFile, items: files("untitled.txt"), state: .finished).summary, "Created file untitled.txt in Downloads")
        XCTAssertEqual(finished(HistoryEntry(.newFolderWithItems, items: files("a", "b"), destination: downloads.appending(path: "New Folder With Items"), target: "New Folder With Items")).summary, "Moved 2 items into new folder New Folder With Items")
        XCTAssertEqual(finished(HistoryEntry(.compress, items: files("a", "b"), destination: downloads, target: "Archive.zip")).summary, "Compressed 2 items into Archive.zip")
        XCTAssertEqual(HistoryEntry(.compress, items: files("a"), destination: downloads, target: "a.zip").summary, "Compressing a into a.zip")
    }

    func testDescribesSymbolsAndStates() {
        for kind in HistoryEntry.Kind.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: HistoryEntry(kind, items: files("a")).symbolName, accessibilityDescription: nil), kind.rawValue)
        }
        var entry = HistoryEntry(.move, items: files("a"), destination: projects)
        XCTAssertEqual(entry.stateDescription, "Running")
        entry.state = .finished
        XCTAssertEqual(entry.stateDescription, "Finished")
        entry.state = .stopped
        XCTAssertEqual(entry.stateDescription, "Stopped")
        entry.state = .failed
        entry.errors = 1
        XCTAssertEqual(entry.stateDescription, "Failed")
        entry.errors = 3
        XCTAssertEqual(entry.stateDescription, "Failed with 3 errors")
    }

    func testRecordsUpdatesAndPersists() {
        let url = makeTemporaryDirectory().appending(path: "history.json")
        let history = FileHistory(url: url)
        XCTAssertTrue(history.entries.isEmpty)
        let first = HistoryEntry(.move, items: files("a"), destination: projects)
        history.record(first)
        history.record(HistoryEntry(.rename, items: files("b"), target: "c", state: .finished))
        history.update(first.id) { entry in
            entry.state = .failed
            entry.errors = 2
            entry.finished = Date()
        }
        history.update(UUID()) { $0.state = .stopped }
        XCTAssertEqual(history.entries.map(\.state), [.failed, .finished])

        let reloaded = FileHistory(url: url)
        XCTAssertEqual(reloaded.entries, history.entries)
        XCTAssertEqual(reloaded.entries[0].errors, 2)
    }

    func testLoadsRunningEntriesAsStopped() {
        let url = makeTemporaryDirectory().appending(path: "history.json")
        let history = FileHistory(url: url)
        history.record(HistoryEntry(.copy, items: files("a"), destination: projects))
        XCTAssertEqual(FileHistory(url: url).entries.map(\.state), [.stopped])

        history.record(HistoryEntry(.copy, items: files("b"), destination: projects))
        history.stopRunning()
        XCTAssertEqual(history.entries.map(\.state), [.stopped, .stopped])
        XCTAssertEqual(FileHistory(url: url).entries.map(\.state), [.stopped, .stopped])
    }

    func testListsRunningFirstThenNewest() {
        let now = Date()
        let history = FileHistory(url: nil) { now }
        let old = HistoryEntry(.trash, items: files("old"), state: .finished, date: now.addingTimeInterval(-60))
        let running = HistoryEntry(.move, items: files("running"), destination: projects, date: now.addingTimeInterval(-30))
        let new = HistoryEntry(.rename, items: files("new"), target: "newer", state: .finished, date: now)
        history.record(old)
        history.record(running)
        history.record(new)
        XCTAssertEqual(history.recent.map(\.id), [running.id, new.id, old.id])
    }

    func testExpiresOldEntries() {
        let url = makeTemporaryDirectory().appending(path: "history.json")
        var now = Date()
        let history = FileHistory(url: url) { now }
        let stale = HistoryEntry(.trash, items: files("stale"), state: .finished, date: now.addingTimeInterval(-FileHistory.retention + 60))
        let fresh = HistoryEntry(.trash, items: files("fresh"), state: .finished, date: now)
        history.record(stale)
        history.record(fresh)
        XCTAssertEqual(history.recent.map(\.id), [fresh.id, stale.id])

        now = now.addingTimeInterval(120)
        XCTAssertEqual(history.recent.map(\.id), [fresh.id])
        XCTAssertEqual(FileHistory(url: url) { now }.entries.map(\.id), [fresh.id])
        history.record(HistoryEntry(.trash, items: files("later"), state: .finished, date: now))
        XCTAssertEqual(history.entries.count, 2)
        XCTAssertFalse(history.entries.contains { $0.id == stale.id })
    }

    func testCapsTheEntryCount() {
        let history = FileHistory(url: nil)
        let entries = (0..<(FileHistory.limit + 2)).map { HistoryEntry(.trash, items: files("\($0)"), state: .finished) }
        for entry in entries {
            history.record(entry)
        }
        XCTAssertEqual(history.entries.count, FileHistory.limit)
        XCTAssertEqual(history.entries.first?.id, entries[2].id)
    }

    func testIgnoresUnreadableFiles() {
        let directory = makeTemporaryDirectory()
        let url = makeFile(directory, "history.json", contents: "nope")
        XCTAssertTrue(FileHistory(url: url).entries.isEmpty)
        XCTAssertTrue(FileHistory(url: directory.appending(path: "missing.json")).entries.isEmpty)
    }
}
