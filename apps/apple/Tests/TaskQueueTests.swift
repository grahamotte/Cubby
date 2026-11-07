import XCTest
@testable import CubbyCore

@MainActor
final class TaskQueueTests: XCTestCase {
    private func entry(_ name: String) -> HistoryEntry {
        HistoryEntry(.trash, items: [URL(filePath: "/tmp/\(name)")])
    }

    private func run(_ queue: TaskQueue, _ entry: HistoryEntry, change: PendingChange = PendingChange(), work: @escaping (FileOperations) -> OperationResult) -> OperationResult {
        let done = expectation(description: entry.summary)
        var output = OperationResult()
        queue.enqueue(entry, change: change, work: work) { result in
            output = result
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return output
    }

    func testRunsTasksAndLogsTheirResults() {
        let directory = makeTemporaryDirectory()
        let source = makeFolder(directory, "source")
        let destination = makeFolder(directory, "destination")
        let file = makeFile(source, "a.txt")
        let changes = PendingChanges()
        let history = FileHistory(url: directory.appending(path: "history.json"))
        let queue = TaskQueue(changes: changes, history: history)

        let result = run(queue, HistoryEntry(.move, items: [file], destination: destination), change: .move([file], to: destination)) { operations in
            operations.move([file], to: destination) { _ in .stop }
        }
        XCTAssertEqual(result.transfers, [Transfer(source: file, destination: destination.appending(path: "a.txt"))])
        XCTAssertTrue(changes.snapshot.isEmpty)
        XCTAssertFalse(queue.isBusy)
        XCTAssertNil(queue.summary)
        let task = queue.tasks[0]
        XCTAssertEqual(task.title, "Moved a.txt from source to destination")
        XCTAssertEqual(task.state, .finished)
        XCTAssertEqual(task.transfers, result.transfers)
        XCTAssertNotNil(task.started)
        XCTAssertNotNil(task.finished)

        _ = run(queue, entry("failing")) { _ in OperationResult(errors: [OperationError(message: "Nope"), OperationError(message: "Again")]) }
        _ = run(queue, entry("stopping")) { _ in OperationResult(stopped: true) }
        XCTAssertEqual(queue.tasks.map(\.state), [.finished, .failed, .stopped])
        XCTAssertEqual(queue.tasks[1].errors, ["Nope", "Again"])
        XCTAssertEqual(Set(queue.tasks.map(\.id)).count, 3)

        XCTAssertEqual(history.entries.map(\.state), [.finished, .failed, .stopped])
        XCTAssertEqual(history.entries.map(\.errors), [0, 2, 0])
        XCTAssertEqual(history.entries[0].finished, task.finished)
        XCTAssertEqual(history.entries.map(\.id), queue.tasks.map(\.entry.id))
        XCTAssertEqual(FileHistory(url: directory.appending(path: "history.json")).entries, history.entries)
    }

    func testRecordsSynchronousOperations() {
        let history = FileHistory(url: nil)
        let queue = TaskQueue(changes: PendingChanges(), history: history)
        var posts = 0
        let observer = NotificationCenter.default.addObserver(forName: .taskQueueChanged, object: queue, queue: nil) { _ in posts += 1 }
        queue.record(HistoryEntry(.rename, items: [URL(filePath: "/tmp/a")], target: "b", state: .finished))
        XCTAssertEqual(history.entries.map(\.summary), ["Renamed a to b"])
        XCTAssertTrue(queue.tasks.isEmpty)
        XCTAssertEqual(posts, 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testAppliesPendingChangesWhileQueued() {
        let directory = makeTemporaryDirectory()
        let file = makeFile(directory, "a.txt")
        let changes = PendingChanges()
        let history = FileHistory(url: nil)
        let queue = TaskQueue(changes: changes, history: history)
        let gate = DispatchSemaphore(value: 0)
        let done = expectation(description: "done")
        var posts = 0
        let observer = NotificationCenter.default.addObserver(forName: .taskQueueChanged, object: queue, queue: nil) { _ in posts += 1 }
        queue.enqueue(entry("first"), change: .remove([file]), work: { _ in
            gate.wait()
            return OperationResult()
        }, completion: { _ in })
        queue.enqueue(entry("second"), work: { _ in OperationResult() }, completion: { _ in done.fulfill() })
        XCTAssertTrue(queue.isBusy)
        XCTAssertEqual(queue.active.map(\.title), ["Moving first from tmp to the Trash", "Moving second from tmp to the Trash"])
        XCTAssertEqual(queue.summary, "Moving first from tmp to the Trash (+1 more)")
        XCTAssertEqual(history.recent.map(\.state), [.running, .running])
        XCTAssertEqual(changes.snapshot.changes(in: directory.path).removed, ["a.txt"])
        gate.signal()
        wait(for: [done], timeout: 5)
        XCTAssertFalse(queue.isBusy)
        XCTAssertTrue(changes.snapshot.isEmpty)
        XCTAssertEqual(history.recent.map(\.state), [.finished, .finished])
        XCTAssertGreaterThanOrEqual(posts, 6)
        NotificationCenter.default.removeObserver(observer)
    }

    func testTrimsTheLogToFinishedTasks() {
        let queue = TaskQueue(changes: PendingChanges())
        for index in 0..<(TaskQueue.logLimit + 2) {
            _ = run(queue, entry("\(index)")) { _ in OperationResult() }
        }
        XCTAssertEqual(queue.tasks.count, TaskQueue.logLimit)
        XCTAssertEqual(queue.tasks.first?.entry.name, "2")
        XCTAssertEqual(queue.history.entries.count, TaskQueue.logLimit + 2)
    }
}
