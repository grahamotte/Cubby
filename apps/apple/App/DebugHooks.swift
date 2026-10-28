#if CUBBY_DEV
import AppKit

@MainActor
enum DebugHooks {
    static func install() {
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("cubby.debug"), object: nil, queue: .main) { note in
            let command = note.object as? String ?? ""
            MainActor.assumeIsolated { run(command) }
        }
    }

    static func run(_ command: String) {
        let parts = command.components(separatedBy: "|")
        guard let controller = NSApp.orderedWindows.compactMap({ $0.windowController as? BrowserWindowController }).first else { return }
        switch parts[0] {
        case "snap":
            let target = parts.count > 2 ? NSApp.windows.first { $0.title == parts[2] } : controller.window
            guard let window = target, let view = window.contentView?.superview else { return }
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: parts[1]))
        case "go":
            controller.activePane.navigate(to: parts[1])
        case "mode":
            controller.activePane.setMode(ViewMode(rawValue: parts[1]) ?? .list)
        case "layout":
            controller.setLayout(PaneLayout(rawValue: parts[1]) ?? .single)
        case "select":
            controller.activePane.navigate(to: (parts[1] as NSString).deletingLastPathComponent, select: [(parts[1] as NSString).lastPathComponent])
        case "frame":
            controller.window?.setFrame(NSRect(x: 100, y: 100, width: Double(parts[1]) ?? 1100, height: Double(parts[2]) ?? 700), display: true)
        case "time":
            let start = Date()
            controller.activePane.navigate(to: parts[1])
            let pane = controller.activePane
            func check() {
                if pane.model.isLoaded {
                    try? "\(Date().timeIntervalSince(start)) \(pane.model.items.count)".write(toFile: parts[2], atomically: true, encoding: .utf8)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: check)
                }
            }
            check()
        case "action":
            NSApp.sendAction(Selector(parts[1]), to: nil, from: nil)
        case "type":
            guard let editor = controller.window?.firstResponder as? NSTextView else { return }
            editor.selectAll(nil)
            editor.insertText(parts[1], replacementRange: editor.selectedRange())
            editor.insertNewline(nil)
        case "profile":
            AppState.shared.selectProfile(Int(parts[1]) ?? 0)
        case "undo":
            AppState.shared.undoManager.undo()
        case "focus":
            controller.activePane.activate()
        default:
            break
        }
    }
}
#endif
