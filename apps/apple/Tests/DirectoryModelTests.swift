import XCTest
@testable import CubbyCore

@MainActor
final class DirectoryModelTests: XCTestCase {
    private func waitForChange(_ model: DirectoryModel, where matches: @escaping (DirectoryModel.Change) -> Bool = { _ in true }, perform: () -> Void) {
        let changed = expectation(description: "change")
        changed.assertForOverFulfill = false
        model.onChange = { change in if matches(change) { changed.fulfill() } }
        perform()
        wait(for: [changed], timeout: 5)
    }

    func testLoadsSortsAndFilters() {
        let directory = makeTemporaryDirectory()
        makeFile(directory, "b.txt", contents: "12345")
        makeFile(directory, "a.txt", contents: "1")
        makeFile(directory, ".hidden")
        makeFile(directory, ".DS_Store")
        let model = DirectoryModel(path: directory.path, view: .standard, visibility: .standard)
        waitForChange(model) { model.start() }
        XCTAssertTrue(model.isLoaded)
        XCTAssertEqual(names(model.items), ["a.txt", "b.txt"])
        XCTAssertEqual(model.allItems.count, 4)

        model.sort = .size
        model.ascending = false
        waitForChange(model) { model.applyPresentation() }
        XCTAssertEqual(names(model.items), ["b.txt", "a.txt"])

        model.query = "A."
        waitForChange(model) { model.applyPresentation() }
        XCTAssertEqual(names(model.items), ["a.txt"])

        model.query = ""
        model.visibility = Visibility(showHidden: true, showDSStore: false)
        waitForChange(model) { model.applyPresentation() }
        XCTAssertEqual(names(model.items), ["b.txt", "a.txt", ".hidden"])

        model.visibility = Visibility(showHidden: true, showDSStore: true)
        waitForChange(model) { model.applyPresentation() }
        XCTAssertEqual(model.items.count, 4)
        model.stop()
    }

    func testSortsByCountAsCountsArrive() {
        let directory = makeTemporaryDirectory()
        let many = makeFolder(directory, "many")
        for index in 0..<3 { makeFile(many, "f\(index)") }
        let few = makeFolder(directory, "few")
        makeFile(few, "f")
        makeFolder(directory, "empty")
        makeFile(directory, "file.txt")
        let model = DirectoryModel(path: directory.path, view: FolderView(mode: .list, sort: .count, ascending: false, iconSize: 80), visibility: .standard)
        waitForChange(model, where: { _ in names(model.items) == ["many", "few", "empty", "file.txt"] }) { model.start() }
        XCTAssertNotNil(model.counter)

        model.ascending = true
        waitForChange(model) { model.applyPresentation() }
        XCTAssertEqual(names(model.items), ["empty", "few", "many", "file.txt"])

        waitForChange(model, where: { _ in names(model.items) == ["empty", "many", "few", "file.txt"] }) {
            for index in 0..<5 { makeFile(few, "g\(index)") }
        }
        model.stop()
        XCTAssertNil(model.counter)
    }

    func testReloadsWhenDirectoryChanges() {
        let directory = makeTemporaryDirectory()
        makeFile(directory, "a.txt")
        let model = DirectoryModel(path: directory.path, view: .standard, visibility: .standard)
        waitForChange(model) { model.start() }
        let original = model.items[0]
        waitForChange(model, where: { if case .refreshed = $0 { return true } else { return false } }) {
            makeFile(directory, "b.txt")
        }
        XCTAssertEqual(names(model.items), ["a.txt", "b.txt"])
        XCTAssertTrue(model.items[0] === original)
        model.stop()
    }

    func testExpandsChildren() {
        let directory = makeTemporaryDirectory()
        let folder = makeFolder(directory, "folder")
        makeFile(folder, "inner.txt")
        let model = DirectoryModel(path: directory.path, view: .standard, visibility: .standard)
        waitForChange(model) { model.start() }
        let item = model.items[0]
        waitForChange(model, where: { if case .children = $0 { return true } else { return false } }) {
            model.expand(item)
        }
        XCTAssertEqual(model.children(of: item).map(names), ["inner.txt"])
        waitForChange(model, where: { if case .children = $0 { return true } else { return false } }) {
            makeFile(folder, "second.txt")
        }
        XCTAssertEqual(model.children(of: item).map(names), ["inner.txt", "second.txt"])
        model.collapse(item)
        model.stop()
    }

    func testReportsReadErrors() {
        let model = DirectoryModel(path: "/nonexistent/\(UUID().uuidString)", view: .standard, visibility: .standard)
        waitForChange(model) { model.start() }
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.items.isEmpty)
    }
}
