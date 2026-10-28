import XCTest
@testable import CubbyCore

final class ShortcutsTests: XCTestCase {
    func testDisplaysModifiersInMacOrder() {
        XCTAssertEqual(KeyCombo.command("n", .shift).display, "⇧⌘N")
        XCTAssertEqual(KeyCombo.command("1", [.control, .option, .shift]).display, "⌃⌥⇧⌘1")
        XCTAssertEqual(KeyCombo(.delete, .command).display, "⌘⌫")
        XCTAssertEqual(KeyCombo(.space).display, "Space")
        XCTAssertEqual(KeyCombo(.returnKey).display, "↩")
        XCTAssertEqual(KeyCombo(.tab).display, "⇥")
        XCTAssertEqual(KeyCombo(.escape).display, "⎋")
        XCTAssertEqual(KeyCombo(.forwardDelete).display, "⌦")
        XCTAssertEqual(KeyCombo(.upArrow, .command).display, "⌘↑")
        XCTAssertEqual(KeyCombo(.downArrow, .command).display, "⌘↓")
        XCTAssertEqual(KeyCombo(.leftArrow).display, "←")
        XCTAssertEqual(KeyCombo(.rightArrow).display, "→")
    }

    func testKeyEquivalents() {
        XCTAssertEqual(KeyCombo.command("[").keyEquivalent, "[")
        XCTAssertEqual(KeyCombo(.delete, .command).keyEquivalent, "\u{8}")
        XCTAssertEqual(KeyCombo(.forwardDelete).keyEquivalent, "\u{7F}")
        XCTAssertEqual(KeyCombo(.returnKey).keyEquivalent, "\r")
        XCTAssertEqual(KeyCombo(.space).keyEquivalent, " ")
        XCTAssertEqual(KeyCombo(.tab).keyEquivalent, "\t")
        XCTAssertEqual(KeyCombo(.escape).keyEquivalent, "\u{1B}")
        XCTAssertEqual(KeyCombo(.upArrow).keyEquivalent, "\u{F700}")
        XCTAssertEqual(KeyCombo(.downArrow).keyEquivalent, "\u{F701}")
        XCTAssertEqual(KeyCombo(.leftArrow).keyEquivalent, "\u{F702}")
        XCTAssertEqual(KeyCombo(.rightArrow).keyEquivalent, "\u{F703}")
    }

    func testLooksUpShortcuts() {
        XCTAssertEqual(Shortcuts[.back].keys, [.command("[")])
        XCTAssertEqual(Shortcuts[.newFolder].title, "New Folder")
        XCTAssertEqual(Shortcuts[.viewMode(.columns)].keys, [.command("3")])
        XCTAssertEqual(Shortcuts[.layout(.grid)].keys, [.command("5", .option)])
        XCTAssertEqual(Shortcuts[.sort(.kind)].title, "Sort by Kind")
        XCTAssertEqual(Shortcuts[.sort(.kind)].keys, [.command("6", .control)])
    }

    func testFindsActionsBySection() {
        XCTAssertEqual(Shortcuts.action(for: KeyCombo(.returnKey), in: .browsing), .renameItem)
        XCTAssertEqual(Shortcuts.action(for: KeyCombo(.returnKey), in: .sidebar), .renameSidebarItem)
        XCTAssertEqual(Shortcuts.action(for: KeyCombo(.returnKey), in: .filter), .leaveFilter)
        XCTAssertEqual(Shortcuts.action(for: KeyCombo(.downArrow), in: .filter), .leaveFilter)
        XCTAssertEqual(Shortcuts.action(for: KeyCombo(.delete, .command), in: .sidebar), .removeSidebarItem)
        XCTAssertEqual(Shortcuts.action(for: KeyCombo(.rightArrow), in: .columns), .nextColumn)
        XCTAssertNil(Shortcuts.action(for: KeyCombo(.rightArrow, .shift), in: .columns))
        XCTAssertNil(Shortcuts.action(for: KeyCombo(.returnKey, .command), in: .browsing))
        XCTAssertNil(Shortcuts.action(for: KeyCombo(.character("a")), in: .browsing))
    }

    func testEveryShortcutHasKeysAndUniqueID() {
        XCTAssertTrue(Shortcuts.all.allSatisfy { !$0.keys.isEmpty && !$0.title.isEmpty })
        XCTAssertEqual(Set(Shortcuts.all.map(\.id)).count, Shortcuts.all.count)
        XCTAssertEqual(Shortcuts.all.filter { $0.section == .view }.count, ViewMode.allCases.count + PaneLayout.allCases.count + SortKey.allCases.count + 6)
    }

    func testKeysDoNotCollide() {
        let menuKeys = Shortcuts.all.filter(\.section.isMenu).flatMap(\.keys)
        XCTAssertEqual(Set(menuKeys).count, menuKeys.count)
        for section in Shortcut.Section.allCases where !section.isMenu {
            let keys = Shortcuts.all.filter { $0.section == section }.flatMap(\.keys)
            XCTAssertEqual(Set(keys).count, keys.count, section.rawValue)
        }
        let columnView = Shortcuts.all.filter { $0.section == .columns || $0.section == .browsing }.flatMap(\.keys)
        XCTAssertEqual(Set(columnView).count, columnView.count)
    }

    func testSectionsKeepMenuOrder() {
        let sections = Shortcuts.sections.map(\.section)
        XCTAssertEqual(sections, Shortcut.Section.allCases)
        XCTAssertEqual(Shortcuts.sections.first?.shortcuts.first?.id, .settings)
        XCTAssertTrue(Shortcut.Section.go.isMenu)
        XCTAssertFalse(Shortcut.Section.browsing.isMenu)
    }
}
