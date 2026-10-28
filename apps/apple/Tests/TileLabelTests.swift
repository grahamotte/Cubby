import AppKit
import XCTest
@testable import CubbyCore

final class TileLabelTests: XCTestCase {
    private let font = NSFont.systemFont(ofSize: 12)

    func testShortNamesStayWhole() {
        XCTAssertNil(TileLabel.lines("notes.txt", width: 120, font: font))
        XCTAssertNil(TileLabel.lines("", width: 120, font: font))
    }

    func testNamesThatFitTwoLinesAreNotSplit() {
        XCTAssertNil(TileLabel.lines("a photo with a longer name.jpg", width: 120, font: font))
    }

    func testLongNamesSplitAfterTheFirstLine() throws {
        let name = "019ff0a5-708c-7a5b-affd-d06f1a4c470e-HqFaGk5xoJXLs4Zrb5xT2us26OWZrl2lCydB2.jpg"
        let lines = try XCTUnwrap(TileLabel.lines(name, width: 120, font: font))
        XCTAssertEqual(lines.first + lines.rest, name)
        XCTAssertFalse(lines.first.isEmpty)
        XCTAssertLessThanOrEqual(NSAttributedString(string: lines.first.trimmingCharacters(in: .whitespaces), attributes: [.font: font]).size().width, 120)
        XCTAssertTrue(lines.rest.hasSuffix(".jpg"))
    }

    func testTextTruncatesOnlyTheSecondLine() {
        let name = String(repeating: "abcdefghij", count: 12)
        let text = TileLabel.text(name, width: 100, font: font, color: .labelColor)
        XCTAssertEqual(text.string.replacingOccurrences(of: "\n", with: ""), name)
        let first = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let last = text.attribute(.paragraphStyle, at: text.length - 1, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(first?.lineBreakMode, .byWordWrapping)
        XCTAssertEqual(last?.lineBreakMode, .byTruncatingMiddle)
        XCTAssertEqual(last?.alignment, .center)
    }

    func testTextKeepsShortNamesInOneParagraph() {
        let text = TileLabel.text("notes.txt", width: 100, font: font, color: .labelColor)
        XCTAssertEqual(text.string, "notes.txt")
        XCTAssertEqual((text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.lineBreakMode, .byWordWrapping)
    }
}
