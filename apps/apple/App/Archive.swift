import Foundation

struct Archive: Equatable {
    let executable: URL
    let arguments: [String]
    let directory: URL?
    let destination: URL

    static func plan(for urls: [URL], exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Archive? {
        guard let first = urls.first else { return nil }
        let directory = first.deletingLastPathComponent()
        let baseName = urls.count == 1 ? first.lastPathComponent : "Archive"
        let destination = directory.appending(path: FileNaming.available(baseName + ".zip", in: directory.path, exists: exists))
        if urls.count == 1 {
            return Archive(executable: URL(filePath: "/usr/bin/ditto"), arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, destination.path], directory: nil, destination: destination)
        }
        return Archive(executable: URL(filePath: "/usr/bin/zip"), arguments: ["-r", "-y", "-q", destination.path, "--"] + urls.map(\.lastPathComponent), directory: directory, destination: destination)
    }
}
