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
            controller.activePane.navigate(to: (parts[1] as NSString).deletingLastPathComponent, select: Set(parts.dropFirst().map { ($0 as NSString).lastPathComponent }))
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
            if !NSApp.sendAction(Selector(parts[1]), to: nil, from: nil) {
                _ = controller.window?.firstResponder?.tryToPerform(Selector(parts[1]), with: nil)
            }
        case "type":
            guard let editor = controller.window?.firstResponder as? NSTextView else { return }
            editor.selectAll(nil)
            editor.insertText(parts[1], replacementRange: editor.selectedRange())
            editor.insertNewline(nil)
        case "sidebar":
            _ = controller.sidebar.tryToPerform(Selector(parts[1]), with: nil)
        case "key":
            guard let window = controller.window, let code = UInt16(parts[1]) else { return }
            let modifiers = parts.count > 2 ? parts[2] : ""
            var flags: NSEvent.ModifierFlags = []
            if modifiers.contains("c") { flags.insert(.command) }
            if modifiers.contains("s") { flags.insert(.shift) }
            if modifiers.contains("o") { flags.insert(.option) }
            if modifiers.contains("t") { flags.insert(.control) }
            let arrows: [UInt16: Int] = [126: NSUpArrowFunctionKey, 125: NSDownArrowFunctionKey, 123: NSLeftArrowFunctionKey, 124: NSRightArrowFunctionKey]
            if arrows[code] != nil { flags.formUnion([.function, .numericPad]) }
            let characters = arrows[code].flatMap { UnicodeScalar($0) }.map { String(Character($0)) } ?? (parts.count > 3 ? parts[3] : "")
            window.makeKeyAndOrderFront(nil)
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { continue }
                NSApp.postEvent(event, atStart: false)
            }
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
