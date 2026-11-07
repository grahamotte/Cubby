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
        case .finished: return "Finished"
        case .stopped: return "Stopped"
        case .failed: return errors > 1 ? "Failed with \(errors.formatted()) errors" : "Failed"
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
