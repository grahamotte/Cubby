import AppKit

@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu("Cubby", appMenu()))
        main.addItem(submenu("File", fileMenu()))
        main.addItem(submenu("Edit", editMenu()))
        main.addItem(submenu("View", viewMenu()))
        main.addItem(submenu("Go", goMenu()))
        let window = windowMenu()
        main.addItem(submenu("Window", window))
        NSApp.windowsMenu = window
        let help = NSMenu(title: "Help")
        main.addItem(submenu("Help", help))
        NSApp.helpMenu = help
        return main
    }

    private static func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        menu.title = title
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.tag = tag
        return item
    }

    private static func add(_ id: ShortcutID, _ action: Selector?, to menu: NSMenu, title: String? = nil, tag: Int = 0, represented: Any? = nil) {
        let shortcut = Shortcuts[id]
        for (index, combo) in shortcut.keys.enumerated() {
            let item = NSMenuItem(title: title ?? shortcut.title, action: action, keyEquivalent: combo.keyEquivalent)
            item.keyEquivalentModifierMask = combo.modifiers.flags
            item.tag = tag
            item.representedObject = represented
            if index > 0 {
                item.isHidden = true
                item.allowsKeyEquivalentWhenHidden = true
            }
            menu.addItem(item)
        }
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("About Cubby", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        add(.settings, #selector(BrowserWindowController.showSettings(_:)), to: menu)
        menu.addItem(item("Open Config File…", #selector(AppDelegate.openConfigFile(_:))))
        menu.addItem(.separator())
        let services = NSMenu()
        menu.addItem(submenu("Services", services))
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        add(.hideCubby, #selector(NSApplication.hide(_:)), to: menu)
        add(.hideOthers, #selector(NSApplication.hideOtherApplications(_:)), to: menu)
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        add(.quit, #selector(NSApplication.terminate(_:)), to: menu)
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu()
        add(.newWindow, #selector(AppDelegate.newWindow(_:)), to: menu)
        add(.newFolder, #selector(PaneController.newFolder(_:)), to: menu)
        add(.newFolderWithSelection, #selector(PaneController.newFolderWithSelection(_:)), to: menu)
        add(.newTextFile, #selector(PaneController.newFile(_:)), to: menu)
        menu.addItem(.separator())
        add(.open, #selector(PaneController.openSelection(_:)), to: menu)
        add(.closeWindow, #selector(NSWindow.performClose(_:)), to: menu)
        menu.addItem(.separator())
        menu.addItem(item("Rename", #selector(PaneController.renameSelection(_:))))
        add(.duplicate, #selector(PaneController.duplicate(_:)), to: menu)
        menu.addItem(item("Compress", #selector(PaneController.compress(_:))))
        add(.moveToTrash, #selector(PaneController.moveToTrash(_:)), to: menu)
        menu.addItem(.separator())
        add(.quickLook, #selector(PaneController.quickLook(_:)), to: menu)
        add(.showInFinder, #selector(PaneController.showInFinder(_:)), to: menu)
        add(.openInTerminal, #selector(PaneController.openInTerminal(_:)), to: menu)
        add(.addToSidebar, #selector(PaneController.addToSidebar(_:)), to: menu)
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu()
        add(.undo, Selector(("undo:")), to: menu)
        add(.redo, Selector(("redo:")), to: menu)
        menu.addItem(.separator())
        add(.cut, #selector(NSText.cut(_:)), to: menu)
        add(.copy, #selector(NSText.copy(_:)), to: menu)
        add(.copyPath, #selector(PaneController.copyPath(_:)), to: menu)
        add(.paste, #selector(NSText.paste(_:)), to: menu)
        add(.moveItemHere, #selector(PaneController.pasteAndMove(_:)), to: menu)
        add(.selectAll, #selector(NSText.selectAll(_:)), to: menu)
        menu.addItem(.separator())
        add(.filter, #selector(BrowserWindowController.performFindPanelAction(_:)), to: menu)
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu()
        for (index, mode) in ViewMode.allCases.enumerated() {
            add(.viewMode(mode), #selector(PaneController.setViewMode(_:)), to: menu, tag: index)
        }
        menu.addItem(.separator())
        let layouts = NSMenu()
        for (index, layout) in PaneLayout.allCases.enumerated() {
            add(.layout(layout), #selector(BrowserWindowController.changeLayout(_:)), to: layouts, tag: index)
        }
        menu.addItem(submenu("Layout", layouts))
        let sort = NSMenu()
        for (index, key) in SortKey.allCases.enumerated() {
            add(.sort(key), #selector(PaneController.sortBy(_:)), to: sort, title: key.title, tag: index)
        }
        menu.addItem(submenu("Sort By", sort))
        add(.biggerIcons, #selector(PaneController.biggerIcons(_:)), to: menu)
        add(.smallerIcons, #selector(PaneController.smallerIcons(_:)), to: menu)
        menu.addItem(.separator())
        add(.showHiddenFiles, #selector(AppDelegate.toggleHiddenFiles(_:)), to: menu)
        add(.reload, #selector(PaneController.refresh(_:)), to: menu)
        menu.addItem(.separator())
        add(.toggleSidebar, #selector(BrowserWindowController.toggleSidebarVisibility(_:)), to: menu)
        add(.fullScreen, #selector(NSWindow.toggleFullScreen(_:)), to: menu)
        return menu
    }

    private static func goMenu() -> NSMenu {
        let menu = NSMenu()
        add(.back, #selector(PaneController.goBack(_:)), to: menu)
        add(.forward, #selector(PaneController.goForward(_:)), to: menu)
        add(.enclosingFolder, #selector(PaneController.goToEnclosingFolder(_:)), to: menu)
        menu.addItem(.separator())
        let home = NSHomeDirectory()
        let locations: [(ShortcutID, String)] = [
            (.home, home),
            (.desktop, home + "/Desktop"),
            (.documents, home + "/Documents"),
            (.downloads, home + "/Downloads"),
            (.applications, "/Applications"),
            (.computer, "/"),
        ]
        for (id, path) in locations {
            add(id, #selector(BrowserWindowController.goToLocation(_:)), to: menu, represented: path)
        }
        menu.addItem(.separator())
        add(.goToFolder, #selector(BrowserWindowController.goToFolder(_:)), to: menu)
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu()
        add(.minimize, #selector(NSWindow.performMiniaturize(_:)), to: menu)
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}

extension KeyCombo {
    init?(event: NSEvent) {
        let key: Key
        switch event.keyCode {
        case 36, 76: key = .returnKey
        case 49: key = .space
        case 48: key = .tab
        case 51: key = .delete
        case 117: key = .forwardDelete
        case 53: key = .escape
        case 126: key = .upArrow
        case 125: key = .downArrow
        case 123: key = .leftArrow
        case 124: key = .rightArrow
        default:
            guard let characters = event.charactersIgnoringModifiers?.lowercased(), !characters.isEmpty else { return nil }
            key = .character(characters)
        }
        self.init(key, Modifiers(event.modifierFlags))
    }
}

extension KeyCombo.Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
    }

    var flags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.control) { flags.insert(.control) }
        if contains(.option) { flags.insert(.option) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.command) { flags.insert(.command) }
        return flags
    }
}
