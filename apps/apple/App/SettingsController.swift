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

final class ThemeTile: NSView {
    let theme: ThemeDefinition
    var onSelect: ((ThemeDefinition) -> Void)?

    var isSelected = false {
        didSet { needsDisplay = true }
    }

    init(theme: ThemeDefinition) {
        self.theme = theme
        super.init(frame: .zero)
        toolTip = theme.name
        setAccessibilityRole(.button)
        setAccessibilityLabel(theme.name)
        heightAnchor.constraint(equalToConstant: 104).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        Theme.card.setFill()
        path.fill()
        (isSelected ? Theme.accent : Theme.divider).setStroke()
        path.lineWidth = isSelected ? 2 : 1
        path.stroke()
        let side: CGFloat = 40
        let gap: CGFloat = 12
        for (index, palette) in [theme.light, theme.dark].enumerated() {
            let rect = NSRect(x: (bounds.midX - side - gap / 2 + CGFloat(index) * (side + gap)).rounded(), y: bounds.maxY - 16 - side, width: side, height: side)
            let orb = NSBezierPath(ovalIn: rect)
            NSGradient(colors: [Theme.nsColor(palette[.content]), Theme.nsColor(palette[.accent])])?.draw(in: orb, relativeCenterPosition: NSPoint(x: -0.4, y: 0.4))
            Theme.divider.setStroke()
            orb.lineWidth = 1
            orb.stroke()
        }
        let name = NSAttributedString(string: theme.name, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: Theme.text,
        ])
        name.draw(with: NSRect(x: 14, y: 14, width: bounds.width - 28, height: name.size().height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(theme)
    }

    override func accessibilityPerformPress() -> Bool {
        onSelect?(theme)
        return true
    }
}

final class ProfileRow: NSView {
    let index: Int
    let iconButton = PlainButton.make(SidebarProfile.icons[0], "Change Icon", target: nil, action: nil)
    let nameField = NSTextField()
    let deleteButton = PlainButton.make("trash", "Delete Profile", target: nil, action: nil)
    private var popover: NSPopover?

    init(index: Int) {
        self.index = index
        super.init(frame: .zero)
        iconButton.target = self
        iconButton.action = #selector(pickIcon(_:))
        deleteButton.target = self
        deleteButton.action = #selector(delete(_:))
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.focusRingType = .none
        nameField.font = .systemFont(ofSize: 13, weight: .medium)
        nameField.textColor = Theme.text
        nameField.lineBreakMode = .byTruncatingTail
        nameField.cell?.isScrollable = true
        nameField.cell?.sendsActionOnEndEditing = true
        nameField.target = self
        nameField.action = #selector(commitName(_:))
        nameField.setAccessibilityLabel("Profile Name")
        let iconBackground = FillView()
        iconBackground.color = Theme.inactiveSelection
        iconBackground.cornerRadius = 6
        iconBackground.addSubview(iconButton)
        for view in [iconBackground, nameField, deleteButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 48),
            iconBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconBackground.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBackground.widthAnchor.constraint(equalToConstant: 30),
            iconBackground.heightAnchor.constraint(equalToConstant: 28),
            iconButton.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconButton.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            nameField.leadingAnchor.constraint(equalTo: iconBackground.trailingAnchor, constant: 10),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameField.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -12),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func update(_ profile: SidebarProfile, canDelete: Bool) {
        iconButton.image = NSImage(systemSymbolName: profile.icon, accessibilityDescription: "Change Icon")
        if nameField.currentEditor() == nil {
            nameField.stringValue = profile.name
        }
        deleteButton.isEnabled = canDelete
        deleteButton.alphaValue = canDelete ? 1 : 0.35
    }

    override func cancelOperation(_ sender: Any?) {
        guard nameField.currentEditor() != nil else { return super.cancelOperation(sender) }
        nameField.abortEditing()
        if AppState.shared.profiles.indices.contains(index) {
            nameField.stringValue = AppState.shared.profiles[index].name
        }
    }

    @objc private func commitName(_ sender: NSTextField) {
        let state = AppState.shared
        state.renameProfile(at: index, to: sender.stringValue)
        if state.profiles.indices.contains(index) {
            sender.stringValue = state.profiles[index].name
        }
    }

    @objc private func pickIcon(_ sender: NSButton) {
        let current = AppState.shared.profiles.indices.contains(index) ? AppState.shared.profiles[index].icon : ""
        let columns = 5
        let rows = stride(from: 0, to: SidebarProfile.icons.count, by: columns).map { start in
            SidebarProfile.icons[start..<min(start + columns, SidebarProfile.icons.count)].map { icon -> NSView in
                let button = PlainButton.make(icon, icon, target: self, action: #selector(choseIcon(_:)))
                button.identifier = NSUserInterfaceItemIdentifier(icon)
                button.contentTintColor = icon == current ? Theme.accent : Theme.icon
                return button
            }
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 6
        grid.columnSpacing = 6
        grid.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
        ])
        let controller = NSViewController()
        controller.view = content
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        self.popover = popover
    }

    @objc private func choseIcon(_ sender: NSButton) {
        guard let icon = sender.identifier?.rawValue else { return }
        popover?.close()
        popover = nil
        AppState.shared.setProfileIcon(at: index, to: icon)
    }

    @objc private func delete(_ sender: Any?) {
        let state = AppState.shared
        guard state.profiles.indices.contains(index) else { return }
        let profile = state.profiles[index]
        if !profile.tree.nodes.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Delete the profile “\(profile.name)”?"
            alert.informativeText = "Its groups and folders will be removed from the sidebar. Nothing on disk is deleted."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        state.removeProfile(at: index)
    }
}

final class FocusableView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

final class SettingsController: NSViewController {
    var onClose: (() -> Void)?

    private let schemePopup = SettingsController.popup()
    private let profileList = NSStackView()
    private let themeGrid = NSStackView()
    private let themeErrors = NSTextField(wrappingLabelWithString: "")
    private var shownThemes: ThemeLibrary?
    private let hiddenSwitch = NSSwitch()
    private let dsStoreSwitch = NSSwitch()
    private var dsStoreRow: NSView?
    private let modePopup = SettingsController.popup()
    private let sortPopup = SettingsController.popup()
    private let orderPopup = SettingsController.popup()
    private let iconSlider = NSSlider(value: 80, minValue: Double(FolderView.iconSizes.lowerBound), maxValue: Double(FolderView.iconSizes.upperBound), target: nil, action: nil)
    private let iconValue = NSTextField(labelWithString: "")
    private let header = NSTextField(labelWithString: "Settings")
    private lazy var backButton = PlainButton.make("chevron.left", "Back to Settings", target: self, action: #selector(showMain(_:)))
    private var mainPage = NSScrollView()
    private var shortcutsPage = NSScrollView()
    private var titleLeading: NSLayoutConstraint?
    private var observers: [NSObjectProtocol] = []

    init() {
        super.init(nibName: nil, bundle: nil)
        let center = NotificationCenter.default
        observers = [.configChanged, .showHiddenChanged, .themeChanged, .sidebarChanged].map { name in
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
        popup.contentTintColor = Theme.secondaryText
        return popup
    }

    override func loadView() {
        schemePopup.addItems(withTitles: ColorScheme.allCases.map(\.title))
        schemePopup.target = self
        schemePopup.action = #selector(schemeChanged(_:))
        profileList.orientation = .vertical
        profileList.spacing = 0
        themeGrid.orientation = .vertical
        themeGrid.alignment = .leading
        themeGrid.spacing = 10
        themeErrors.font = .systemFont(ofSize: 12)
        themeErrors.textColor = Theme.warning

        hiddenSwitch.controlSize = .small
        hiddenSwitch.target = self
        hiddenSwitch.action = #selector(hiddenChanged(_:))
        dsStoreSwitch.controlSize = .small
        dsStoreSwitch.target = self
        dsStoreSwitch.action = #selector(dsStoreChanged(_:))

        for popup in [modePopup, sortPopup, orderPopup] {
            popup.target = self
            popup.action = #selector(defaultViewChanged(_:))
        }
        modePopup.addItems(withTitles: ViewMode.allCases.map(\.title))
        sortPopup.addItems(withTitles: SortKey.allCases.map(\.title))
        orderPopup.addItems(withTitles: ["Ascending", "Descending"])

        iconSlider.controlSize = .small
        iconSlider.trackFillColor = Theme.accent
        iconSlider.isContinuous = true
        iconSlider.target = self
        iconSlider.action = #selector(defaultViewChanged(_:))
        iconSlider.widthAnchor.constraint(equalToConstant: 140).isActive = true
        iconValue.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        iconValue.textColor = Theme.secondaryText
        iconValue.alignment = .right
        iconValue.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let iconControl = NSStackView(views: [iconValue, iconSlider])
        iconControl.spacing = 8

        let sortControl = NSStackView(views: [sortPopup, orderPopup])
        sortControl.spacing = 4

        let appearanceCard = card([
            row("Color scheme", "Follow the system, or always use light or dark.", schemePopup),
        ])
        let dsStoreRow = row("Show .DS_Store files", "Show the folder settings files macOS leaves behind.", dsStoreSwitch, indent: 16)
        self.dsStoreRow = dsStoreRow
        let generalCard = card([
            row("Show hidden files", "Show files and folders whose names start with a dot.", hiddenSwitch),
            dsStoreRow,
            row("Keyboard shortcuts", "Every keyboard shortcut in Cubby.", PlainButton.make("chevron.right", "Keyboard Shortcuts", target: self, action: #selector(showShortcuts(_:)))),
        ])
        let defaultViewCard = card([
            row("View", "How folders you haven't customized are shown.", modePopup),
            row("Sort by", "The column and direction folders are sorted by.", sortControl),
            row("Icon size", "Icon view thumbnail size.", iconControl),
        ])
        let profilesCard = CardView()
        profileList.translatesAutoresizingMaskIntoConstraints = false
        profilesCard.addSubview(profileList)
        NSLayoutConstraint.activate([
            profileList.topAnchor.constraint(equalTo: profilesCard.topAnchor),
            profileList.leadingAnchor.constraint(equalTo: profilesCard.leadingAnchor),
            profileList.trailingAnchor.constraint(equalTo: profilesCard.trailingAnchor),
            profileList.bottomAnchor.constraint(equalTo: profilesCard.bottomAnchor),
        ])
        let addProfile = link("Add Profile", target: self, action: #selector(addProfile(_:)))
        let profilesTitle = NSStackView(views: [sectionTitle("Profiles"), NSView(), addProfile])
        let sections: [NSView] = [
            profilesTitle,
            profilesCard,
            sectionTitle("Theme"),
            appearanceCard,
            themeGrid,
            themeErrors,
            sectionTitle("General"),
            generalCard,
            sectionTitle("Default view"),
            defaultViewCard,
        ]
        let stack = NSStackView(views: sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        for view in [profilesCard, themeGrid, themeErrors, generalCard] {
            stack.setCustomSpacing(28, after: view)
        }
        for view in sections where view is CardView || view === themeGrid || view === themeErrors || view === profilesTitle {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        mainPage = page(stack)
        shortcutsPage = page(shortcutsStack())
        shortcutsPage.isHidden = true

        header.font = .systemFont(ofSize: 13, weight: .medium)
        header.textColor = Theme.text
        backButton.isHidden = true
        let title = NSStackView(views: [backButton, header])
        title.spacing = 2
        title.translatesAutoresizingMaskIntoConstraints = false
        let close = PlainButton.make("xmark", "Close Settings", target: self, action: #selector(close(_:)))

        let root = FocusableView()
        for view in [mainPage, shortcutsPage, title, close] {
            root.addSubview(view)
        }
        titleLeading = title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16)
        NSLayoutConstraint.activate([
            titleLeading!,
            title.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            close.centerYAnchor.constraint(equalTo: root.topAnchor, constant: headerHeight / 2),
        ])
        for page in [mainPage, shortcutsPage] {
            NSLayoutConstraint.activate([
                page.topAnchor.constraint(equalTo: root.topAnchor, constant: headerHeight),
                page.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                page.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            ])
        }
        view = root
        refresh()
    }

    private func page(_ stack: NSStackView) -> NSScrollView {
        stack.translatesAutoresizingMaskIntoConstraints = false
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
        let width = stack.widthAnchor.constraint(equalToConstant: 640)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -32),
            stack.centerXAnchor.constraint(equalTo: document.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: document.leadingAnchor, constant: 32),
            width,
        ])
        return scroll
    }

    private func shortcutsStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        for (section, shortcuts) in Shortcuts.sections {
            let card = card(shortcuts.map(shortcutRow))
            stack.addArrangedSubview(sectionTitle(section.rawValue))
            stack.addArrangedSubview(card)
            stack.setCustomSpacing(28, after: card)
            card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func shortcutRow(_ shortcut: Shortcut) -> NSView {
        let title = NSTextField(labelWithString: shortcut.title)
        title.font = .systemFont(ofSize: 13)
        title.textColor = Theme.text
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let keys = NSStackView(views: shortcut.keys.map(keycap))
        keys.spacing = 6
        let row = NSView()
        for view in [title, keys] {
            view.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(view)
        }
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 36),
            title.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            title.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: keys.leadingAnchor, constant: -16),
            keys.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            keys.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func keycap(_ combo: KeyCombo) -> NSView {
        let label = NSTextField(labelWithString: combo.display)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = Theme.secondaryText
        label.translatesAutoresizingMaskIntoConstraints = false
        let cap = FillView()
        cap.color = Theme.inactiveSelection
        cap.cornerRadius = 5
        cap.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cap.leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: cap.trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: cap.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: cap.bottomAnchor, constant: -2),
        ])
        return cap
    }

    @objc private func showShortcuts(_ sender: Any?) {
        setShortcutsVisible(true)
    }

    @objc private func showMain(_ sender: Any?) {
        setShortcutsVisible(false)
    }

    private func setShortcutsVisible(_ visible: Bool) {
        mainPage.isHidden = visible
        shortcutsPage.isHidden = !visible
        backButton.isHidden = !visible
        titleLeading?.constant = visible ? 8 : 16
        header.stringValue = visible ? "Keyboard Shortcuts" : "Settings"
        shortcutsPage.contentView.scroll(to: .zero)
    }

    var headerHeight: CGFloat = 38

    @objc private func close(_ sender: Any?) {
        onClose?()
    }

    override func cancelOperation(_ sender: Any?) {
        if !shortcutsPage.isHidden {
            setShortcutsVisible(false)
        } else {
            onClose?()
        }
    }

    private func sectionTitle(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = Theme.secondaryText
        return label
    }

    private func link(_ title: String, target: AnyObject?, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.isBordered = false
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: Theme.accent,
        ])
        return button
    }

    private func rebuildThemeGrid(_ library: ThemeLibrary) {
        themeGrid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let columns = 3
        for start in stride(from: 0, to: library.themes.count, by: columns) {
            var views: [NSView] = library.themes[start..<min(start + columns, library.themes.count)].map { theme in
                let tile = ThemeTile(theme: theme)
                tile.onSelect = { AppState.shared.selectTheme($0.id) }
                return tile
            }
            while views.count < columns {
                views.append(NSView())
            }
            let row = NSStackView(views: views)
            row.distribution = .fillEqually
            row.spacing = 10
            themeGrid.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: themeGrid.widthAnchor).isActive = true
        }
        themeErrors.stringValue = library.errors.joined(separator: "\n")
        themeErrors.isHidden = library.errors.isEmpty
    }

    private func refreshProfiles(_ state: AppState) {
        let profiles = state.profiles
        let rows = profileList.arrangedSubviews.compactMap { $0 as? ProfileRow }
        if rows.count != profiles.count {
            profileList.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for index in profiles.indices {
                if index > 0 {
                    let divider = FillView()
                    divider.color = Theme.divider
                    divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
                    profileList.addArrangedSubview(divider)
                    divider.leadingAnchor.constraint(equalTo: profileList.leadingAnchor, constant: 16).isActive = true
                    divider.trailingAnchor.constraint(equalTo: profileList.trailingAnchor).isActive = true
                }
                let row = ProfileRow(index: index)
                profileList.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: profileList.widthAnchor).isActive = true
            }
        }
        for row in profileList.arrangedSubviews.compactMap({ $0 as? ProfileRow }) {
            row.update(profiles[row.index], canDelete: profiles.count > 1)
        }
    }

    @objc private func addProfile(_ sender: Any?) {
        let index = AppState.shared.addProfile()
        guard let row = profileList.arrangedSubviews.compactMap({ $0 as? ProfileRow }).first(where: { $0.index == index }) else { return }
        view.window?.makeFirstResponder(row.nameField)
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

    private func setRow(_ row: NSView, hidden: Bool) {
        row.isHidden = hidden
        guard let stack = row.superview as? NSStackView, let index = stack.arrangedSubviews.firstIndex(of: row), index > 0 else { return }
        stack.arrangedSubviews[index - 1].isHidden = hidden
    }

    private func row(_ title: String, _ detail: String, _ control: NSView, indent: CGFloat = 0) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = Theme.text
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = Theme.secondaryText
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
            text.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16 + indent),
            text.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -16),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    func refresh() {
        let state = AppState.shared
        refreshProfiles(state)
        schemePopup.selectItem(at: ColorScheme.allCases.firstIndex(of: state.colorScheme) ?? 0)
        if shownThemes != state.themes {
            shownThemes = state.themes
            rebuildThemeGrid(state.themes)
        }
        let selectedTheme = state.theme.id
        for case let row as NSStackView in themeGrid.arrangedSubviews {
            for case let tile as ThemeTile in row.arrangedSubviews {
                tile.isSelected = tile.theme.id == selectedTheme
            }
        }
        hiddenSwitch.state = state.showHiddenFiles ? .on : .off
        dsStoreSwitch.state = state.showDSStoreFiles ? .on : .off
        if let dsStoreRow {
            setRow(dsStoreRow, hidden: !state.showHiddenFiles)
        }
        let view = state.config.defaultView
        modePopup.selectItem(at: ViewMode.allCases.firstIndex(of: view.mode) ?? 0)
        sortPopup.selectItem(at: SortKey.allCases.firstIndex(of: view.sort) ?? 0)
        orderPopup.selectItem(at: view.ascending ? 0 : 1)
        iconSlider.integerValue = view.iconSize
        iconValue.stringValue = "\(view.iconSize) pt"

    }

    @objc private func schemeChanged(_ sender: NSPopUpButton) {
        AppState.shared.colorScheme = ColorScheme.allCases[max(sender.indexOfSelectedItem, 0)]
    }

    @objc private func hiddenChanged(_ sender: NSSwitch) {
        AppState.shared.showHiddenFiles = sender.state == .on
    }

    @objc private func dsStoreChanged(_ sender: NSSwitch) {
        AppState.shared.showDSStoreFiles = sender.state == .on
    }

    @objc private func defaultViewChanged(_ sender: Any?) {
        let view = FolderView(
            mode: ViewMode.allCases[max(modePopup.indexOfSelectedItem, 0)],
            sort: SortKey.allCases[max(sortPopup.indexOfSelectedItem, 0)],
            ascending: orderPopup.indexOfSelectedItem == 0,
            iconSize: iconSlider.integerValue,
            listIconSize: AppState.shared.defaultView.listIconSize,
        )
        iconValue.stringValue = "\(view.iconSize) pt"
        AppState.shared.defaultView = view
    }
}
