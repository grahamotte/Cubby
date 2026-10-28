import Foundation
@testable import CubbyCore

func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "CubbyTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}

@discardableResult
func makeFile(_ directory: URL, _ name: String, contents: String = "") -> URL {
    let url = directory.appending(path: name)
    try! Data(contents.utf8).write(to: url)
    return url
}

@discardableResult
func makeFolder(_ directory: URL, _ name: String) -> URL {
    let url = directory.appending(path: name, directoryHint: .isDirectory)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func item(_ name: String, directory: Bool = false, hidden: Bool = false, size: Int64 = 0, modified: Double = 0, created: Double = 0, added: Double = 0) -> FileItem {
    FileItem(directory: "/tmp", name: name, isDirectory: directory, isHidden: hidden, size: size, modified: modified, created: created, added: added)
}

func names(_ items: [FileItem]) -> [String] {
    items.map(\.name)
}

func sidebarJSON(_ nodes: [SidebarNode]) -> String {
    String(decoding: try! JSONStore.encode(nodes), as: UTF8.self)
}
