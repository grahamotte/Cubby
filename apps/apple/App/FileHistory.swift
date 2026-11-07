import Foundation

struct HistoryEntry: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case move
        case copy
        case trash
        case putBack
        case moveBack
        case duplicate
        case rename
        case newFolder
        case newFile
        case newFolderWithItems
        case compress
    }

    enum State: String, Codable {
        case running
        case finished
        case stopped
        case failed
    }

    struct Replacement: Codable, Equatable {
        var path: String
        var trashed: String
    }

    static let pathLimit = 1000

    var id: UUID
    var kind: Kind
    var count: Int
    var name: String?
    var target: String?
    var source: String?
    var destination: String?
    var state: State
    var started: Date
    var finished: Date?
    var errors: Int
    var inputs: [String]?
    var outputs: [String]?
    var replaced: [Replacement]?
    var undoes: UUID?
    var undoneBy: UUID?

    init(_ kind: Kind, items: [URL], destination: URL? = nil, target: String? = nil, state: State = .running, date: Date = Date()) {
        id = UUID()
        self.kind = kind
        count = items.count
        name = items.count == 1 ? items[0].lastPathComponent : nil
        source = HistoryEntry.folder(of: items)?.path
        self.destination = destination?.standardizedFileURL.path
        self.target = target
        self.state = state
        started = date
        finished = state == .running ? nil : date
        errors = state == .failed ? 1 : 0
    }

    static func folder(of urls: [URL]) -> URL? {
        let parents = Set(urls.map { $0.standardizedFileURL.deletingLastPathComponent().path })
        guard parents.count == 1, let parent = parents.first else { return nil }
        return URL(filePath: parent, directoryHint: .isDirectory)
    }

    var createsOutputs: Bool {
        switch kind {
        case .copy, .duplicate, .newFolder, .newFile, .compress: return true
        case .move, .trash, .putBack, .moveBack, .rename, .newFolderWithItems: return false
        }
    }

    var paths: [String]? {
        guard let inputs, let outputs else { return nil }
        return inputs + outputs + (replaced ?? []).map(\.trashed)
    }

    var undoActionName: String {
        switch kind {
        case .move: return "Move"
        case .copy: return "Copy"
        case .trash: return "Move to Trash"
        case .putBack: return "Put Back"
        case .moveBack: return "Move Back"
        case .duplicate: return "Duplicate"
        case .rename: return "Rename"
        case .newFolder: return "New Folder"
        case .newFile: return "New File"
        case .newFolderWithItems: return "New Folder With Selection"
        case .compress: return "Compress"
        }
    }

    mutating func record(_ result: OperationResult) {
        record(inputs: createsOutputs ? [] : result.transfers.map(\.source), outputs: result.transfers.map(\.destination), replaced: result.replaced)
    }

    mutating func record(inputs: [URL], outputs: [URL], replaced: [Transfer] = []) {
        guard outputs.count + replaced.count <= HistoryEntry.pathLimit else {
            self.inputs = nil
            self.outputs = nil
            self.replaced = nil
            return
        }
        self.inputs = inputs.map(\.standardizedFileURL.path)
        self.outputs = outputs.map(\.standardizedFileURL.path)
        self.replaced = replaced.isEmpty ? nil : replaced.map { Replacement(path: $0.source.standardizedFileURL.path, trashed: $0.destination.standardizedFileURL.path) }
    }

    var summary: String {
        let subject = name ?? "\(count.formatted()) items"
        let from = source.map { " from \(HistoryEntry.displayName($0))" } ?? ""
        let into = source.map { " in \(HistoryEntry.displayName($0))" } ?? ""
        let to = destination.map { " to \(HistoryEntry.displayName($0))" } ?? ""
        let target = target ?? ""
        switch kind {
        case .move: return "\(verb("Moved", "Moving")) \(subject)\(from)\(to)"
        case .copy: return "\(verb("Copied", "Copying")) \(subject)\(from)\(to)"
        case .trash: return "\(verb("Moved", "Moving")) \(subject)\(from) to the Trash"
        case .putBack: return "\(verb("Put", "Putting")) back \(subject)\(to)"
        case .moveBack: return "\(verb("Moved", "Moving")) \(subject) back\(to)"
        case .duplicate: return "\(verb("Duplicated", "Duplicating")) \(subject)\(into)"
        case .rename: return "\(verb("Renamed", "Renaming")) \(subject) to \(target)"
        case .newFolder: return "\(verb("Created", "Creating")) folder \(subject)\(into)"
        case .newFile: return "\(verb("Created", "Creating")) file \(subject)\(into)"
        case .newFolderWithItems: return "\(verb("Moved", "Moving")) \(subject) into new folder \(target)"
        case .compress: return "\(verb("Compressed", "Compressing")) \(subject) into \(target)"
        }
    }

    var symbolName: String {
        switch kind {
        case .move: return "arrow.right"
        case .copy, .duplicate: return "plus.square.on.square"
        case .trash: return "trash"
        case .putBack, .moveBack: return "arrow.uturn.backward"
        case .rename: return "pencil"
        case .newFolder, .newFolderWithItems: return "folder.badge.plus"
        case .newFile: return "doc.badge.plus"
        case .compress: return "archivebox"
        }
    }

    var stateDescription: String {
        switch state {
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .failed: return errors > 1 ? "Failed with \(errors.formatted()) errors" : "Failed"
        case .finished where undoneBy != nil: return "Undone"
        case .finished: return "Finished"
        }
    }

    private func verb(_ past: String, _ present: String) -> String {
        state == .running ? present : past
    }

    private static func displayName(_ path: String) -> String {
        URL(filePath: path).lastPathComponent
    }
}

final class FileHistory {
    private struct File: Codable {
        var entries: [HistoryEntry]
    }

    static let retention: TimeInterval = 30 * 24 * 60 * 60
    static let undoWindow: TimeInterval = 24 * 60 * 60
    static let limit = 5000

    let url: URL?
    private(set) var entries: [HistoryEntry] = []
    private let now: () -> Date

    init(url: URL?, now: @escaping () -> Date = Date.init) {
        self.url = url
        self.now = now
        guard let url, let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) else { return }
        entries = file.entries.map { entry in
            var entry = entry
            if entry.state == .running { entry.state = .stopped }
            return entry
        }
        expire()
    }

    var recent: [HistoryEntry] {
        let cutoff = now().addingTimeInterval(-FileHistory.retention)
        let shown = entries.filter { $0.started >= cutoff }.reversed()
        return shown.filter { $0.state == .running } + shown.filter { $0.state != .running }
    }

    var undoable: Set<UUID> {
        let cutoff = now().addingTimeInterval(-FileHistory.undoWindow)
        var result: Set<UUID> = []
        var touched: Set<String> = []
        var ancestors: Set<String> = []
        for entry in entries.reversed() {
            guard entry.started >= cutoff, entry.state != .running, let paths = entry.paths else { break }
            if entry.undoes != nil || entry.undoneBy != nil { continue }
            let keys = paths.map { $0.lowercased() }
            let blocked = keys.contains { key in
                touched.contains(key) || ancestors.contains(key) || FileHistory.ancestors(of: key).contains { touched.contains($0) }
            }
            if !blocked && entry.state == .finished && entry.outputs?.isEmpty == false {
                result.insert(entry.id)
            }
            for key in keys {
                touched.insert(key)
                ancestors.formUnion(FileHistory.ancestors(of: key))
            }
        }
        return result
    }

    var nextUndo: HistoryEntry? {
        let undoable = undoable
        return entries.last { undoable.contains($0.id) }
    }

    func record(_ entry: HistoryEntry) {
        entries.append(entry)
        save()
    }

    func update(_ id: UUID, _ change: (inout HistoryEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let before = entries[index]
        change(&entries[index])
        guard entries[index] != before else { return }
        save()
    }

    func stopRunning() {
        guard entries.contains(where: { $0.state == .running }) else { return }
        for index in entries.indices where entries[index].state == .running {
            entries[index].state = .stopped
        }
        save()
    }

    private static func ancestors(of path: String) -> [String] {
        var result: [String] = []
        var current = (path as NSString).deletingLastPathComponent
        while current.count > 1 {
            result.append(current)
            current = (current as NSString).deletingLastPathComponent
        }
        return result
    }

    private func expire() {
        let cutoff = now().addingTimeInterval(-FileHistory.retention)
        entries.removeAll { $0.started < cutoff }
        if entries.count > FileHistory.limit {
            entries.removeFirst(entries.count - FileHistory.limit)
        }
    }

    private func save() {
        expire()
        guard let url, let data = try? JSONStore.encode(File(entries: entries)) else { return }
        try? JSONStore.write(data, to: url)
    }
}
