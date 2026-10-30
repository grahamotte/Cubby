import Foundation
import UniformTypeIdentifiers

final class FileItem {
    let directory: String
    let name: String
    let isDirectory: Bool
    private(set) var isSymlink: Bool
    private(set) var isPackage: Bool
    private(set) var isHidden: Bool
    private(set) var size: Int64
    private(set) var modified: Double
    private(set) var created: Double
    private(set) var added: Double
    private(set) var fileID: UInt64
    var children: [FileItem]?

    init(directory: String, name: String, isDirectory: Bool, isSymlink: Bool = false, isPackage: Bool = false, isHidden: Bool = false, size: Int64 = 0, modified: Double = 0, created: Double = 0, added: Double = 0, fileID: UInt64 = 0) {
        self.directory = directory
        self.name = name
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.size = size
        self.modified = modified
        self.created = created
        self.added = added
        self.fileID = fileID
    }

    var path: String {
        directory == "/" ? "/" + name : directory + "/" + name
    }

    var url: URL {
        URL(filePath: path, directoryHint: isFolder ? .isDirectory : .notDirectory)
    }

    var isFolder: Bool { isDirectory && !isPackage }

    var pathExtension: String { (name as NSString).pathExtension }

    var kind: String { KindCache.shared.description(for: self) }

    func update(from other: FileItem) {
        isSymlink = other.isSymlink
        isPackage = other.isPackage
        isHidden = other.isHidden
        size = other.size
        modified = other.modified
        created = other.created
        added = other.added
        fileID = other.fileID
    }

    func placed(in directory: String, name: String? = nil) -> FileItem {
        FileItem(directory: directory, name: name ?? self.name, isDirectory: isDirectory, isSymlink: isSymlink, isPackage: isPackage, isHidden: isHidden, size: size, modified: modified, created: created, added: added, fileID: fileID)
    }

    func sameEntry(as other: FileItem) -> Bool {
        name == other.name && fileID == other.fileID && modified == other.modified && size == other.size && isDirectory == other.isDirectory && isHidden == other.isHidden
    }
}

final class KindCache {
    static let shared = KindCache()

    private let lock = NSLock()
    private var descriptions: [String: String] = [:]
    private var packages: [String: Bool] = [:]

    func description(for item: FileItem) -> String {
        if item.isFolder { return "Folder" }
        let ext = item.pathExtension.lowercased()
        let key = (item.isDirectory ? "d:" : "f:") + ext
        lock.lock()
        defer { lock.unlock() }
        if let cached = descriptions[key] { return cached }
        let type = ext.isEmpty ? nil : UTType(filenameExtension: ext, conformingTo: item.isDirectory ? .directory : .data)
        let description: String
        if let type, !type.isDynamic, let text = type.localizedDescription {
            description = text.prefix(1).uppercased() + text.dropFirst()
        } else if ext.isEmpty {
            description = "Document"
        } else {
            description = "\(ext.uppercased()) File"
        }
        descriptions[key] = description
        return description
    }

    func isPackage(extension ext: String) -> Bool {
        guard !ext.isEmpty else { return false }
        let key = ext.lowercased()
        lock.lock()
        defer { lock.unlock() }
        if let cached = packages[key] { return cached }
        let result = UTType(filenameExtension: key, conformingTo: .directory)?.conforms(to: .package) ?? false
        packages[key] = result
        return result
    }
}
