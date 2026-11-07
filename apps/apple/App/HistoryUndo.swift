import Foundation

extension HistoryEntry {
    var movesBack: Bool {
        switch kind {
        case .move, .trash, .rename, .newFolderWithItems: return true
        case .copy, .duplicate, .newFolder, .newFile, .compress, .putBack, .moveBack: return false
        }
    }

    var undoTransfers: [Transfer] {
        zip(inputs ?? [], outputs ?? []).map { Transfer(source: URL(filePath: $0), destination: URL(filePath: $1)) }
    }

    var undoReplaced: [Transfer] {
        (replaced ?? []).map { Transfer(source: URL(filePath: $0.path), destination: URL(filePath: $0.trashed)) }
    }

    var undoEntry: HistoryEntry {
        let outputURLs = (outputs ?? []).map { URL(filePath: $0) }
        var entry: HistoryEntry
        switch kind {
        case .trash:
            let sources = (inputs ?? []).map { URL(filePath: $0) }
            entry = HistoryEntry(.putBack, items: sources, destination: HistoryEntry.folder(of: sources))
        case .rename:
            entry = HistoryEntry(.rename, items: outputURLs, target: outputURLs.count == 1 ? inputs?.first.map { URL(filePath: $0).lastPathComponent } : nil)
        case .move, .newFolderWithItems:
            entry = HistoryEntry(.moveBack, items: outputURLs, destination: HistoryEntry.folder(of: (inputs ?? []).map { URL(filePath: $0) }))
        case .copy, .duplicate, .newFolder, .newFile, .compress, .putBack, .moveBack:
            entry = HistoryEntry(.trash, items: outputURLs)
        }
        entry.undoes = id
        return entry
    }

    var undoChange: PendingChange {
        movesBack ? .moveBack(undoTransfers) : .remove((outputs ?? []).map { URL(filePath: $0) })
    }

    func undoPreflight(fileManager: FileManager = .default) -> OperationError? {
        guard let inputs, let outputs else { return OperationError(message: "This operation can't be undone.") }
        let exists = { (path: String) in (try? fileManager.attributesOfItem(atPath: path)) != nil }
        if let missing = outputs.first(where: { !exists($0) }) {
            return OperationError(message: "“\(URL(filePath: missing).lastPathComponent)” is no longer where it was, so this can't be undone.")
        }
        if let missing = (replaced ?? []).first(where: { !exists($0.trashed) }) {
            return OperationError(message: "The replaced “\(URL(filePath: missing.path).lastPathComponent)” is no longer in the Trash, so this can't be undone.")
        }
        guard movesBack else { return nil }
        for (input, output) in zip(inputs, outputs) {
            let name = URL(filePath: input).lastPathComponent
            var isDirectory: ObjCBool = false
            let parent = (input as NSString).deletingLastPathComponent
            guard fileManager.fileExists(atPath: parent, isDirectory: &isDirectory), isDirectory.boolValue else {
                return OperationError(message: "The folder that held “\(name)” no longer exists, so this can't be undone.")
            }
            if input.lowercased() != output.lowercased() && exists(input) {
                return OperationError(message: "An item named “\(name)” already exists where it was, so this can't be undone.")
            }
        }
        return nil
    }

    func undo(with operations: FileOperations) -> OperationResult {
        guard movesBack else {
            var result = operations.trash((outputs ?? []).map { URL(filePath: $0) })
            result.errors += operations.moveBack(undoReplaced).errors
            return result
        }
        var result = operations.moveBack(undoTransfers)
        result.errors += operations.moveBack(undoReplaced).errors
        if kind == .newFolderWithItems, result.errors.isEmpty, let folder = destination, (try? operations.fileManager.contentsOfDirectory(atPath: folder))?.isEmpty == true {
            do { try operations.fileManager.removeItem(atPath: folder) } catch { result.errors.append(error) }
        }
        return result
    }
}
