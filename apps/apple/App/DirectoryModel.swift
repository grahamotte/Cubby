import Foundation

@MainActor
final class DirectoryModel {
    enum Change {
        case loaded
        case refreshed
        case children(FileItem)
    }

    let path: String
    private(set) var allItems: [FileItem] = []
    private(set) var items: [FileItem] = []
    private(set) var isLoaded = false
    private(set) var error: DirectoryReader.ReadError?
    var sort: SortKey
    var ascending: Bool
    var visibility: Visibility
    var query = ""
    let seed = FileSorter.daySeed()
    var onChange: ((Change) -> Void)?

    private var generation = 0
    private var watcher: PathWatcher?
    private var childWatchers: [String: PathWatcher] = [:]
    private var expanded: [String: FileItem] = [:]
    private var lastLoadDuration: TimeInterval = 0
    private var reloadScheduled = false
    private var countSortScheduled = false
    private var loading = false
    private(set) var counter: FolderCounter?
    private var stopped = false
    private let changes: PendingChanges
    private var pending: PendingSnapshot
    private var changesObserver: NSObjectProtocol?
    private static let queue = DispatchQueue(label: "cubby.directory", qos: .userInitiated, attributes: .concurrent)

    init(path: String, view: FolderView, visibility: Visibility, changes: PendingChanges? = nil) {
        self.path = path
        sort = view.sort
        ascending = view.ascending
        self.visibility = visibility
        self.changes = changes ?? .shared
        pending = self.changes.snapshot
    }

    func start() {
        changesObserver = NotificationCenter.default.addObserver(forName: .pendingChangesChanged, object: changes, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pendingChanged() }
        }
        load(change: .loaded)
    }

    func stop() {
        generation += 1
        stopped = true
        if let changesObserver { NotificationCenter.default.removeObserver(changesObserver) }
        changesObserver = nil
        counter = nil
        watcher = nil
        childWatchers = [:]
    }

    func reload() {
        load(change: .refreshed)
        expanded.values.forEach(loadChildren)
    }

    func applyPresentation() {
        generation += 1
        loading = false
        let token = generation
        let all = allItems
        let expandedItems = Array(expanded.values)
        let counts = countSnapshot(allItems + expandedItems.flatMap { $0.children ?? [] })
        let path = path, sort = sort, ascending = ascending, visibility = visibility, query = query, seed = seed, pending = pending
        Self.queue.async {
            let visible = FileSorter.sorted(FileSorter.filtered(pending.applied(to: all, in: path), visibility: visibility, query: query), by: sort, ascending: ascending, seed: seed, counts: counts)
            let children = expandedItems.map { item in (item, item.children.map { FileSorter.sorted(FileSorter.filtered(pending.applied(to: $0, in: item.path), visibility: visibility, query: ""), by: sort, ascending: ascending, seed: seed, counts: counts) }) }
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                for (item, sorted) in children {
                    item.children = sorted
                }
                self.items = visible
                self.onChange?(.refreshed)
            }
        }
    }

    func children(of item: FileItem) -> [FileItem]? {
        item.children
    }

    func expand(_ item: FileItem) {
        expanded[item.path] = item
        if item.children == nil || childWatchers[item.path] == nil {
            loadChildren(of: item)
        }
    }

    func collapse(_ item: FileItem) {
        expanded[item.path] = nil
        childWatchers[item.path] = nil
    }

    private func loadChildren(of item: FileItem) {
        let sort = sort, ascending = ascending, visibility = visibility, seed = seed, counts = knownCounts, pending = pending
        let path = item.path
        Self.queue.async {
            let read = (try? DirectoryReader.read(path)) ?? []
            let visible = FileSorter.sorted(FileSorter.filtered(pending.applied(to: read, in: path), visibility: visibility, query: ""), by: sort, ascending: ascending, seed: seed, counts: counts)
            DispatchQueue.main.async {
                guard !self.stopped, self.expanded[path] === item else { return }
                item.children = DirectoryListing.reconcile(old: item.children ?? [], new: read, visible: visible).visible
                self.requestCounts(item.children ?? [])
                if self.childWatchers[path] == nil {
                    self.childWatchers[path] = PathWatcher(path: path) { [weak self] in
                        guard let self, let item = self.expanded[path] else { return }
                        self.loadChildren(of: item)
                    }
                }
                self.onChange?(.children(item))
            }
        }
    }

    private var knownCounts: [String: Int] {
        guard sort == .count else { return [:] }
        counter?.visibility = visibility
        return counter?.knownCounts ?? [:]
    }

    private func countSnapshot(_ items: [FileItem]) -> [String: Int] {
        requestCounts(items)
        return knownCounts
    }

    private func requestCounts(_ items: [FileItem]) {
        guard sort == .count, !stopped else { return }
        let counter = counter ?? FolderCounter(root: path, visibility: visibility)
        if self.counter == nil {
            counter.onChange = { [weak self] in self?.scheduleCountSort() }
            self.counter = counter
        }
        counter.visibility = visibility
        for item in items where item.isFolder {
            _ = counter.count(for: item.path)
        }
    }

    private func scheduleCountSort() {
        guard sort == .count, !countSortScheduled else { return }
        countSortScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + min(max(lastLoadDuration * 3, 0.2), 2)) { [weak self] in
            guard let self else { return }
            self.countSortScheduled = false
            guard self.sort == .count, !self.stopped else { return }
            if self.loading {
                self.scheduleCountSort()
            } else {
                self.applyPresentation()
            }
        }
    }

    private func scheduleReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        let delay = min(max(lastLoadDuration * 3, 0), 3)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.reloadScheduled = false
            self.load(change: .refreshed)
        }
    }

    private func load(change: Change) {
        generation += 1
        let token = generation
        let path = path, sort = sort, ascending = ascending, visibility = visibility, query = query, seed = seed, counts = knownCounts, pending = pending
        let started = Date()
        loading = true
        Self.queue.async { [weak self] in
            let result: Result<[FileItem], DirectoryReader.ReadError>
            do {
                let read = try DirectoryReader.read(path)
                result = .success(read)
            } catch let error as DirectoryReader.ReadError {
                result = .failure(error)
            } catch {
                result = .failure(DirectoryReader.ReadError(path: path, code: EIO))
            }
            let visible = (try? result.get()).map { FileSorter.sorted(FileSorter.filtered(pending.applied(to: $0, in: path), visibility: visibility, query: query), by: sort, ascending: ascending, seed: seed, counts: counts) } ?? []
            DispatchQueue.main.async {
                guard let self, token == self.generation, !self.stopped else { return }
                self.loading = false
                self.lastLoadDuration = Date().timeIntervalSince(started)
                switch result {
                case .success(let read):
                    let reconciled = DirectoryListing.reconcile(old: self.allItems, new: read, visible: visible)
                    self.allItems = reconciled.all
                    self.items = reconciled.visible
                    self.requestCounts(reconciled.visible)
                    self.error = nil
                    if self.watcher == nil {
                        self.watcher = PathWatcher(path: path) { [weak self] in self?.scheduleReload() }
                    }
                case .failure(let error):
                    self.allItems = []
                    self.items = []
                    self.error = error
                }
                self.isLoaded = true
                self.onChange?(change)
                if self.pending != pending {
                    self.applyPresentation()
                }
            }
        }
    }

    private func pendingChanged() {
        let previous = pending
        pending = changes.snapshot
        let changed = ([path] + expanded.keys).map { (previous.changes(in: $0), pending.changes(in: $0)) }.filter { $0 != $1 }
        guard !changed.isEmpty, !stopped else { return }
        if changed.allSatisfy({ $0.isSubset(of: $1) }) {
            if !loading { applyPresentation() }
        } else {
            reload()
        }
    }
}
