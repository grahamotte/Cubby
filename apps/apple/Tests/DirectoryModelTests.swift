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
        let model = DirectoryModel(path: directory.path, view: .standard, showHidden: false)
        waitForChange(model) { model.start() }
        XCTAssertTrue(model.isLoaded)
        XCTAssertEqual(names(model.items), ["a.txt", "b.txt"])
        XCTAssertEqual(model.allItems.count, 3)

        model.sort = .size
        model.ascending = false
        waitForChange(model) { model.applyPresentation() }
        XCTAssertEqual(names(model.items), ["b.txt", "a.txt"])

        model.query = "A."
        waitForChange(model) { model.applyPresentation() }
        XCTAssertEqual(names(model.items), ["a.txt"])

        model.query = ""
        model.showHidden = true
        waitForChange(model) { model.applyPresentation() }
        XCTAssertEqual(model.items.count, 3)
        model.stop()
    }

    func testReloadsWhenDirectoryChanges() {
        let directory = makeTemporaryDirectory()
        makeFile(directory, "a.txt")
        let model = DirectoryModel(path: directory.path, view: .standard, showHidden: false)
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
        let model = DirectoryModel(path: directory.path, view: .standard, showHidden: false)
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
        let model = DirectoryModel(path: "/nonexistent/\(UUID().uuidString)", view: .standard, showHidden: false)
        waitForChange(model) { model.start() }
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.items.isEmpty)
    }
}
