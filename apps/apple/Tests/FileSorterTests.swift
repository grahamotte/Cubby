import XCTest
@testable import CubbyCore

final class FileSorterTests: XCTestCase {
    func testSortsNamesNaturally() {
        let items = [item("file10"), item("File2"), item("file1"), item("apple")]
        XCTAssertEqual(names(FileSorter.sorted(items, by: .name, ascending: true)), ["apple", "file1", "File2", "file10"])
        XCTAssertEqual(names(FileSorter.sorted(items, by: .name, ascending: false)), ["file10", "File2", "file1", "apple"])
    }

    func testSortsByValuesWithNameTiebreak() {
        let items = [item("b", size: 5), item("a", size: 5), item("c", size: 9), item("dir", directory: true)]
        XCTAssertEqual(names(FileSorter.sorted(items, by: .size, ascending: false)), ["c", "a", "b", "dir"])
        XCTAssertEqual(names(FileSorter.sorted(items, by: .size, ascending: true)), ["dir", "a", "b", "c"])
        let dated = [item("old", modified: 1, created: 3, added: 2), item("new", modified: 3, created: 1, added: 1)]
        XCTAssertEqual(names(FileSorter.sorted(dated, by: .modified, ascending: false)), ["new", "old"])
        XCTAssertEqual(names(FileSorter.sorted(dated, by: .created, ascending: false)), ["old", "new"])
        XCTAssertEqual(names(FileSorter.sorted(dated, by: .added, ascending: true)), ["new", "old"])
    }

    func testSortsByKind() {
        let items = [item("z.txt"), item("folder", directory: true), item("a.txt")]
        XCTAssertEqual(names(FileSorter.sorted(items, by: .kind, ascending: true)).first, "folder")
        XCTAssertEqual(Array(names(FileSorter.sorted(items, by: .kind, ascending: true)).suffix(2)), ["a.txt", "z.txt"])
    }

    func testFiltersHiddenAndQuery() {
        let items = [item(".git", directory: true, hidden: true), item("Résumé.pdf"), item("notes.md")]
        XCTAssertEqual(names(FileSorter.filtered(items, showHidden: false, query: "")), ["Résumé.pdf", "notes.md"])
        XCTAssertEqual(names(FileSorter.filtered(items, showHidden: true, query: "")).count, 3)
        XCTAssertEqual(names(FileSorter.filtered(items, showHidden: false, query: " resume ")), ["Résumé.pdf"])
        XCTAssertEqual(names(FileSorter.filtered(items, showHidden: true, query: "GIT")), [".git"])
    }

    func testSortsLargeListsQuickly() {
        let items = (0..<100_000).map { item("file \(($0 * 7919) % 100_000).txt", size: Int64($0)) }
        let start = Date()
        let sorted = FileSorter.sorted(items, by: .name, ascending: true)
        XCTAssertEqual(sorted.first?.name, "file 0.txt")
        XCTAssertEqual(sorted.last?.name, "file 99999.txt")
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
}

final class FileSorterNaturalCompareTests: XCTestCase {
    private func compare(_ a: String, _ b: String) -> ComparisonResult {
        FileSorter.naturalCompare(Array(a.utf16), Array(b.utf16))
    }

    func testNaturalCompare() {
        XCTAssertEqual(compare("a2", "a10"), .orderedAscending)
        XCTAssertEqual(compare("a010", "a9"), .orderedDescending)
        XCTAssertEqual(compare("a01", "a1"), .orderedSame)
        XCTAssertEqual(compare("abc", "ab"), .orderedDescending)
        XCTAssertEqual(compare("", "a"), .orderedAscending)
        XCTAssertEqual(compare("x 0", "x 00"), .orderedSame)
    }
}
