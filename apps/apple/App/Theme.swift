import AppKit

enum Theme {
    static let content = dynamic(light: NSColor(srgbRed: 0.988, green: 0.988, blue: 0.984, alpha: 1), dark: NSColor(srgbRed: 0.118, green: 0.122, blue: 0.129, alpha: 1))
    static let sidebar = dynamic(light: NSColor(srgbRed: 0.945, green: 0.945, blue: 0.937, alpha: 1), dark: NSColor(srgbRed: 0.090, green: 0.094, blue: 0.102, alpha: 1))
    static let card = dynamic(light: .white, dark: NSColor(srgbRed: 0.157, green: 0.161, blue: 0.169, alpha: 1))
    static let divider = dynamic(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.07))
    static let hover = dynamic(light: NSColor(white: 0, alpha: 0.04), dark: NSColor(white: 1, alpha: 0.05))
    static let inactiveSelection = dynamic(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.09))

    static var selection: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(0.2)
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
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
                .foregroundColor: active ? NSColor.labelColor : NSColor.secondaryLabelColor,
            ])
            let size = title.size()
            let configuration = NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold).applying(.init(paletteColors: [.secondaryLabelColor]))
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
