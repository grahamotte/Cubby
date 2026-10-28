import AppKit

enum Theme {
    nonisolated(unsafe) private(set) static var definition = ThemeLibrary.builtIn[0]

    static let content = color(.content)
    static let sidebar = color(.sidebar)
    static let card = color(.card)
    static let divider = color(.divider)
    static let text = color(.text)
    static let secondaryText = color(.secondaryText)
    static let tertiaryText = color(.tertiaryText)
    static let icon = color(.icon)
    static let sidebarText = color(.sidebarText)
    static let sidebarSecondaryText = color(.sidebarSecondaryText)
    static let accent = color(.accent)
    static let accentText = color(.accentText)
    static let warning = color(.warning)

    static let selection = NSColor(name: nil) { appearance in
        resolve(.accent, appearance).withAlphaComponent(0.2)
    }

    static let inactiveSelection = NSColor(name: nil) { appearance in
        let text = resolve(.text, appearance)
        return text.withAlphaComponent(text.alphaComponent * 0.1)
    }

    @MainActor
    static func apply(_ theme: ThemeDefinition, scheme: ColorScheme) {
        definition = theme
        switch scheme {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        for window in NSApp.windows {
            if let frame = window.contentView?.superview {
                refresh(frame)
            }
        }
    }

    static func nsColor(_ color: ThemeColor) -> NSColor {
        switch color {
        case .systemAccent:
            return .controlAccentColor
        case .rgba(let red, let green, let blue, let alpha):
            return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        }
    }

    private static func color(_ role: ThemeRole) -> NSColor {
        NSColor(name: nil) { appearance in resolve(role, appearance) }
    }

    private static func resolve(_ role: ThemeRole, _ appearance: NSAppearance) -> NSColor {
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return nsColor(definition.palette(dark: dark)[role])
    }

    @MainActor
    private static func refresh(_ view: NSView) {
        view.needsDisplay = true
        view.needsLayout = true
        view.subviews.forEach(refresh)
    }
}

final class ThemedSplitView: NSSplitView {
    override var dividerColor: NSColor { Theme.divider }
}

final class RoundedRowView: NSTableRowView {
    var horizontalInset: CGFloat = 6

    override func drawBackground(in dirtyRect: NSRect) {}

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        (isEmphasized ? Theme.selection : Theme.inactiveSelection).setFill()
        var rect = bounds.insetBy(dx: horizontalInset, dy: 0)
        if !isPreviousRowSelected {
            rect.origin.y += 1
            rect.size.height -= 1
        }
        if !isNextRowSelected {
            rect.size.height -= 1
        }
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        if isPreviousRowSelected {
            NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(6, rect.height)).fill()
        }
        if isNextRowSelected {
            NSRect(x: rect.minX, y: rect.maxY - min(6, rect.height), width: rect.width, height: min(6, rect.height)).fill()
        }
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

final class QuietHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.content.setFill()
        dirtyRect.fill()
        guard let table = tableView else { return }
        let ascending = table.sortDescriptors.first?.ascending ?? true
        for (index, column) in table.tableColumns.enumerated() where !column.isHidden {
            let rect = headerRect(ofColumn: index)
            guard rect.intersects(dirtyRect) else { continue }
            let active = table.indicatorImage(in: column) != nil
            let font = NSFont.systemFont(ofSize: 11, weight: .medium)
            let title = NSAttributedString(string: column.title, attributes: [
                .font: font,
                .foregroundColor: active ? Theme.text : Theme.secondaryText,
            ])
            let size = title.size()
            let configuration = NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold).applying(.init(paletteColors: [Theme.secondaryText]))
            let chevron = active ? NSImage(systemSymbolName: ascending ? "chevron.up" : "chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) : nil
            let chevronWidth = chevron.map { $0.size.width + 4 } ?? 0
            var inner = rect.insetBy(dx: 8, dy: 0)
            if table.numberOfRows > 0 {
                let cell = table.frameOfCell(atColumn: index, row: 0)
                inner = NSRect(x: cell.minX + 2, y: rect.minY, width: cell.width - 4, height: rect.height)
            }
            let width = min(size.width, inner.width - chevronWidth)
            let x = column.headerCell.alignment == .right ? inner.maxX - width - chevronWidth : inner.minX
            let y = rect.midY - size.height / 2
            title.draw(with: NSRect(x: x, y: y, width: width, height: size.height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            chevron?.draw(in: NSRect(x: x + width + 4, y: rect.midY - chevron!.size.height / 2, width: chevron!.size.width, height: chevron!.size.height))
        }
        Theme.divider.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
}
