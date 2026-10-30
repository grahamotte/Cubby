import Foundation

extension Notification.Name {
    static let taskQueueChanged = Notification.Name("CubbyTaskQueueChanged")
}

struct FileTask: Identifiable {
    enum State {
        case queued
        case running
        case finished
        case stopped
        case failed
    }

    let id: Int
    let title: String
    let queued: Date
    var state = State.queued
    var started: Date?
    var finished: Date?
    var transfers: [Transfer] = []
    var replaced: [Transfer] = []
    var errors: [String] = []

    var isActive: Bool { state == .queued || state == .running }
}

@MainActor
final class TaskQueue {
    static let shared = TaskQueue()
    static let logLimit = 500

    private(set) var tasks: [FileTask] = []
    private let changes: PendingChanges
    private let queue = DispatchQueue(label: "cubby.file-operations", qos: .userInitiated)
    private var nextID = 1

    init(changes: PendingChanges? = nil) {
        self.changes = changes ?? .shared
    }

    var active: [FileTask] { tasks.filter(\.isActive) }

    var isBusy: Bool { tasks.contains(where: \.isActive) }

    var summary: String? {
        let active = active
        guard let first = active.first else { return nil }
        return active.count > 1 ? "\(first.title) (+\(active.count - 1) more)" : first.title
    }

    @discardableResult
    func enqueue(_ title: String, change: PendingChange = PendingChange(), work: @escaping (FileOperations) -> OperationResult, completion: @escaping (OperationResult) -> Void) -> Int {
        let id = nextID
        nextID += 1
        tasks.append(FileTask(id: id, title: title, queued: Date()))
        trim()
        let token = changes.begin(change)
        notify()
        queue.async {
            DispatchQueue.main.async {
                self.update(id) { task in
                    task.state = .running
                    task.started = Date()
                }
            }
            let result = work(FileOperations())
            DispatchQueue.main.async {
                self.changes.end(token)
                self.update(id) { task in
                    task.state = !result.errors.isEmpty ? .failed : result.stopped ? .stopped : .finished
                    task.finished = Date()
                    task.transfers = result.transfers
                    task.replaced = result.replaced
                    task.errors = result.errors.map(\.localizedDescription)
                }
                completion(result)
            }
        }
        return id
    }

    private func update(_ id: Int, _ change: (inout FileTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&tasks[index])
        notify()
    }

    private func trim() {
        while tasks.count > Self.logLimit, let index = tasks.firstIndex(where: { !$0.isActive }) {
            tasks.remove(at: index)
        }
    }

    private func notify() {
        NotificationCenter.default.post(name: .taskQueueChanged, object: self)
    }
}
