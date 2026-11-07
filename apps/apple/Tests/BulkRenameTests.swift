import XCTest
@testable import CubbyCore

final class BulkRenameTests: XCTestCase {
    private let root = URL(filePath: "/d", directoryHint: .isDirectory)

    private func items(_ names: String...) -> [BulkRename.Item] {
        names.map { BulkRename.Item(url: root.appending(path: $0), splitsExtension: true) }
    }

    private func names(_ rename: BulkRename, _ items: [BulkRename.Item], exists: @escaping (String) -> Bool = { _ in false }) -> [String] {
        rename.plan(items, exists: exists).map(\.name)
    }

    func testLeavesNamesAloneByDefault() {
        let rows = BulkRename().plan(items("a.txt", "b"), exists: { _ in true })
        XCTAssertEqual(rows.map(\.name), ["a.txt", "b"])
        XCTAssertFalse(rows.contains(where: \.changed))
        XCTAssertNil(rows.compactMap(\.problem).first)
    }

    func testFindsAndReplacesInTheBaseName() {
        var rename = BulkRename()
        rename.find = "txt"
        rename.replace = "md"
        XCTAssertEqual(names(rename, items("txt notes.txt", "Txt.txt")), ["md notes.txt", "Txt.txt"])
    }

    func testReplacesWithRegularExpressions() {
        var rename = BulkRename()
        rename.regex = true
        rename.find = #"IMG_(\d+)"#
        rename.replace = "Photo $1"
        XCTAssertEqual(names(rename, items("IMG_0042.jpg", "other.jpg")), ["Photo 0042.jpg", "other.jpg"])
        XCTAssertNil(rename.regexError)

        rename.find = "("
        XCTAssertEqual(rename.regexError, "The regular expression is invalid.")
        XCTAssertEqual(names(rename, items("a(b.txt")), ["a(b.txt"])
        rename.regex = false
        rename.replace = ""
        XCTAssertNil(rename.regexError)
        XCTAssertEqual(names(rename, items("a(b.txt")), ["ab.txt"])
    }

    func testAddsAndRemovesText() {
        var rename = BulkRename()
        rename.prefix = "2026 "
        rename.suffix = " final"
        rename.removeFirst = 2
        rename.removeLast = 1
        XCTAssertEqual(names(rename, items("x-reportZ.pdf", "ab")), ["2026 report final.pdf", "2026  final"])
    }

    func testKeepsFolderNamesWhole() {
        var rename = BulkRename()
        rename.suffix = "!"
        let folder = BulkRename.Item(url: root.appending(path: "v1.2"), splitsExtension: false)
        XCTAssertEqual(rename.plan([folder], exists: { _ in false }).map(\.name), ["v1.2!"])
    }

    func testChangesCase() {
        var rename = BulkRename()
        rename.letterCase = .upper
        XCTAssertEqual(names(rename, items("hello world.txt")), ["HELLO WORLD.txt"])
        rename.letterCase = .lower
        XCTAssertEqual(names(rename, items("Hello World.TXT")), ["hello world.TXT"])
        rename.letterCase = .title
        XCTAssertEqual(names(rename, items("hello world.txt")), ["Hello World.txt"])
    }

    func testNumbersWithPadding() {
        var rename = BulkRename()
        rename.numbering = .after
        let many = (1...10).map { BulkRename.Item(url: root.appending(path: "p\($0).jpg"), splitsExtension: true) }
        let numbered = names(rename, many)
        XCTAssertEqual(numbered.first, "p1 01.jpg")
        XCTAssertEqual(numbered.last, "p10 10.jpg")

        rename.numbering = .before
        rename.separator = "_"
        rename.start = 7
        XCTAssertEqual(names(rename, items("a.txt", "b.txt", "c.txt")), ["7_a.txt", "8_b.txt", "9_c.txt"])

        rename.find = "a"
        XCTAssertEqual(names(rename, items("a.txt")), ["7.txt"])
    }

    func testFlagsProblems() {
        var rename = BulkRename()
        rename.regex = true
        rename.find = "^.*$"
        rename.replace = "same"
        let rows = rename.plan(items("a.txt", "b.txt"), exists: { _ in false })
        XCTAssertEqual(rows.map(\.problem), ["Another item gets this name.", "Another item gets this name."])

        rename.replace = "taken"
        XCTAssertEqual(rename.plan(items("a.txt"), exists: { $0 == "/d/taken.txt" }).first?.problem, "An item with this name already exists.")

        rename.replace = "a:b"
        XCTAssertEqual(rename.plan(items("a.txt"), exists: { _ in false }).first?.problem, "The name can't contain “:”.")

        rename.find = "^"
        rename.replace = "."
        XCTAssertEqual(rename.plan(items("a.txt"), exists: { _ in false }).first?.problem, "Names that begin with “.” are hidden.")
    }

    func testAllowsSwapsAndCaseChanges() {
        var rename = BulkRename()
        rename.letterCase = .upper
        let rows = rename.plan(items("c.txt"), exists: { _ in true })
        XCTAssertEqual(rows.map(\.name), ["C.txt"])
        XCTAssertNil(rows[0].problem)

        var swap = BulkRename()
        swap.regex = true
        swap.find = "^.*$"
        swap.numbering = .before
        let swapRows = swap.plan(items("2.txt", "1.txt"), exists: { _ in true })
        XCTAssertEqual(swapRows.map(\.name), ["1.txt", "2.txt"])
        XCTAssertEqual(swapRows.compactMap(\.problem), [])
    }
}
