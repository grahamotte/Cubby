import Foundation

struct KeyCombo: Hashable {
    struct Modifiers: OptionSet, Hashable {
        let rawValue: Int

        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)
    }

    enum Key: Hashable {
        case character(String)
        case returnKey
        case space
        case tab
        case delete
        case forwardDelete
        case escape
        case upArrow
        case downArrow
        case leftArrow
        case rightArrow
    }

    let key: Key
    let modifiers: Modifiers

    init(_ key: Key, _ modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    static func command(_ character: String, _ extra: Modifiers = []) -> KeyCombo {
        KeyCombo(.character(character), extra.union(.command))
    }

    var keyEquivalent: String {
        switch key {
        case .character(let character): character
        case .returnKey: "\r"
        case .space: " "
        case .tab: "\t"
        case .delete: "\u{8}"
        case .forwardDelete: "\u{7F}"
        case .escape: "\u{1B}"
        case .upArrow: "\u{F700}"
        case .downArrow: "\u{F701}"
        case .leftArrow: "\u{F702}"
        case .rightArrow: "\u{F703}"
        }
    }

    var display: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + keyName
    }

    private var keyName: String {
        switch key {
        case .character(let character): character.uppercased()
        case .returnKey: "↩"
        case .space: "Space"
        case .tab: "⇥"
        case .delete: "⌫"
        case .forwardDelete: "⌦"
        case .escape: "⎋"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .leftArrow: "←"
        case .rightArrow: "→"
        }
    }
}

enum ShortcutID: Hashable {
    case settings, hideCubby, hideOthers, quit
    case newWindow, newFolder, newFolderWithSelection, newTextFile, open, closeWindow, duplicate, moveToTrash, quickLook, showInFinder, openInTerminal, addToSidebar
    case undo, redo, cut, copy, copyPath, paste, moveItemHere, selectAll, filter
    case viewMode(ViewMode), layout(PaneLayout), sort(SortKey)
    case biggerIcons, smallerIcons, showHiddenFiles, reload, toggleSidebar, fullScreen
    case back, forward, enclosingFolder, home, desktop, documents, downloads, applications, computer, goToFolder
    case minimize
    case renameItem, previewItem, nextPane, openItem
    case nextColumn, previousColumn
    case renameSidebarItem, removeSidebarItem
    case leaveFilter, clearFilter
    case closeSettings
}

struct Shortcut {
    enum Section: String, CaseIterable {
        case app = "Cubby"
        case file = "File"
        case edit = "Edit"
        case view = "View"
        case go = "Go"
        case window = "Window"
        case browsing = "Browsing"
        case columns = "Column View"
        case sidebar = "Sidebar"
        case filter = "Filter"
        case settings = "Settings"

        var isMenu: Bool {
            switch self {
            case .app, .file, .edit, .view, .go, .window: true
            case .browsing, .columns, .sidebar, .filter, .settings: false
            }
        }
    }

    let id: ShortcutID
    let title: String
    let section: Section
    let keys: [KeyCombo]

    init(_ id: ShortcutID, _ title: String, _ section: Section, _ keys: KeyCombo...) {
        self.id = id
        self.title = title
        self.section = section
        self.keys = keys
    }
}

enum Shortcuts {
    static let all: [Shortcut] = {
        var list: [Shortcut] = [
            Shortcut(.settings, "Settings…", .app, .command(",")),
            Shortcut(.hideCubby, "Hide Cubby", .app, .command("h")),
            Shortcut(.hideOthers, "Hide Others", .app, .command("h", .option)),
            Shortcut(.quit, "Quit Cubby", .app, .command("q")),

            Shortcut(.newWindow, "New Window", .file, .command("n")),
            Shortcut(.newFolder, "New Folder", .file, .command("n", .shift)),
            Shortcut(.newFolderWithSelection, "New Folder with Selection", .file, .command("n", .control)),
            Shortcut(.newTextFile, "New Text File", .file, .command("n", .option)),
            Shortcut(.open, "Open", .file, .command("o")),
            Shortcut(.closeWindow, "Close Window", .file, .command("w")),
            Shortcut(.duplicate, "Duplicate", .file, .command("d")),
            Shortcut(.moveToTrash, "Move to Trash", .file, KeyCombo(.delete, .command)),
            Shortcut(.quickLook, "Quick Look", .file, .command("y")),
            Shortcut(.showInFinder, "Show in Finder", .file, .command("r", .option)),
            Shortcut(.openInTerminal, "Open in Terminal", .file, .command("t", .option)),
            Shortcut(.addToSidebar, "Add to Sidebar", .file, .command("t", .control)),

            Shortcut(.undo, "Undo", .edit, .command("z")),
            Shortcut(.redo, "Redo", .edit, .command("z", .shift)),
            Shortcut(.cut, "Cut", .edit, .command("x")),
            Shortcut(.copy, "Copy", .edit, .command("c")),
            Shortcut(.copyPath, "Copy Path", .edit, .command("c", .option)),
            Shortcut(.paste, "Paste", .edit, .command("v")),
            Shortcut(.moveItemHere, "Move Item Here", .edit, .command("v", .option)),
            Shortcut(.selectAll, "Select All", .edit, .command("a")),
            Shortcut(.filter, "Filter", .edit, .command("f")),
        ]
        for (index, mode) in ViewMode.allCases.enumerated() {
            list.append(Shortcut(.viewMode(mode), "as \(mode.title)", .view, .command("\(index + 1)")))
        }
        for (index, layout) in PaneLayout.allCases.enumerated() {
            list.append(Shortcut(.layout(layout), layout.title, .view, .command("\(index + 1)", .option)))
        }
        for (index, key) in SortKey.allCases.enumerated() {
            list.append(Shortcut(.sort(key), "Sort by \(key.title)", .view, .command("\(index + 1)", .control)))
        }
        list += [
            Shortcut(.biggerIcons, "Bigger Icons", .view, .command("+")),
            Shortcut(.smallerIcons, "Smaller Icons", .view, .command("-")),
            Shortcut(.showHiddenFiles, "Show Hidden Files", .view, .command(".", .shift)),
            Shortcut(.reload, "Reload", .view, .command("r")),
            Shortcut(.toggleSidebar, "Toggle Sidebar", .view, .command("s", .control)),
            Shortcut(.fullScreen, "Enter Full Screen", .view, .command("f", .control)),

            Shortcut(.back, "Back", .go, .command("["), KeyCombo(.leftArrow, .command)),
            Shortcut(.forward, "Forward", .go, .command("]"), KeyCombo(.rightArrow, .command)),
            Shortcut(.enclosingFolder, "Enclosing Folder", .go, KeyCombo(.upArrow, .command)),
            Shortcut(.home, "Home", .go, .command("h", .shift)),
            Shortcut(.desktop, "Desktop", .go, .command("d", .shift)),
            Shortcut(.documents, "Documents", .go, .command("o", .shift)),
            Shortcut(.downloads, "Downloads", .go, .command("l", .option)),
            Shortcut(.applications, "Applications", .go, .command("a", .shift)),
            Shortcut(.computer, "Computer", .go, .command("c", .shift)),
            Shortcut(.goToFolder, "Go to Folder…", .go, .command("g", .shift)),

            Shortcut(.minimize, "Minimize", .window, .command("m")),

            Shortcut(.renameItem, "Rename", .browsing, KeyCombo(.returnKey)),
            Shortcut(.previewItem, "Quick Look", .browsing, KeyCombo(.space)),
            Shortcut(.openItem, "Open", .browsing, KeyCombo(.downArrow, .command)),
            Shortcut(.nextPane, "Next Pane", .browsing, KeyCombo(.tab)),

            Shortcut(.nextColumn, "Next Column", .columns, KeyCombo(.rightArrow)),
            Shortcut(.previousColumn, "Previous Column", .columns, KeyCombo(.leftArrow)),

            Shortcut(.renameSidebarItem, "Rename", .sidebar, KeyCombo(.returnKey)),
            Shortcut(.removeSidebarItem, "Remove from Sidebar", .sidebar, KeyCombo(.delete), KeyCombo(.forwardDelete), KeyCombo(.delete, .command)),

            Shortcut(.leaveFilter, "Move to Files", .filter, KeyCombo(.returnKey), KeyCombo(.downArrow)),
            Shortcut(.clearFilter, "Clear Filter", .filter, KeyCombo(.escape)),

            Shortcut(.closeSettings, "Close Settings", .settings, KeyCombo(.escape)),
        ]
        return list
    }()

    private static let byID: [ShortcutID: Shortcut] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static subscript(_ id: ShortcutID) -> Shortcut {
        byID[id]!
    }

    static func action(for combo: KeyCombo, in section: Shortcut.Section) -> ShortcutID? {
        all.first { $0.section == section && $0.keys.contains(combo) }?.id
    }

    static var sections: [(section: Shortcut.Section, shortcuts: [Shortcut])] {
        Shortcut.Section.allCases.compactMap { section in
            let shortcuts = all.filter { $0.section == section }
            return shortcuts.isEmpty ? nil : (section, shortcuts)
        }
    }
}
