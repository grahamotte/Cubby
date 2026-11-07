import AppKit

@MainActor
enum FileActions {
    static func transfer(_ urls: [URL], to directory: URL, copy: Bool, completion: (([URL]) -> Void)? = nil) {
        guard !urls.isEmpty else { return }
        run(HistoryEntry(copy ? .copy : .move, items: urls, destination: directory), change: copy ? .copy(urls, to: directory) : .move(urls, to: directory)) { operations in
            var applyToAll: ConflictChoice?
            let resolve: (URL) -> ConflictChoice = { destination in
                if let applyToAll { return applyToAll }
                return DispatchQueue.main.sync {
                    let (choice, all) = askConflict(destination)
                    if all { applyToAll = choice }
                    return choice
                }
            }
            return copy ? operations.copy(urls, to: directory, resolve: resolve) : operations.move(urls, to: directory, resolve: resolve)
        } completion: { result in
            if !copy {
                for transfer in result.transfers {
                    AppState.shared.folderMoved(from: transfer.source.standardizedFileURL.path, to: transfer.destination.standardizedFileURL.path)
                }
            }
            completion?(result.transfers.map(\.destination))
        }
    }

    static func trash(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        run(HistoryEntry(.trash, items: urls), change: .remove(urls)) { $0.trash(urls) } completion: { _ in }
    }

    static func rename(_ url: URL, to name: String) -> URL? {
        do {
            let renamed = try FileOperations().rename(url, to: name)
            guard renamed != url else { return url }
            var entry = HistoryEntry(.rename, items: [url], target: renamed.lastPathComponent, state: .finished)
            entry.record(inputs: [url], outputs: [renamed])
            TaskQueue.shared.record(entry)
            AppState.shared.folderMoved(from: url.standardizedFileURL.path, to: renamed.standardizedFileURL.path)
            return renamed
        } catch {
            var entry = HistoryEntry(.rename, items: [url], target: name, state: .failed)
            entry.record(inputs: [], outputs: [])
            TaskQueue.shared.record(entry)
            present(error)
            return nil
        }
    }

    static func duplicate(_ urls: [URL], completion: (([URL]) -> Void)? = nil) {
        guard !urls.isEmpty else { return }
        run(HistoryEntry(.duplicate, items: urls)) { $0.duplicate(urls) } completion: { result in
            completion?(result.transfers.map(\.destination))
        }
    }

    static func newFolder(in directory: URL) -> URL? {
        create(.newFolder) { try FileOperations().makeFolder(in: directory) }
    }

    static func newFile(in directory: URL) -> URL? {
        create(.newFile) { try FileOperations().makeFile(in: directory) }
    }

    static func newFolder(with urls: [URL], in directory: URL, completion: @escaping (URL) -> Void) {
        guard let folder = try? FileOperations().makeFolder(in: directory, name: "New Folder With Items") else { return }
        run(HistoryEntry(.newFolderWithItems, items: urls, destination: folder, target: folder.lastPathComponent), change: .move(urls, to: folder)) { $0.move(urls, to: folder) { _ in .keepBoth } } completion: { _ in
            completion(folder)
        }
    }

    static func compress(_ urls: [URL], completion: @escaping (URL) -> Void) {
        guard let archive = Archive.plan(for: urls), let first = urls.first else { return }
        run(HistoryEntry(.compress, items: urls, destination: archive.destination.deletingLastPathComponent(), target: archive.destination.lastPathComponent)) { _ in
            let process = Process()
            process.executableURL = archive.executable
            process.arguments = archive.arguments
            if let directory = archive.directory {
                process.currentDirectoryURL = directory
            }
            var result = OperationResult()
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    result.transfers = [Transfer(source: first, destination: archive.destination)]
                } else {
                    result.errors = [OperationError(message: "Compressing failed (exit \(process.terminationStatus)).")]
                }
            } catch {
                result.errors = [error]
            }
            return result
        } completion: { result in
            guard let transfer = result.transfers.first else { return }
            completion(transfer.destination)
        }
    }

    static func undo(_ entry: HistoryEntry) {
        guard TaskQueue.shared.history.undoable.contains(entry.id) else { return }
        if let error = entry.undoPreflight() {
            present(error)
            return
        }
        run(entry.undoEntry, change: entry.undoChange) { entry.undo(with: $0) } completion: { result in
            guard entry.movesBack, entry.kind != .trash else { return }
            for transfer in result.transfers {
                AppState.shared.folderMoved(from: transfer.source.standardizedFileURL.path, to: transfer.destination.standardizedFileURL.path)
            }
        }
    }

    static func undoLatest() {
        guard let entry = TaskQueue.shared.history.nextUndo else { return }
        undo(entry)
    }

    static func openInTerminal(_ directory: URL) {
        let name = AppState.shared.config.terminal
        let configuration = NSWorkspace.OpenConfiguration()
        let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name)
            ?? applicationURL(named: name)
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        guard let application else { return }
        NSWorkspace.shared.open([directory], withApplicationAt: application, configuration: configuration) { _, error in
            if let error {
                DispatchQueue.main.async { present(error) }
            }
        }
    }

    static func copyPaths(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    static func writeToPasteboard(_ urls: [URL], cut: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        AppState.shared.cutURLs = cut ? urls : []
        AppState.shared.cutChangeCount = cut ? pasteboard.changeCount : -1
    }

    static func pasteboardURLs() -> [URL] {
        (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    static func paste(into directory: URL, forceMove: Bool, completion: (([URL]) -> Void)? = nil) {
        let urls = pasteboardURLs()
        guard !urls.isEmpty else { return }
        let state = AppState.shared
        let isCut = state.cutChangeCount == NSPasteboard.general.changeCount && state.cutURLs == urls
        if isCut {
            state.cutURLs = []
            state.cutChangeCount = -1
        }
        transfer(urls, to: directory, copy: !(isCut || forceMove), completion: completion)
    }

    static func present(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.alertStyle = .warning
        alert.runModal()
    }

    private static func applicationURL(named name: String) -> URL? {
        let candidates = ["/Applications/\(name).app", "/System/Applications/Utilities/\(name).app", "/System/Applications/\(name).app", NSHomeDirectory() + "/Applications/\(name).app"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }.map { URL(filePath: $0) }
    }

    private static func create(_ kind: HistoryEntry.Kind, _ make: () throws -> URL) -> URL? {
        do {
            let url = try make()
            var entry = HistoryEntry(kind, items: [url], state: .finished)
            entry.record(inputs: [], outputs: [url])
            TaskQueue.shared.record(entry)
            return url
        } catch {
            present(error)
            return nil
        }
    }

    private static func askConflict(_ destination: URL) -> (ConflictChoice, Bool) {
        let alert = NSAlert()
        alert.messageText = "An item named “\(destination.lastPathComponent)” already exists in this location."
        alert.informativeText = "Do you want to replace it with the one you're moving or copying?"
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Stop")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Apply to all"
        let response = alert.runModal()
        let all = alert.suppressionButton?.state == .on
        switch response {
        case .alertFirstButtonReturn: return (.keepBoth, all)
        case .alertSecondButtonReturn: return (.replace, all)
        case .alertThirdButtonReturn: return (.skip, all)
        default: return (.stop, false)
        }
    }

    private static func run(_ entry: HistoryEntry, change: PendingChange = PendingChange(), work: @escaping (FileOperations) -> OperationResult, completion: @escaping (OperationResult) -> Void) {
        TaskQueue.shared.enqueue(entry, change: change, work: work) { result in
            completion(result)
            if let summary = result.errorSummary {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = summary.message
                alert.informativeText = summary.details
                alert.runModal()
            } else if let error = result.errors.first {
                present(error)
            }
        }
    }
}
