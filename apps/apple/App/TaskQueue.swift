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
    var entry: HistoryEntry
    let queued: Date
    var state = State.queued
    var started: Date?
    var finished: Date?
    var transfers: [Transfer] = []
    var replaced: [Transfer] = []
    var errors: [String] = []

    var title: String { entry.summary }
    var isActive: Bool { state == .queued || state == .running }
}

@MainActor
final class TaskQueue {
    static let shared = TaskQueue(history: FileHistory(url: CubbyPaths.standard.historyFile))
    static let logLimit = 500

    private(set) var tasks: [FileTask] = []
    let history: FileHistory
    private let changes: PendingChanges
    private let queue = DispatchQueue(label: "cubby.file-operations", qos: .userInitiated)
    private var nextID = 1

    init(changes: PendingChanges? = nil, history: FileHistory? = nil) {
        self.changes = changes ?? .shared
        self.history = history ?? FileHistory(url: nil)
    }

    var active: [FileTask] { tasks.filter(\.isActive) }

    var isBusy: Bool { tasks.contains(where: \.isActive) }

    var summary: String? {
        let active = active
        guard let first = active.first else { return nil }
        return active.count > 1 ? "\(first.title) (+\(active.count - 1) more)" : first.title
    }

    @discardableResult
    func enqueue(_ entry: HistoryEntry, change: PendingChange = PendingChange(), work: @escaping (FileOperations) -> OperationResult, completion: @escaping (OperationResult) -> Void) -> Int {
        let id = nextID
        nextID += 1
        tasks.append(FileTask(id: id, entry: entry, queued: Date()))
        trim()
        history.record(entry)
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
                    task.entry.state = task.state == .failed ? .failed : task.state == .stopped ? .stopped : .finished
                    task.entry.finished = task.finished
                    task.entry.errors = task.errors.count
                    task.entry.record(result)
                }
                if let original = entry.undoes, result.errors.isEmpty, !result.stopped {
                    self.history.update(original) { $0.undoneBy = entry.id }
                    self.notify()
                }
                completion(result)
            }
        }
        return id
    }

    func record(_ entry: HistoryEntry) {
        history.record(entry)
        notify()
    }

    private func update(_ id: Int, _ change: (inout FileTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&tasks[index])
        let entry = tasks[index].entry
        history.update(entry.id) { $0 = entry }
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
