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

    func testAddsTextAroundTheName() {
        var rename = BulkRename()
        rename.prefix = "2026 "
        rename.suffix = " final"
        XCTAssertEqual(names(rename, items("report.pdf", "ab")), ["2026 report final.pdf", "2026 ab final"])
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
        rename.find = "1"
        rename.replace = "2"
        let rows = rename.plan(items("a1.txt", "a2.txt"), exists: { _ in true })
        XCTAssertEqual(rows.map(\.problem), ["Another item gets this name.", nil])

        rename.replace = "taken"
        XCTAssertEqual(rename.plan(items("1.txt"), exists: { $0 == "/d/taken.txt" }).first?.problem, "An item with this name already exists.")

        rename.replace = "a:b"
        XCTAssertEqual(rename.plan(items("1.txt"), exists: { _ in false }).first?.problem, "The name can't contain “:”.")

        var hidden = BulkRename()
        hidden.prefix = "."
        XCTAssertEqual(hidden.plan(items("a.txt"), exists: { _ in false }).first?.problem, "Names that begin with “.” are hidden.")
    }

    func testAllowsChainsAndCaseChanges() {
        var rename = BulkRename()
        rename.letterCase = .upper
        let rows = rename.plan(items("c.txt"), exists: { _ in true })
        XCTAssertEqual(rows.map(\.name), ["C.txt"])
        XCTAssertNil(rows[0].problem)

        var chain = BulkRename()
        chain.find = "1"
        chain.replace = "11"
        let chainRows = chain.plan(items("1.txt", "11.txt"), exists: { ["/d/1.txt", "/d/11.txt"].contains($0) })
        XCTAssertEqual(chainRows.map(\.name), ["11.txt", "1111.txt"])
        XCTAssertEqual(chainRows.compactMap(\.problem), [])
    }
}
