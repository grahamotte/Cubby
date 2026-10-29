import Foundation

enum ConflictChoice {
    case replace
    case keepBoth
    case skip
    case stop
}

struct Transfer: Equatable {
    let source: URL
    let destination: URL
}

struct OperationResult {
    var transfers: [Transfer] = []
    var replaced: [Transfer] = []
    var errors: [Error] = []
    var stopped = false
}

struct OperationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class FileOperations {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func move(_ sources: [URL], to directory: URL, resolve: (URL) -> ConflictChoice) -> OperationResult {
        transfer(sources, to: directory, copiesInPlace: false, resolve: resolve) { source, destination in
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    func copy(_ sources: [URL], to directory: URL, resolve: (URL) -> ConflictChoice) -> OperationResult {
        transfer(sources, to: directory, copiesInPlace: true, resolve: resolve) { source, destination in
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    func trash(_ urls: [URL]) -> OperationResult {
        var result = OperationResult()
        for url in urls {
            do {
                var trashed: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &trashed)
                if let trashed = trashed as URL? {
                    result.transfers.append(Transfer(source: url, destination: trashed))
                }
            } catch {
                result.errors.append(error)
            }
        }
        return result
    }

    func duplicate(_ urls: [URL]) -> OperationResult {
        var result = OperationResult()
        for url in urls {
            let directory = url.deletingLastPathComponent()
            let name = FileNaming.available(url.lastPathComponent, in: directory.path, copySuffix: true, exists: exists)
            let destination = directory.appending(path: name)
            do {
                try fileManager.copyItem(at: url, to: destination)
                result.transfers.append(Transfer(source: url, destination: destination))
            } catch {
                result.errors.append(error)
            }
        }
        return result
    }

    func rename(_ url: URL, to name: String) throws -> URL {
        if let message = FileNaming.validationError(for: name) {
            throw OperationError(message: message)
        }
        let destination = url.deletingLastPathComponent().appending(path: name)
        guard destination.lastPathComponent != url.lastPathComponent else { return url }
        let isCaseChange = destination.lastPathComponent.lowercased() == url.lastPathComponent.lowercased()
        if !isCaseChange && exists(destination.path) {
            throw OperationError(message: "The name “\(name)” is already taken. Please choose a different name.")
        }
        try fileManager.moveItem(at: url, to: destination)
        return destination
    }

    func makeFolder(in directory: URL, name: String = "untitled folder") throws -> URL {
        let destination = directory.appending(path: FileNaming.available(name, in: directory.path, exists: exists), directoryHint: .isDirectory)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        return destination
    }

    func makeFile(in directory: URL, name: String = "untitled.txt") throws -> URL {
        let destination = directory.appending(path: FileNaming.available(name, in: directory.path, exists: exists))
        guard fileManager.createFile(atPath: destination.path, contents: Data()) else {
            throw OperationError(message: "Couldn't create “\(destination.lastPathComponent)”.")
        }
        return destination
    }

    func moveBack(_ transfers: [Transfer]) -> OperationResult {
        var result = OperationResult()
        for transfer in transfers.reversed() {
            do {
                try fileManager.createDirectory(at: transfer.source.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: transfer.destination, to: transfer.source)
                result.transfers.append(Transfer(source: transfer.destination, destination: transfer.source))
            } catch {
                result.errors.append(error)
            }
        }
        return result
    }

    private func transfer(_ sources: [URL], to directory: URL, copiesInPlace: Bool, resolve: (URL) -> ConflictChoice, perform: (URL, URL) throws -> Void) -> OperationResult {
        var result = OperationResult()
        let directoryPath = directory.standardizedFileURL.path
        let resolvedDirectory = resolved(directory)
        var placed: Set<String> = []
        for source in sources {
            let sourcePath = resolved(source)
            if resolvedDirectory == sourcePath || resolvedDirectory.hasPrefix(sourcePath + "/") {
                result.errors.append(OperationError(message: "“\(source.lastPathComponent)” can't be moved or copied into itself."))
                continue
            }
            let sameDirectory = resolved(source.deletingLastPathComponent()) == resolvedDirectory
            var destination = directory.appending(path: source.lastPathComponent)
            var replaced: URL?
            if sameDirectory && !copiesInPlace {
                continue
            } else if sameDirectory {
                destination = directory.appending(path: FileNaming.available(source.lastPathComponent, in: directoryPath, copySuffix: true, exists: exists))
            } else if placed.contains(destination.lastPathComponent.lowercased()) {
                destination = directory.appending(path: FileNaming.available(source.lastPathComponent, in: directoryPath, exists: exists))
            } else if exists(destination.path) {
                switch resolve(destination) {
                case .stop:
                    result.stopped = true
                    return result
                case .skip:
                    continue
                case .keepBoth:
                    destination = directory.appending(path: FileNaming.available(source.lastPathComponent, in: directoryPath, exists: exists))
                case .replace:
                    let target = resolved(destination)
                    if sourcePath == target || sourcePath.hasPrefix(target + "/") {
                        result.errors.append(OperationError(message: "“\(destination.lastPathComponent)” can't be replaced by an item inside it."))
                        continue
                    }
                    do {
                        var trashed: NSURL?
                        try fileManager.trashItem(at: destination, resultingItemURL: &trashed)
                        replaced = trashed as URL?
                    } catch {
                        result.errors.append(error)
                        continue
                    }
                }
            }
            do {
                try perform(source, destination)
                result.transfers.append(Transfer(source: source, destination: destination))
                if let replaced {
                    result.replaced.append(Transfer(source: destination, destination: replaced))
                }
                placed.insert(destination.lastPathComponent.lowercased())
            } catch {
                result.errors.append(error)
                if let replaced {
                    putBack(replaced, at: destination, into: &result)
                }
            }
        }
        return result
    }

    private func putBack(_ replaced: URL, at destination: URL, into result: inout OperationResult) {
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.trashItem(at: destination, resultingItemURL: nil)
            }
            try fileManager.moveItem(at: replaced, to: destination)
        } catch {
            result.errors.append(error)
        }
    }

    private func resolved(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func exists(_ path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }
}
