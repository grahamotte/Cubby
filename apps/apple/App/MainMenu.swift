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

    private static func item(_ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0, represented: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.tag = tag
        item.representedObject = represented
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("About Cubby", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Open Config File…", #selector(AppDelegate.openConfigFile(_:)), ","))
        menu.addItem(.separator())
        let services = NSMenu()
        menu.addItem(submenu("Services", services))
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(item("Hide Cubby", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Cubby", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("New Window", #selector(AppDelegate.newWindow(_:)), "n"))
        menu.addItem(item("New Tab", #selector(AppDelegate.newTab(_:)), "t"))
        menu.addItem(item("New Folder", #selector(PaneController.newFolder(_:)), "n", [.command, .shift]))
        menu.addItem(item("New Folder with Selection", #selector(PaneController.newFolderWithSelection(_:)), "n", [.command, .control]))
        menu.addItem(item("New Text File", #selector(PaneController.newFile(_:)), "n", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Open", #selector(PaneController.openSelection(_:)), "o"))
        menu.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(.separator())
        menu.addItem(item("Rename", #selector(PaneController.renameSelection(_:))))
        menu.addItem(item("Duplicate", #selector(PaneController.duplicate(_:)), "d"))
        menu.addItem(item("Compress", #selector(PaneController.compress(_:))))
        menu.addItem(item("Move to Trash", #selector(PaneController.moveToTrash(_:)), "\u{8}"))
        menu.addItem(.separator())
        menu.addItem(item("Quick Look", #selector(PaneController.quickLook(_:)), "y"))
        menu.addItem(item("Show in Finder", #selector(PaneController.showInFinder(_:)), "r", [.command, .option]))
        menu.addItem(item("Open in Terminal", #selector(PaneController.openInTerminal(_:)), "t", [.command, .option]))
        menu.addItem(item("Add to Sidebar", #selector(PaneController.addToSidebar(_:)), "t", [.command, .control]))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Copy Path", #selector(PaneController.copyPath(_:)), "c", [.command, .option]))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Move Item Here", #selector(PaneController.pasteAndMove(_:)), "v", [.command, .option]))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())
        menu.addItem(item("Filter", #selector(BrowserWindowController.performFindPanelAction(_:)), "f"))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu()
        for (index, mode) in ViewMode.allCases.enumerated() {
            menu.addItem(item("as \(mode.title)", #selector(PaneController.setViewMode(_:)), "\(index + 1)", tag: index))
        }
        menu.addItem(.separator())
        let layouts = NSMenu()
        for (index, layout) in PaneLayout.allCases.enumerated() {
            layouts.addItem(item(layout.title, #selector(BrowserWindowController.changeLayout(_:)), "\(index + 1)", [.command, .option], tag: index))
        }
        menu.addItem(submenu("Layout", layouts))
        let sort = NSMenu()
        for (index, key) in SortKey.allCases.enumerated() {
            sort.addItem(item(key.title, #selector(PaneController.sortBy(_:)), "\(index + 1)", [.command, .control], tag: index))
        }
        menu.addItem(submenu("Sort By", sort))
        menu.addItem(item("Bigger Icons", #selector(PaneController.biggerIcons(_:)), "+"))
        menu.addItem(item("Smaller Icons", #selector(PaneController.smallerIcons(_:)), "-"))
        menu.addItem(.separator())
        menu.addItem(item("Show Hidden Files", #selector(AppDelegate.toggleHiddenFiles(_:)), ".", [.command, .shift]))
        menu.addItem(item("Reload", #selector(PaneController.refresh(_:)), "r"))
        menu.addItem(.separator())
        menu.addItem(item("Toggle Sidebar", #selector(BrowserWindowController.toggleSidebarVisibility(_:)), "s", [.command, .control]))
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func goMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Back", #selector(PaneController.goBack(_:)), "["))
        menu.addItem(item("Forward", #selector(PaneController.goForward(_:)), "]"))
        menu.addItem(item("Enclosing Folder", #selector(PaneController.goToEnclosingFolder(_:)), String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))))
        menu.addItem(.separator())
        let home = NSHomeDirectory()
        let locations: [(String, String, String, NSEvent.ModifierFlags)] = [
            ("Home", home, "h", [.command, .shift]),
            ("Desktop", home + "/Desktop", "d", [.command, .shift]),
            ("Documents", home + "/Documents", "o", [.command, .shift]),
            ("Downloads", home + "/Downloads", "l", [.command, .option]),
            ("Applications", "/Applications", "a", [.command, .shift]),
            ("Computer", "/", "c", [.command, .shift]),
        ]
        for (title, path, key, modifiers) in locations {
            menu.addItem(item(title, #selector(BrowserWindowController.goToLocation(_:)), key, modifiers, represented: path))
        }
        menu.addItem(.separator())
        menu.addItem(item("Go to Folder…", #selector(BrowserWindowController.goToFolder(_:)), "g", [.command, .shift]))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Show Previous Tab", #selector(NSWindow.selectPreviousTab(_:)), "\t", [.control, .shift]))
        menu.addItem(item("Show Next Tab", #selector(NSWindow.selectNextTab(_:)), "\t", [.control]))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}
