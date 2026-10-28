import XCTest
@testable import CubbyCore

final class ThemeLibraryTests: XCTestCase {
    func testBuiltInThemesDefineEveryRoleForBothVariants() {
        XCTAssertEqual(ThemeLibrary.builtIn.map(\.id), ["workbench", "bubblegum", "grove", "ocean", "ember", "iris"])
        XCTAssertEqual(ThemeLibrary.builtIn.map(\.name), ["Workbench", "Bubblegum", "Grove", "Ocean", "Ember", "Iris"])
        for theme in ThemeLibrary.builtIn {
            XCTAssertEqual(Set(theme.light.colors.keys), Set(ThemeRole.allCases), theme.id)
            XCTAssertEqual(Set(theme.dark.colors.keys), Set(ThemeRole.allCases), theme.id)
            XCTAssertNotEqual(theme.light, theme.dark, theme.id)
        }
    }

    func testDefaultThemeIsWorkbenchWithSystemAccent() {
        let theme = ThemeLibrary().theme(id: ThemeLibrary.defaultID)
        XCTAssertEqual(theme.id, "workbench")
        XCTAssertEqual(theme.light[.accent], .systemAccent)
        XCTAssertEqual(theme.dark[.accent], .systemAccent)
        XCTAssertEqual(theme.light[.content].string, "#FCFCFB")
        XCTAssertEqual(theme.dark[.content].string, "#1E1F21")
    }

    func testPaletteChoosesVariantByAppearance() {
        let grove = ThemeLibrary().theme(id: "grove")
        XCTAssertEqual(grove.palette(dark: false), grove.light)
        XCTAssertEqual(grove.palette(dark: true), grove.dark)
        XCTAssertEqual(grove.light[.accent].string, "#1B7D50")
        XCTAssertEqual(grove.dark[.accent].string, "#69D69A")
    }

    func testUnknownThemeFallsBackToDefault() {
        XCTAssertEqual(ThemeLibrary().theme(id: "missing").id, "workbench")
    }

    func testParsesHexColors() {
        XCTAssertEqual(ThemeColor("#FF8000"), .rgba(red: 1, green: 128.0 / 255, blue: 0, alpha: 1))
        XCTAssertEqual(ThemeColor("#00000080"), .rgba(red: 0, green: 0, blue: 0, alpha: 128.0 / 255))
        XCTAssertEqual(ThemeColor("#abcdef")?.string, "#ABCDEF")
        XCTAssertEqual(ThemeColor("system"), .systemAccent)
        for invalid in ["", "#", "FF8000", "#FF80", "#GG8000", "#+F8000", "#FF8000001", "red"] {
            XCTAssertNil(ThemeColor(invalid), invalid)
        }
    }

    func testColorStringsRoundTrip() {
        for string in ["#123456", "#12345678", "#FFFFFF12", "system"] {
            XCTAssertEqual(ThemeColor(string)?.string, string)
        }
        XCTAssertEqual(ThemeColor("#123456FF")?.string, "#123456")
    }

    func testLoadsThemeFilesAfterBuiltIns() throws {
        let directory = makeTemporaryDirectory()
        makeFile(directory, "sakura.json", contents: ##"{"name":"Sakura","light":{"accent":"#E0457B","content":"#FFF5F8"},"dark":{"accent":"#F07AA2"}}"##)
        makeFile(directory, "notes.txt", contents: "ignored")
        let library = ThemeLibrary(directory: directory)
        XCTAssertEqual(library.errors, [])
        XCTAssertEqual(library.themes.map(\.id), ThemeLibrary.builtIn.map(\.id) + ["sakura"])
        let sakura = library.theme(id: "sakura")
        XCTAssertEqual(sakura.name, "Sakura")
        XCTAssertEqual(sakura.light[.accent].string, "#E0457B")
        XCTAssertEqual(sakura.light[.content].string, "#FFF5F8")
        XCTAssertEqual(sakura.dark[.accent].string, "#F07AA2")
        XCTAssertEqual(sakura.light[.sidebar], ThemeLibrary.builtIn[0].light[.sidebar])
        XCTAssertEqual(sakura.dark[.content], ThemeLibrary.builtIn[0].dark[.content])
    }

    func testMissingDirectoryLoadsBuiltIns() {
        let library = ThemeLibrary(directory: makeTemporaryDirectory().appending(path: "missing"))
        XCTAssertEqual(library, ThemeLibrary())
    }

    func testReportsInvalidThemeFilesAndKeepsValidOnes() {
        let directory = makeTemporaryDirectory()
        makeFile(directory, "a-role.json", contents: ##"{"name":"A","light":{"glow":"#FFFFFF"},"dark":{}}"##)
        makeFile(directory, "b-color.json", contents: #"{"name":"B","light":{"accent":"blue"},"dark":{}}"#)
        makeFile(directory, "c-name.json", contents: #"{"name":"  ","light":{},"dark":{}}"#)
        makeFile(directory, "d-syntax.json", contents: "{")
        makeFile(directory, "grove.json", contents: #"{"name":"Mine","light":{},"dark":{}}"#)
        makeFile(directory, "e-good.json", contents: #"{"name":"Good","light":{},"dark":{}}"#)
        let library = ThemeLibrary(directory: directory)
        XCTAssertEqual(library.themes.last?.id, "e-good")
        XCTAssertEqual(library.themes.count, ThemeLibrary.builtIn.count + 1)
        XCTAssertEqual(library.theme(id: "grove").name, "Grove")
        XCTAssertEqual(library.errors.count, 5)
        XCTAssertTrue(library.errors[0].hasPrefix("a-role.json: "), library.errors[0])
        XCTAssertTrue(library.errors[0].contains("glow"), library.errors[0])
        XCTAssertTrue(library.errors[1].contains("blue"), library.errors[1])
        XCTAssertTrue(library.errors[2].contains("name"), library.errors[2])
        XCTAssertTrue(library.errors[3].hasPrefix("d-syntax.json: "), library.errors[3])
        XCTAssertTrue(library.errors[4].contains("grove"), library.errors[4])
    }
}
