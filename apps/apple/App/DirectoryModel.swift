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
    var onChange: ((Change) -> Void)?

    private var generation = 0
    private var watcher: PathWatcher?
    private var childWatchers: [String: PathWatcher] = [:]
    private var expanded: [String: FileItem] = [:]
    private var lastLoadDuration: TimeInterval = 0
    private var reloadScheduled = false
    private var stopped = false
    private static let queue = DispatchQueue(label: "cubby.directory", qos: .userInitiated, attributes: .concurrent)

    init(path: String, view: FolderView, visibility: Visibility) {
        self.path = path
        sort = view.sort
        ascending = view.ascending
        self.visibility = visibility
    }

    func start() {
        load(change: .loaded)
    }

    func stop() {
        generation += 1
        stopped = true
        watcher = nil
        childWatchers = [:]
    }

    func reload() {
        load(change: .refreshed)
        expanded.values.forEach(loadChildren)
    }

    func applyPresentation() {
        generation += 1
        let token = generation
        let all = allItems
        let sort = sort, ascending = ascending, visibility = visibility, query = query
        let expandedItems = Array(expanded.values)
        Self.queue.async {
            let visible = FileSorter.sorted(FileSorter.filtered(all, visibility: visibility, query: query), by: sort, ascending: ascending)
            let children = expandedItems.map { ($0, $0.children.map { FileSorter.sorted(FileSorter.filtered($0, visibility: visibility, query: ""), by: sort, ascending: ascending) }) }
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
        let sort = sort, ascending = ascending, visibility = visibility
        let path = item.path
        Self.queue.async {
            let read = (try? DirectoryReader.read(path)) ?? []
            let visible = FileSorter.sorted(FileSorter.filtered(read, visibility: visibility, query: ""), by: sort, ascending: ascending)
            DispatchQueue.main.async {
                guard !self.stopped, self.expanded[path] === item else { return }
                item.children = DirectoryListing.reconcile(old: item.children ?? [], new: read, visible: visible).visible
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
        let path = path, sort = sort, ascending = ascending, visibility = visibility, query = query
        let started = Date()
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
            let visible = (try? result.get()).map { FileSorter.sorted(FileSorter.filtered($0, visibility: visibility, query: query), by: sort, ascending: ascending) } ?? []
            DispatchQueue.main.async {
                guard let self, token == self.generation, !self.stopped else { return }
                self.lastLoadDuration = Date().timeIntervalSince(started)
                switch result {
                case .success(let read):
                    let reconciled = DirectoryListing.reconcile(old: self.allItems, new: read, visible: visible)
                    self.allItems = reconciled.all
                    self.items = reconciled.visible
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
            }
        }
    }
}
