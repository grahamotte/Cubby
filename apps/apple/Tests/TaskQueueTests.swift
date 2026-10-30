import XCTest
@testable import CubbyCore

@MainActor
final class TaskQueueTests: XCTestCase {
    private func run(_ queue: TaskQueue, _ title: String, change: PendingChange = PendingChange(), work: @escaping (FileOperations) -> OperationResult) -> OperationResult {
        let done = expectation(description: title)
        var output = OperationResult()
        queue.enqueue(title, change: change, work: work) { result in
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
        let queue = TaskQueue(changes: changes)

        let result = run(queue, "Moving 1 item…", change: .move([file], to: destination)) { operations in
            operations.move([file], to: destination) { _ in .stop }
        }
        XCTAssertEqual(result.transfers, [Transfer(source: file, destination: destination.appending(path: "a.txt"))])
        XCTAssertTrue(changes.snapshot.isEmpty)
        XCTAssertFalse(queue.isBusy)
        XCTAssertNil(queue.summary)
        let task = queue.tasks[0]
        XCTAssertEqual(task.title, "Moving 1 item…")
        XCTAssertEqual(task.state, .finished)
        XCTAssertEqual(task.transfers, result.transfers)
        XCTAssertNotNil(task.started)
        XCTAssertNotNil(task.finished)

        _ = run(queue, "Failing…") { _ in OperationResult(errors: [OperationError(message: "Nope")]) }
        _ = run(queue, "Stopping…") { _ in OperationResult(stopped: true) }
        XCTAssertEqual(queue.tasks.map(\.state), [.finished, .failed, .stopped])
        XCTAssertEqual(queue.tasks[1].errors, ["Nope"])
        XCTAssertEqual(Set(queue.tasks.map(\.id)).count, 3)
    }

    func testAppliesPendingChangesWhileQueued() {
        let directory = makeTemporaryDirectory()
        let file = makeFile(directory, "a.txt")
        let changes = PendingChanges()
        let queue = TaskQueue(changes: changes)
        let gate = DispatchSemaphore(value: 0)
        let done = expectation(description: "done")
        var posts = 0
        let observer = NotificationCenter.default.addObserver(forName: .taskQueueChanged, object: queue, queue: nil) { _ in posts += 1 }
        queue.enqueue("First…", change: .remove([file]), work: { _ in
            gate.wait()
            return OperationResult()
        }, completion: { _ in })
        queue.enqueue("Second…", work: { _ in OperationResult() }, completion: { _ in done.fulfill() })
        XCTAssertTrue(queue.isBusy)
        XCTAssertEqual(queue.active.map(\.title), ["First…", "Second…"])
        XCTAssertEqual(queue.summary, "First… (+1 more)")
        XCTAssertEqual(changes.snapshot.changes(in: directory.path).removed, ["a.txt"])
        gate.signal()
        wait(for: [done], timeout: 5)
        XCTAssertFalse(queue.isBusy)
        XCTAssertTrue(changes.snapshot.isEmpty)
        XCTAssertGreaterThanOrEqual(posts, 6)
        NotificationCenter.default.removeObserver(observer)
    }

    func testTrimsTheLogToFinishedTasks() {
        let queue = TaskQueue(changes: PendingChanges())
        for index in 0..<(TaskQueue.logLimit + 2) {
            _ = run(queue, "Task \(index)") { _ in OperationResult() }
        }
        XCTAssertEqual(queue.tasks.count, TaskQueue.logLimit)
        XCTAssertEqual(queue.tasks.first?.title, "Task 2")
    }
}
