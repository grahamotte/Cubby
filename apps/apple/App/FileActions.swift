import AppKit

extension Notification.Name {
    static let activityChanged = Notification.Name("CubbyActivityChanged")
}

@MainActor
enum FileActions {
    private(set) static var activities: [String] = []
    private static let queue = DispatchQueue(label: "cubby.file-operations", qos: .userInitiated)
    private static var undoManager: UndoManager { AppState.shared.undoManager }

    static var activityText: String? {
        guard let first = activities.first else { return nil }
        return activities.count > 1 ? "\(first) (+\(activities.count - 1) more)" : first
    }

    static func transfer(_ urls: [URL], to directory: URL, copy: Bool, completion: (([URL]) -> Void)? = nil) {
        guard !urls.isEmpty else { return }
        let title = "\(copy ? "Copying" : "Moving") \(itemCount(urls.count))…"
        run(title) { operations in
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
            registerUndo(result.transfers, replaced: result.replaced, copy: copy)
            completion?(result.transfers.map(\.destination))
        }
    }

    static func trash(_ urls: [URL], undoable: Bool = true) {
        guard !urls.isEmpty else { return }
        run("Moving \(itemCount(urls.count)) to the Trash…") { $0.trash(urls) } completion: { result in
            guard undoable, !result.transfers.isEmpty else { return }
            let transfers = result.transfers
            registerUndo("Move to Trash") {
                run("Putting Back \(itemCount(transfers.count))…") { $0.moveBack(transfers) } completion: { _ in }
            }
        }
    }

    static func rename(_ url: URL, to name: String, undoable: Bool = true) -> URL? {
        do {
            let renamed = try FileOperations().rename(url, to: name)
            guard renamed != url else { return url }
            AppState.shared.folderMoved(from: url.standardizedFileURL.path, to: renamed.standardizedFileURL.path)
            if undoable {
                registerUndo("Rename") {
                    _ = rename(renamed, to: url.lastPathComponent, undoable: false)
                }
            }
            return renamed
        } catch {
            present(error)
            return nil
        }
    }

    static func duplicate(_ urls: [URL], completion: (([URL]) -> Void)? = nil) {
        guard !urls.isEmpty else { return }
        run("Duplicating \(itemCount(urls.count))…") { $0.duplicate(urls) } completion: { result in
            registerUndo(result.transfers, copy: true)
            completion?(result.transfers.map(\.destination))
        }
    }

    static func newFolder(in directory: URL) -> URL? {
        create { try FileOperations().makeFolder(in: directory) }
    }

    static func newFile(in directory: URL) -> URL? {
        create { try FileOperations().makeFile(in: directory) }
    }

    static func newFolder(with urls: [URL], in directory: URL, completion: @escaping (URL) -> Void) {
        guard let folder = try? FileOperations().makeFolder(in: directory, name: "New Folder With Items") else { return }
        run("Moving \(itemCount(urls.count))…") { $0.move(urls, to: folder) { _ in .keepBoth } } completion: { result in
            let transfers = result.transfers
            registerUndo("New Folder With Selection") {
                run("Moving \(itemCount(transfers.count)) Back…") { operations in
                    var result = operations.moveBack(transfers)
                    if (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
                        do { try FileManager.default.removeItem(at: folder) } catch { result.errors.append(error) }
                    }
                    return result
                } completion: { _ in }
            }
            completion(folder)
        }
    }

    static func compress(_ urls: [URL], completion: @escaping (URL) -> Void) {
        guard let archive = Archive.plan(for: urls), let first = urls.first else { return }
        run("Compressing \(itemCount(urls.count))…") { _ in
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
            registerUndo([transfer], copy: true)
            completion(transfer.destination)
        }
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

    static func itemCount(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count.formatted()) items"
    }

    private static func applicationURL(named name: String) -> URL? {
        let candidates = ["/Applications/\(name).app", "/System/Applications/Utilities/\(name).app", "/System/Applications/\(name).app", NSHomeDirectory() + "/Applications/\(name).app"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }.map { URL(filePath: $0) }
    }

    private static func create(_ make: () throws -> URL) -> URL? {
        do {
            let url = try make()
            registerUndo(url.hasDirectoryPath ? "New Folder" : "New File") { trash([url], undoable: false) }
            return url
        } catch {
            present(error)
            return nil
        }
    }

    private static func registerUndo(_ transfers: [Transfer], replaced: [Transfer] = [], copy: Bool) {
        guard !transfers.isEmpty else { return }
        registerUndo(copy ? "Copy" : "Move") {
            if copy {
                run("Moving \(itemCount(transfers.count)) to the Trash…") { operations in
                    var result = operations.trash(transfers.map(\.destination))
                    result.errors += operations.moveBack(replaced).errors
                    return result
                } completion: { _ in }
            } else {
                run("Moving \(itemCount(transfers.count)) Back…") { operations in
                    var result = operations.moveBack(transfers)
                    result.errors += operations.moveBack(replaced).errors
                    return result
                } completion: { result in
                    for transfer in result.transfers {
                        AppState.shared.folderMoved(from: transfer.source.standardizedFileURL.path, to: transfer.destination.standardizedFileURL.path)
                    }
                }
            }
        }
    }

    private static func registerUndo(_ name: String, _ handler: @escaping () -> Void) {
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: AppState.shared) { _ in handler() }
        undoManager.setActionName(name)
        undoManager.endUndoGrouping()
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

    private static func run(_ title: String, work: @escaping (FileOperations) -> OperationResult, completion: @escaping (OperationResult) -> Void) {
        activities.append(title)
        NotificationCenter.default.post(name: .activityChanged, object: nil)
        queue.async {
            let result = work(FileOperations())
            DispatchQueue.main.async {
                if let index = activities.firstIndex(of: title) { activities.remove(at: index) }
                NotificationCenter.default.post(name: .activityChanged, object: nil)
                completion(result)
                if let error = result.errors.first {
                    present(error)
                }
            }
        }
    }
}
