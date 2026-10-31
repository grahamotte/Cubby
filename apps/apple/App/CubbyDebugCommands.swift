#if APP_DEV && os(macOS)
import AppKit

@MainActor
enum CubbyDebugCommands {
    static func run(_ name: String, _ arguments: [String]) throws {
        guard let controller = NSApp.orderedWindows.compactMap({ $0.windowController as? BrowserWindowController }).first else { throw DebugHooks.Failure("no browser window") }
        switch name {
        case "go":
            controller.activePane.navigate(to: try argument(arguments, 0))
        case "mode":
            controller.activePane.setMode(ViewMode(rawValue: try argument(arguments, 0)) ?? .list)
        case "layout":
            controller.setLayout(PaneLayout(rawValue: try argument(arguments, 0)) ?? .single)
        case "select":
            let paths = arguments.filter { !$0.isEmpty }
            guard let first = paths.first else { throw DebugHooks.Failure("select needs a path") }
            controller.activePane.navigate(to: (first as NSString).deletingLastPathComponent, select: Set(paths.map { ($0 as NSString).lastPathComponent }))
        case "time":
            let path = try argument(arguments, 0)
            let output = try argument(arguments, 1)
            let start = Date()
            controller.activePane.navigate(to: path)
            let pane = controller.activePane
            func check() {
                if pane.model.isLoaded {
                    try? "\(Date().timeIntervalSince(start)) \(pane.model.items.count)".write(toFile: output, atomically: true, encoding: .utf8)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: check)
                }
            }
            check()
        case "move", "copy":
            let destination = try argument(arguments, 0)
            FileActions.transfer(arguments.dropFirst().map { URL(filePath: $0) }, to: URL(filePath: destination, directoryHint: .isDirectory), copy: name == "copy")
        case "sidebar":
            let selector = try argument(arguments, 0)
            guard controller.sidebar.tryToPerform(Selector(selector), with: nil) else { throw DebugHooks.Failure("sidebar did not handle \(selector)") }
        case "profile":
            AppState.shared.selectProfile(Int(try argument(arguments, 0)) ?? 0)
        case "undo":
            AppState.shared.undoManager.undo()
        case "focus":
            controller.activePane.activate()
        default:
            throw DebugHooks.Failure("unknown command \(name)")
        }
    }

    private static func argument(_ arguments: [String], _ index: Int) throws -> String {
        guard arguments.count > index, !arguments[index].isEmpty else { throw DebugHooks.Failure("missing argument \(index + 1)") }
        return arguments[index]
    }
}
#endif
