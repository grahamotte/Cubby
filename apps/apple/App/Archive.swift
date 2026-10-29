import Foundation

struct Archive: Equatable {
    let executable: URL
    let arguments: [String]
    let directory: URL?
    let destination: URL

    static func plan(for urls: [URL], exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Archive? {
        guard let first = urls.first else { return nil }
        let parents = urls.map { $0.deletingLastPathComponent().standardizedFileURL.pathComponents }
        let common = parents.dropFirst().reduce(parents[0]) { prefix, components in
            zip(prefix, components).prefix { $0 == $1 }.map(\.0)
        }
        let directory = URL(filePath: NSString.path(withComponents: common), directoryHint: .isDirectory)
        let baseName = urls.count == 1 ? first.lastPathComponent : "Archive"
        let destination = directory.appending(path: FileNaming.available(baseName + ".zip", in: directory.path, exists: exists))
        if urls.count == 1 {
            return Archive(executable: URL(filePath: "/usr/bin/ditto"), arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, destination.path], directory: nil, destination: destination)
        }
        return Archive(executable: URL(filePath: "/usr/bin/zip"), arguments: ["-r", "-y", "-q", destination.path, "--"] + urls.map { $0.standardizedFileURL.pathComponents.dropFirst(common.count).joined(separator: "/") }, directory: directory, destination: destination)
    }
}
