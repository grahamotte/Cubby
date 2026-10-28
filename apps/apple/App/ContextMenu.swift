import AppKit
import UniformTypeIdentifiers

@MainActor
enum ContextMenu {
    static func build(for items: [FileItem], in directory: URL, pane: PaneController) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, _ action: Selector, symbol: String? = nil, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = pane
            item.isEnabled = enabled
            if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            menu.addItem(item)
        }
        let hasPaste = !FileActions.pasteboardURLs().isEmpty

        if items.isEmpty {
            add("New Folder", #selector(PaneController.newFolder(_:)), symbol: "folder.badge.plus")
            add("New Text File", #selector(PaneController.newFile(_:)), symbol: "doc.badge.plus")
            menu.addItem(.separator())
            add("Paste", #selector(PaneController.paste(_:)), symbol: "doc.on.clipboard", enabled: hasPaste)
            menu.addItem(.separator())
            add("Open in Terminal", #selector(PaneController.openInTerminal(_:)), symbol: "terminal")
            add("Copy Path", #selector(PaneController.copyPath(_:)), symbol: "link")
            add("Show in Finder", #selector(PaneController.showInFinder(_:)), symbol: "macwindow")
            add("Add to Sidebar", #selector(PaneController.addToSidebar(_:)), symbol: "sidebar.left")
            menu.addItem(.separator())
            menu.addItem(viewMenu(pane))
            menu.addItem(sortMenu(pane))
            let hidden = NSMenuItem(title: "Show Hidden Files", action: #selector(AppDelegate.toggleHiddenFiles(_:)), keyEquivalent: "")
            hidden.state = AppState.shared.showHiddenFiles ? .on : .off
            menu.addItem(hidden)
            return menu
        }

        let single = items.count == 1 ? items[0] : nil
        add("Open", #selector(PaneController.openSelection(_:)))
        if let single, !single.isFolder {
            menu.addItem(openWithMenu(single.url))
        }
        if let single, single.isPackage {
            add("Show Package Contents", #selector(PaneController.showPackageContents(_:)))
        }
        menu.addItem(.separator())
        add("Open in Terminal", #selector(PaneController.openInTerminal(_:)), symbol: "terminal")
        add("Show in Finder", #selector(PaneController.showInFinder(_:)), symbol: "macwindow")
        menu.addItem(.separator())
        add("Move to Trash", #selector(PaneController.moveToTrash(_:)), symbol: "trash")
        menu.addItem(.separator())
        add("Rename", #selector(PaneController.renameSelection(_:)), symbol: "pencil", enabled: single != nil)
        add("Duplicate", #selector(PaneController.duplicate(_:)), symbol: "plus.square.on.square")
        add("Compress", #selector(PaneController.compress(_:)), symbol: "archivebox")
        add("Quick Look", #selector(PaneController.quickLook(_:)), symbol: "eye")
        let share = NSMenuItem(title: "Share…", action: #selector(PaneController.share(_:)), keyEquivalent: "")
        share.target = pane
        share.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        menu.addItem(share)
        menu.addItem(.separator())
        add("Cut", #selector(PaneController.cut(_:)), symbol: "scissors")
        add("Copy", #selector(PaneController.copy(_:)), symbol: "doc.on.doc")
        add("Copy Path", #selector(PaneController.copyPath(_:)), symbol: "link")
        add("Paste", #selector(PaneController.paste(_:)), symbol: "doc.on.clipboard", enabled: hasPaste)
        menu.addItem(.separator())
        add("New Folder", #selector(PaneController.newFolder(_:)), symbol: "folder.badge.plus")
        add("New Folder with Selection", #selector(PaneController.newFolderWithSelection(_:)))
        if items.contains(where: \.isFolder) {
            menu.addItem(.separator())
            add("Add to Sidebar", #selector(PaneController.addToSidebar(_:)), symbol: "sidebar.left")
        }
        return menu
    }

    static func openWithMenu(_ url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let workspace = NSWorkspace.shared
        let defaultApp = workspace.urlForApplication(toOpen: url)
        var apps = workspace.urlsForApplications(toOpen: url)
        if let defaultApp {
            apps.removeAll { $0 == defaultApp }
            apps.insert(defaultApp, at: 0)
        }
        var seen = Set<String>()
        for (index, app) in apps.enumerated() {
            let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
            guard seen.insert(name).inserted else { continue }
            let entry = NSMenuItem(title: index == 0 && defaultApp != nil ? "\(name) (default)" : name, action: #selector(OpenWithTarget.open(_:)), keyEquivalent: "")
            entry.target = OpenWithTarget.shared
            entry.representedObject = [url, app]
            let icon = workspace.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            entry.image = icon
            submenu.addItem(entry)
            if index == 0 && defaultApp != nil && apps.count > 1 {
                submenu.addItem(.separator())
            }
        }
        if apps.isEmpty {
            submenu.addItem(NSMenuItem(title: "No Applications", action: nil, keyEquivalent: ""))
        }
        submenu.addItem(.separator())
        let other = NSMenuItem(title: "Other…", action: #selector(OpenWithTarget.chooseOther(_:)), keyEquivalent: "")
        other.target = OpenWithTarget.shared
        other.representedObject = [url]
        submenu.addItem(other)
        item.submenu = submenu
        return item
    }

    static func viewMenu(_ pane: PaneController) -> NSMenuItem {
        let item = NSMenuItem(title: "View As", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (index, mode) in ViewMode.allCases.enumerated() {
            let entry = NSMenuItem(title: mode.title, action: #selector(PaneController.setViewMode(_:)), keyEquivalent: "")
            entry.tag = index
            entry.target = pane
            entry.state = pane.folderView.mode == mode ? .on : .off
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    static func sortMenu(_ pane: PaneController) -> NSMenuItem {
        let item = NSMenuItem(title: "Sort By", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (index, key) in SortKey.allCases.enumerated() {
            let entry = NSMenuItem(title: key.title, action: #selector(PaneController.sortBy(_:)), keyEquivalent: "")
            entry.tag = index
            entry.target = pane
            entry.state = pane.folderView.sort == key ? .on : .off
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }
}

@MainActor
final class OpenWithTarget: NSObject {
    static let shared = OpenWithTarget()

    @objc func open(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [URL], pair.count == 2 else { return }
        NSWorkspace.shared.open([pair[0]], withApplicationAt: pair[1], configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func chooseOther(_ sender: NSMenuItem) {
        guard let url = (sender.representedObject as? [URL])?.first else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let app = panel.url else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
