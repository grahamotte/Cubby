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

    func testMatchRangesFindEveryRunOfTwoOrMoreCharacters() {
        XCTAssertEqual(FileSorter.matchRanges(in: "Report report.txt", query: "rep"), [NSRange(location: 0, length: 3), NSRange(location: 7, length: 3)])
        XCTAssertEqual(FileSorter.matchRanges(in: "notes.md", query: " not "), [NSRange(location: 0, length: 3)])
        XCTAssertEqual(FileSorter.matchRanges(in: "notes.md", query: "n"), [])
        XCTAssertEqual(FileSorter.matchRanges(in: "notes.md", query: ""), [])
        XCTAssertEqual(FileSorter.matchRanges(in: "notes.md", query: "xyz"), [])
    }

    func testMatchRangesMapOntoDisplayedNamesWithAccentsAndCase() {
        XCTAssertEqual(FileSorter.matchRanges(in: "Résumé.pdf", query: "RESU"), [NSRange(location: 0, length: 4)])
        let decomposed = "Re\u{301}sume\u{301}.pdf"
        let ranges = FileSorter.matchRanges(in: decomposed, query: "ésu")
        XCTAssertEqual(ranges, [NSRange(location: 1, length: 4)])
        XCTAssertEqual((decomposed as NSString).substring(with: ranges[0]), "e\u{301}su")
        let emoji = "🎉party🎉.txt"
        XCTAssertEqual((emoji as NSString).substring(with: FileSorter.matchRanges(in: emoji, query: "PARTY")[0]), "party")
    }

    func testFiltersHiddenAndQuery() {
        let items = [item(".git", directory: true, hidden: true), item("Résumé.pdf"), item("notes.md")]
        let hidden = Visibility(showHidden: true, showDSStore: false)
        XCTAssertEqual(names(FileSorter.filtered(items, visibility: .standard, query: "")), ["Résumé.pdf", "notes.md"])
        XCTAssertEqual(names(FileSorter.filtered(items, visibility: hidden, query: "")).count, 3)
        XCTAssertEqual(names(FileSorter.filtered(items, visibility: .standard, query: " resume ")), ["Résumé.pdf"])
        XCTAssertEqual(names(FileSorter.filtered(items, visibility: hidden, query: "GIT")), [".git"])
    }

    func testFiltersDSStoreUnlessShown() {
        let items = [item(".DS_Store", hidden: true), item(".git", directory: true, hidden: true), item("notes.md")]
        XCTAssertEqual(names(FileSorter.filtered(items, visibility: Visibility(showHidden: true, showDSStore: false), query: "")), [".git", "notes.md"])
        XCTAssertEqual(names(FileSorter.filtered(items, visibility: Visibility(showHidden: true, showDSStore: true), query: "")), [".DS_Store", ".git", "notes.md"])
        XCTAssertEqual(names(FileSorter.filtered(items, visibility: Visibility(showHidden: false, showDSStore: true), query: "")), ["notes.md"])
        XCTAssertEqual(names(FileSorter.filtered(items, visibility: Visibility(showHidden: true, showDSStore: false), query: "DS")), [])
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
