import AppKit

final class CardView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        Theme.card.setFill()
        path.fill()
        Theme.divider.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

final class FocusableView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

final class SettingsController: NSViewController {
    var onClose: (() -> Void)?

    private static let terminals = [
        ("Terminal", "com.apple.Terminal"),
        ("iTerm", "com.googlecode.iterm2"),
        ("Ghostty", "com.mitchellh.ghostty"),
        ("Warp", "dev.warp.Warp-Stable"),
        ("kitty", "net.kovidgoyal.kitty"),
        ("Alacritty", "org.alacritty"),
        ("WezTerm", "com.github.wez.wezterm"),
    ]

    private let hiddenSwitch = NSSwitch()
    private let terminalPopup = SettingsController.popup()
    private let modePopup = SettingsController.popup()
    private let sortPopup = SettingsController.popup()
    private let orderPopup = SettingsController.popup()
    private let iconSlider = NSSlider(value: 80, minValue: Double(FolderView.iconSizes.lowerBound), maxValue: Double(FolderView.iconSizes.upperBound), target: nil, action: nil)
    private let iconValue = NSTextField(labelWithString: "")
    private var observers: [NSObjectProtocol] = []

    init() {
        super.init(nibName: nil, bundle: nil)
        let center = NotificationCenter.default
        observers = [.configChanged, .showHiddenChanged].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private static func popup() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.isBordered = false
        popup.font = .systemFont(ofSize: 13)
        popup.contentTintColor = .secondaryLabelColor
        return popup
    }

    override func loadView() {
        hiddenSwitch.controlSize = .small
        hiddenSwitch.target = self
        hiddenSwitch.action = #selector(hiddenChanged(_:))

        for (popup, action) in [(terminalPopup, #selector(terminalChanged(_:))), (modePopup, #selector(defaultViewChanged(_:))), (sortPopup, #selector(defaultViewChanged(_:))), (orderPopup, #selector(defaultViewChanged(_:)))] {
            popup.target = self
            popup.action = action
        }
        modePopup.addItems(withTitles: ViewMode.allCases.map(\.title))
        sortPopup.addItems(withTitles: SortKey.allCases.map(\.title))
        orderPopup.addItems(withTitles: ["Ascending", "Descending"])

        iconSlider.controlSize = .small
        iconSlider.isContinuous = true
        iconSlider.target = self
        iconSlider.action = #selector(defaultViewChanged(_:))
        iconSlider.widthAnchor.constraint(equalToConstant: 140).isActive = true
        iconValue.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        iconValue.textColor = .secondaryLabelColor
        iconValue.alignment = .right
        iconValue.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let iconControl = NSStackView(views: [iconValue, iconSlider])
        iconControl.spacing = 8

        let openConfig = NSButton(title: "Open config.json", target: nil, action: #selector(AppDelegate.openConfigFile(_:)))
        openConfig.isBordered = false
        openConfig.attributedTitle = NSAttributedString(string: "Open config.json", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.controlAccentColor,
        ])
        let path = NSTextField(labelWithString: (AppState.shared.paths.configFile.path as NSString).abbreviatingWithTildeInPath)
        path.font = .systemFont(ofSize: 12)
        path.textColor = .tertiaryLabelColor
        path.lineBreakMode = .byTruncatingMiddle
        let footer = NSStackView(views: [path, openConfig])
        footer.spacing = 10

        let sections: [NSView] = [
            sectionTitle("General"),
            card([
                row("Show hidden files", "Show files and folders whose names start with a dot.", hiddenSwitch),
                row("Terminal", "The app Open in Terminal uses.", terminalPopup),
            ]),
            sectionTitle("Default view"),
            card([
                row("View", "How folders you haven't customized are shown.", modePopup),
                row("Sort by", "The column folders are sorted by.", sortPopup),
                row("Order", "Sort direction.", orderPopup),
                row("Icon size", "Icon and gallery thumbnail size.", iconControl),
            ]),
            footer,
        ]
        let stack = NSStackView(views: sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(28, after: sections[1])
        stack.setCustomSpacing(16, after: sections[3])
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in sections where view is CardView {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        let scroll = NSScrollView()
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "Settings")
        header.font = .systemFont(ofSize: 13, weight: .medium)
        header.translatesAutoresizingMaskIntoConstraints = false
        let close = PlainButton.make("xmark", "Close Settings", target: self, action: #selector(close(_:)))

        let root = FocusableView()
        for view in [scroll, header, close] {
            root.addSubview(view)
        }
        let width = stack.widthAnchor.constraint(equalToConstant: 640)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            header.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            close.centerYAnchor.constraint(equalTo: root.topAnchor, constant: headerHeight / 2),
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: headerHeight),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -32),
            stack.centerXAnchor.constraint(equalTo: document.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: document.leadingAnchor, constant: 32),
            width,
        ])
        view = root
        refresh()
    }

    var headerHeight: CGFloat = 38

    @objc private func close(_ sender: Any?) {
        onClose?()
    }

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    private func sectionTitle(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func card(_ rows: [NSView]) -> NSView {
        let card = CardView()
        var views: [NSView] = []
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let divider = FillView()
                divider.color = Theme.divider
                divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
                views.append(divider)
            }
            views.append(row)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        for view in views {
            view.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: view is FillView ? 16 : 0).isActive = true
            view.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }
        return card
    }

    private func row(_ title: String, _ detail: String, _ control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let text = NSStackView(views: [titleLabel, detailLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        let row = NSView()
        for view in [text, control] {
            view.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(view)
        }
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            text.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            text.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
            text.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            text.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -16),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    func refresh() {
        let state = AppState.shared
        hiddenSwitch.state = state.showHiddenFiles ? .on : .off
        let view = state.config.defaultView
        modePopup.selectItem(at: ViewMode.allCases.firstIndex(of: view.mode) ?? 0)
        sortPopup.selectItem(at: SortKey.allCases.firstIndex(of: view.sort) ?? 0)
        orderPopup.selectItem(at: view.ascending ? 0 : 1)
        iconSlider.integerValue = view.iconSize
        iconValue.stringValue = "\(view.iconSize) pt"

        terminalPopup.removeAllItems()
        let current = state.config.terminal
        let selected = SettingsController.terminals.first { $0.0 == current || $0.1 == current }
        var choices = SettingsController.terminals.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.1) != nil }
        if let selected, !choices.contains(where: { $0.1 == selected.1 }) {
            choices.append(selected)
        }
        if selected == nil {
            choices.append((current, current))
        }
        for (name, bundle) in choices {
            terminalPopup.addItem(withTitle: name)
            terminalPopup.lastItem?.representedObject = bundle
        }
        terminalPopup.selectItem(at: terminalPopup.indexOfItem(withRepresentedObject: selected?.1 ?? current))
    }

    @objc private func hiddenChanged(_ sender: NSSwitch) {
        AppState.shared.showHiddenFiles = sender.state == .on
    }

    @objc private func terminalChanged(_ sender: NSPopUpButton) {
        guard let name = sender.selectedItem?.representedObject as? String else { return }
        AppState.shared.terminal = name
    }

    @objc private func defaultViewChanged(_ sender: Any?) {
        let view = FolderView(
            mode: ViewMode.allCases[max(modePopup.indexOfSelectedItem, 0)],
            sort: SortKey.allCases[max(sortPopup.indexOfSelectedItem, 0)],
            ascending: orderPopup.indexOfSelectedItem == 0,
            iconSize: iconSlider.integerValue,
        )
        iconValue.stringValue = "\(view.iconSize) pt"
        AppState.shared.defaultView = view
    }
}
