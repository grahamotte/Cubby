import Darwin
import Foundation

enum DirectoryReader {
    struct ReadError: LocalizedError {
        let path: String
        let code: Int32

        var errorDescription: String? {
            "Couldn't read \((path as NSString).lastPathComponent): \(String(cString: strerror(code)))"
        }

        var isPermissionDenied: Bool { code == EACCES || code == EPERM }
    }

    private static let bufferSize = 256 * 1024
    private static let hiddenFlag = UInt32(UF_HIDDEN)

    static func read(_ path: String, isCancelled: () -> Bool = { false }) throws -> [FileItem] {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw ReadError(path: path, code: errno) }
        defer { close(fd) }

        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_CRTIME) | attrgroup_t(ATTR_CMN_MODTIME) | attrgroup_t(ATTR_CMN_FLAGS) | attrgroup_t(ATTR_CMN_FILEID) | attrgroup_t(ATTR_CMN_ADDEDTIME)
        request.fileattr = attrgroup_t(ATTR_FILE_TOTALSIZE)

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }

        var items: [FileItem] = []
        let directory = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        while true {
            if isCancelled() { return items }
            let count = getattrlistbulk(fd, &request, buffer, bufferSize, UInt64(FSOPT_PACK_INVAL_ATTRS))
            if count < 0 {
                let code = errno
                if code == ENOTSUP || code == EINVAL { return try fallback(directory) }
                throw ReadError(path: path, code: code)
            }
            if count == 0 { break }
            var entry = UnsafeRawPointer(buffer)
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                if let item = parse(entry, directory: directory) {
                    items.append(item)
                }
                entry = entry.advanced(by: length)
            }
        }
        return items
    }

    static func count(_ path: String, visibility: Visibility) throws -> Int {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw ReadError(path: path, code: errno) }
        defer { close(fd) }

        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_FLAGS)

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }

        var total = 0
        while true {
            let count = getattrlistbulk(fd, &request, buffer, bufferSize, UInt64(FSOPT_PACK_INVAL_ATTRS))
            if count < 0 {
                let code = errno
                if code == ENOTSUP || code == EINVAL { return try fallbackCount(path, visibility: visibility) }
                throw ReadError(path: path, code: code)
            }
            if count == 0 { break }
            var entry = UnsafeRawPointer(buffer)
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                let cursor = entry.advanced(by: 4 + MemoryLayout<attribute_set_t>.size)
                let nameOffset = cursor.loadUnaligned(as: Int32.self)
                let nameLength = cursor.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
                if nameLength > 1 {
                    let name = String(cString: cursor.advanced(by: Int(nameOffset)).assumingMemoryBound(to: CChar.self))
                    let flags = cursor.loadUnaligned(fromByteOffset: MemoryLayout<attrreference_t>.size, as: UInt32.self)
                    if visibility.shows(name: name, isHidden: name.hasPrefix(".") || (flags & hiddenFlag) != 0) {
                        total += 1
                    }
                }
                entry = entry.advanced(by: length)
            }
        }
        return total
    }

    private static func parse(_ entry: UnsafeRawPointer, directory: String) -> FileItem? {
        var cursor = entry.advanced(by: 4)
        let returned = cursor.loadUnaligned(as: attribute_set_t.self)
        cursor = cursor.advanced(by: MemoryLayout<attribute_set_t>.size)

        let nameOffset = cursor.loadUnaligned(as: Int32.self)
        let nameLength = cursor.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
        let namePointer = cursor.advanced(by: Int(nameOffset)).assumingMemoryBound(to: CChar.self)
        guard nameLength > 1 else { return nil }
        let name = String(cString: namePointer)
        cursor = cursor.advanced(by: MemoryLayout<attrreference_t>.size)

        let objectType = cursor.loadUnaligned(as: UInt32.self)
        cursor = cursor.advanced(by: 4)
        let created = loadTime(&cursor)
        let modified = loadTime(&cursor)
        let flags = cursor.loadUnaligned(as: UInt32.self)
        cursor = cursor.advanced(by: 4)
        let fileID = cursor.loadUnaligned(as: UInt64.self)
        cursor = cursor.advanced(by: 8)
        let added = loadTime(&cursor)
        let size = (returned.fileattr & attrgroup_t(ATTR_FILE_TOTALSIZE)) != 0 ? cursor.loadUnaligned(as: Int64.self) : 0
        let hasAdded = (returned.commonattr & attrgroup_t(ATTR_CMN_ADDEDTIME)) != 0

        let isSymlink = objectType == VLNK.rawValue
        var isDirectory = objectType == VDIR.rawValue
        if isSymlink {
            var info = stat()
            let full = directory == "/" ? "/" + name : directory + "/" + name
            isDirectory = stat(full, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
        }
        let ext = (name as NSString).pathExtension
        return FileItem(
            directory: directory,
            name: name,
            isDirectory: isDirectory,
            isSymlink: isSymlink,
            isPackage: isDirectory && !isSymlink && KindCache.shared.isPackage(extension: ext),
            isHidden: name.hasPrefix(".") || (flags & hiddenFlag) != 0,
            size: isDirectory ? 0 : size,
            modified: modified,
            created: created,
            added: hasAdded ? added : 0,
            fileID: fileID,
        )
    }

    private static func loadTime(_ cursor: inout UnsafeRawPointer) -> Double {
        let seconds = cursor.loadUnaligned(as: Int.self)
        let nanoseconds = cursor.loadUnaligned(fromByteOffset: MemoryLayout<Int>.size, as: Int.self)
        cursor = cursor.advanced(by: MemoryLayout<timespec>.size)
        return Double(seconds) + Double(nanoseconds) / 1_000_000_000
    }

    private static func fallbackCount(_ path: String, visibility: Visibility) throws -> Int {
        let urls = try FileManager.default.contentsOfDirectory(at: URL(filePath: path, directoryHint: .isDirectory), includingPropertiesForKeys: [.isHiddenKey])
        return urls.filter { url in
            let name = url.lastPathComponent
            return visibility.shows(name: name, isHidden: (try? url.resourceValues(forKeys: [.isHiddenKey]))?.isHidden ?? name.hasPrefix("."))
        }.count
    }

    private static func fallback(_ directory: String) throws -> [FileItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isHiddenKey, .totalFileSizeKey, .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey, .fileResourceIdentifierKey]
        let urls = try FileManager.default.contentsOfDirectory(at: URL(filePath: directory, directoryHint: .isDirectory), includingPropertiesForKeys: keys)
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory ?? false
            return FileItem(
                directory: directory,
                name: url.lastPathComponent,
                isDirectory: isDirectory,
                isSymlink: values?.isSymbolicLink ?? false,
                isPackage: values?.isPackage ?? false,
                isHidden: values?.isHidden ?? url.lastPathComponent.hasPrefix("."),
                size: isDirectory ? 0 : Int64(values?.totalFileSize ?? 0),
                modified: values?.contentModificationDate?.timeIntervalSince1970 ?? 0,
                created: values?.creationDate?.timeIntervalSince1970 ?? 0,
                added: values?.addedToDirectoryDate?.timeIntervalSince1970 ?? 0,
                fileID: 0,
            )
        }
    }
}
