import AppKit

final class FillView: NSView {
    var color: NSColor = Theme.content {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        dirtyRect.fill()
    }
}

enum PlainButton {
    static func make(_ symbol: String, _ description: String, target: AnyObject?, action: Selector?) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: description)!, target: target, action: action)
        button.isBordered = false
        button.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        button.contentTintColor = .secondaryLabelColor
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
    let searchField = NSSearchField()
    var onNavigate: ((String) -> Void)?
    private let crumbs = NSStackView()
    private let activitySpinner = NSProgressIndicator()
    private let activityLabel = NSTextField(labelWithString: "")
    private lazy var filterButton = PlainButton.make("magnifyingglass", "Filter", target: nil, action: #selector(BrowserWindowController.performFindPanelAction(_:)))
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

    var activity: String? {
        didSet {
            activityLabel.stringValue = activity ?? ""
            activityLabel.isHidden = activity == nil
            activitySpinner.isHidden = activity == nil
            if activity == nil { activitySpinner.stopAnimation(nil) } else { activitySpinner.startAnimation(nil) }
        }
    }

    var isFilterVisible: Bool {
        get { !searchField.isHidden }
        set { searchField.isHidden = !newValue }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        crumbs.orientation = .horizontal
        crumbs.spacing = 4
        crumbs.setClippingResistancePriority(.defaultLow, for: .horizontal)
        crumbs.translatesAutoresizingMaskIntoConstraints = false

        activitySpinner.style = .spinning
        activitySpinner.controlSize = .small
        activitySpinner.isDisplayedWhenStopped = false
        activitySpinner.isHidden = true
        activityLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        activityLabel.textColor = .secondaryLabelColor
        activityLabel.lineBreakMode = .byTruncatingTail
        activityLabel.isHidden = true
        activityLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        searchField.placeholderString = "Filter"
        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        searchField.sendsSearchStringImmediately = true
        searchField.focusRingType = .none
        searchField.isHidden = true
        searchField.widthAnchor.constraint(equalToConstant: 180).isActive = true

        let controls = NSStackView(views: [activitySpinner, activityLabel, searchField, filterButton, modeButton, layoutButton])
        controls.orientation = .horizontal
        controls.spacing = 2
        controls.setCustomSpacing(8, after: activityLabel)
        controls.setCustomSpacing(6, after: searchField)
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.setHuggingPriority(.required, for: .horizontal)

        addSubview(crumbs)
        addSubview(controls)
        NSLayoutConstraint.activate([
            crumbs.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            crumbs.centerYAnchor.constraint(equalTo: centerYAnchor),
            crumbs.trailingAnchor.constraint(lessThanOrEqualTo: controls.leadingAnchor, constant: -12),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            controls.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    private func rebuildCrumbs() {
        crumbs.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let paths = TopBar.ancestors(of: path)
        for (index, crumbPath) in paths.enumerated() {
            let isLast = index == paths.count - 1
            if index > 0 {
                let slash = NSTextField(labelWithString: "/")
                slash.font = .systemFont(ofSize: 13)
                slash.textColor = .tertiaryLabelColor
                slash.setContentCompressionResistancePriority(.required, for: .horizontal)
                crumbs.addArrangedSubview(slash)
            }
            let name = crumbPath == "/" ? "Macintosh HD" : FileManager.default.displayName(atPath: crumbPath)
            let button = NSButton(title: name, target: self, action: #selector(crumbClicked(_:)))
            button.isBordered = false
            button.identifier = NSUserInterfaceItemIdentifier(crumbPath)
            button.attributedTitle = NSAttributedString(string: name, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: isLast ? .medium : .regular),
                .foregroundColor: isLast ? NSColor.labelColor : NSColor.secondaryLabelColor,
            ])
            button.cell?.lineBreakMode = .byTruncatingTail
            button.toolTip = crumbPath
            button.setContentCompressionResistancePriority(isLast ? .defaultHigh : NSLayoutConstraint.Priority(rawValue: 250 + Float(index)), for: .horizontal)
            crumbs.addArrangedSubview(button)
        }
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
            menu.addItem(item)
        }
        popUp(menu, from: sender)
    }

    private func popUp(_ menu: NSMenu, from button: NSButton) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.isFlipped ? button.bounds.height + 4 : -4), in: button)
    }
}
