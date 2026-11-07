import AppKit

final class FillView: NSView {
    var color: NSColor = Theme.content {
        didSet { needsDisplay = true }
    }

    var cornerRadius: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        if cornerRadius > 0 {
            NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        } else {
            bounds.intersection(dirtyRect).fill(using: .sourceOver)
        }
    }
}

enum PlainButton {
    static func make(_ symbol: String, _ description: String, target: AnyObject?, action: Selector?) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: description)!, target: target, action: action)
        button.isBordered = false
        button.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        button.contentTintColor = Theme.icon
        button.toolTip = description
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])
        return button
    }
}

final class TopBar: NSView {
    let searchField = ThemedSearchField()
    var onNavigate: ((String) -> Void)?
    private let crumbs = CrumbsView()
    private lazy var filterButton = PlainButton.make("magnifyingglass", "Filter", target: nil, action: #selector(BrowserWindowController.performFindPanelAction(_:)))
    private lazy var sortButton = PlainButton.make("arrow.up.arrow.down", "Sort", target: self, action: #selector(showSortMenu(_:)))
    private lazy var modeButton = PlainButton.make(ViewMode.list.symbolName, "View", target: self, action: #selector(showModeMenu(_:)))
    private lazy var layoutButton = PlainButton.make(PaneLayout.single.symbolName, "Layout", target: self, action: #selector(showLayoutMenu(_:)))

    var path = "" {
        didSet { if path != oldValue { rebuildCrumbs() } }
    }

    var mode: ViewMode = .list {
        didSet { modeButton.image = NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: mode.title) }
    }

    var layout: PaneLayout = .single {
        didSet { layoutButton.image = NSImage(systemSymbolName: layout.symbolName, accessibilityDescription: layout.title) }
    }

    var isFilterVisible: Bool {
        get { !searchField.isHidden }
        set { searchField.isHidden = !newValue }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        crumbs.translatesAutoresizingMaskIntoConstraints = false

        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        searchField.placeholderString = "Filter"
        searchField.sendsSearchStringImmediately = true
        searchField.focusRingType = .none
        searchField.isHidden = true
        searchField.widthAnchor.constraint(equalToConstant: 180).isActive = true

        let controls = NSStackView(views: [searchField, filterButton, sortButton, modeButton, layoutButton])
        controls.orientation = .horizontal
        controls.spacing = 2
        controls.setCustomSpacing(6, after: searchField)
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.setHuggingPriority(.required, for: .horizontal)

        addSubview(crumbs)
        addSubview(controls)
        NSLayoutConstraint.activate([
            crumbs.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            crumbs.centerYAnchor.constraint(equalTo: centerYAnchor),
            crumbs.trailingAnchor.constraint(lessThanOrEqualTo: controls.leadingAnchor, constant: -12),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            controls.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    private func rebuildCrumbs() {
        var views: [NSView] = []
        let paths = TopBar.ancestors(of: path)
        for (index, crumbPath) in paths.enumerated() {
            let isLast = index == paths.count - 1
            if index > 0 {
                let slash = NSTextField(labelWithString: "/")
                slash.font = .systemFont(ofSize: 13)
                slash.textColor = Theme.tertiaryText
                views.append(slash)
            }
            let name = crumbPath == "/" ? "Macintosh HD" : FileManager.default.displayName(atPath: crumbPath)
            let button = NSButton(title: name, target: self, action: #selector(crumbClicked(_:)))
            button.isBordered = false
            button.identifier = NSUserInterfaceItemIdentifier(crumbPath)
            let truncating = NSMutableParagraphStyle()
            truncating.lineBreakMode = .byTruncatingMiddle
            button.attributedTitle = NSAttributedString(string: name, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: isLast ? .medium : .regular),
                .foregroundColor: isLast ? Theme.text : Theme.secondaryText,
                .paragraphStyle: truncating,
            ])
            button.cell?.lineBreakMode = .byTruncatingMiddle
            button.toolTip = crumbPath
            views.append(button)
        }
        crumbs.items = views
    }

    static func ancestors(of path: String) -> [String] {
        let home = NSHomeDirectory()
        var result: [String] = []
        var current = path
        while true {
            result.insert(current, at: 0)
            if current == "/" || current == home { break }
            current = (current as NSString).deletingLastPathComponent
        }
        return result
    }

    @objc private func crumbClicked(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        onNavigate?(path)
    }

    @objc private func showModeMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for (index, mode) in ViewMode.allCases.enumerated() {
            let item = NSMenuItem(title: mode.title, action: #selector(PaneController.setViewMode(_:)), keyEquivalent: "")
            item.tag = index
            item.image = NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: nil)
            item.preferredImageVisibility = .visible
            menu.addItem(item)
        }
        popUp(menu, from: sender)
    }

    @objc private func showSortMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for (index, key) in SortKey.allCases.enumerated() {
            let item = NSMenuItem(title: key.title, action: #selector(PaneController.sortBy(_:)), keyEquivalent: "")
            item.tag = index
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (index, title) in ["Ascending", "Descending"].enumerated() {
            let item = NSMenuItem(title: title, action: #selector(PaneController.setSortDirection(_:)), keyEquivalent: "")
            item.tag = index
            menu.addItem(item)
        }
        popUp(menu, from: sender)
    }

    @objc private func showLayoutMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for (index, layout) in PaneLayout.allCases.enumerated() {
            let item = NSMenuItem(title: layout.title, action: #selector(BrowserWindowController.changeLayout(_:)), keyEquivalent: "")
            item.tag = index
            item.image = NSImage(systemSymbolName: layout.symbolName, accessibilityDescription: nil)
            item.preferredImageVisibility = .visible
            menu.addItem(item)
        }
        popUp(menu, from: sender)
    }

    private func popUp(_ menu: NSMenu, from button: NSButton) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.isFlipped ? button.bounds.height + 4 : -4), in: button)
    }
}

final class CrumbsView: NSView {
    private let spacing: CGFloat = 4
    private var naturalWidths: [CGFloat] = []

    var items: [NSView] = [] {
        didSet {
            oldValue.forEach { $0.removeFromSuperview() }
            items.forEach { addSubview($0) }
            naturalWidths = items.map { ceil($0.fittingSize.width) }
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override var intrinsicContentSize: NSSize {
        let height = items.map { ceil($0.fittingSize.height) }.max() ?? 0
        return NSSize(width: naturalWidths.reduce(0, +) + gaps, height: height)
    }

    private var gaps: CGFloat {
        spacing * CGFloat(max(items.count - 1, 0))
    }

    override func layout() {
        super.layout()
        let crumbIndices = items.indices.filter { items[$0] is NSButton }
        let fixed = items.indices.filter { !(items[$0] is NSButton) }.reduce(CGFloat(0)) { $0 + naturalWidths[$1] }
        let fitted = CrumbFit.widths(crumbIndices.map { naturalWidths[$0] }, available: bounds.width - fixed - gaps)
        var widths = naturalWidths
        for (index, width) in zip(crumbIndices, fitted) {
            widths[index] = width
        }
        var x: CGFloat = 0
        for (item, width) in zip(items, widths) {
            let height = ceil(item.fittingSize.height)
            item.frame = NSRect(x: x, y: floor((bounds.height - height) / 2), width: width, height: height)
            x += width + spacing
        }
    }
}
