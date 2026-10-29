import XCTest
@testable import CubbyCore

final class FileNamingTests: XCTestCase {
    func testAvailableNames() {
        let taken: Set<String> = ["/d/a.txt", "/d/a 2.txt", "/d/folder", "/d/a copy.txt"]
        let exists = { taken.contains($0) }
        XCTAssertEqual(FileNaming.available("b.txt", in: "/d", exists: exists), "b.txt")
        XCTAssertEqual(FileNaming.available("a.txt", in: "/d", exists: exists), "a 3.txt")
        XCTAssertEqual(FileNaming.available("folder", in: "/d", exists: exists), "folder 2")
        XCTAssertEqual(FileNaming.available("a.txt", in: "/d", copySuffix: true, exists: exists), "a copy 2.txt")
        XCTAssertEqual(FileNaming.available("a copy.txt", in: "/d", copySuffix: true, exists: exists), "a copy 2.txt")
        XCTAssertEqual(FileNaming.available("b", in: "/d", copySuffix: true, exists: exists), "b copy")
    }

    func testSplitHandlesDotfiles() {
        XCTAssertEqual(FileNaming.split("a.tar.gz").1, "gz")
        XCTAssertEqual(FileNaming.split(".zshrc").1, "")
        XCTAssertEqual(FileNaming.split(".config.json").0, ".config")
        XCTAssertEqual(FileNaming.split("noext").0, "noext")
    }

    func testBecomesHidden() {
        XCTAssertTrue(FileNaming.becomesHidden(renaming: "notes.txt", to: ".notes.txt"))
        XCTAssertFalse(FileNaming.becomesHidden(renaming: ".zshrc", to: ".zprofile"))
        XCTAssertFalse(FileNaming.becomesHidden(renaming: ".zshrc", to: "zshrc"))
        XCTAssertFalse(FileNaming.becomesHidden(renaming: "a.txt", to: "b.txt"))
    }

    func testValidation() {
        XCTAssertNil(FileNaming.validationError(for: "ok.txt"))
        XCTAssertNotNil(FileNaming.validationError(for: " "))
        XCTAssertNotNil(FileNaming.validationError(for: "a/b"))
        XCTAssertNotNil(FileNaming.validationError(for: "a:b"))
        XCTAssertNotNil(FileNaming.validationError(for: ".."))
        XCTAssertNotNil(FileNaming.validationError(for: String(repeating: "x", count: 256)))
    }
}
