import AppKit

final class ThemedSwitch: NSControl {
    private static let size = NSSize(width: 32, height: 18)

    @objc dynamic private var knobPosition: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    var state: NSControl.StateValue = .off {
        didSet {
            guard state != oldValue else { return }
            knobPosition = state == .on ? 1 : 0
            setAccessibilityValue(state == .on)
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilitySubrole(.switch)
        setAccessibilityValue(false)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override var intrinsicContentSize: NSSize { ThemedSwitch.size }
    override var acceptsFirstResponder: Bool { NSApp.isFullKeyboardAccessEnabled }
    override var canBecomeKeyView: Bool { NSApp.isFullKeyboardAccessEnabled }
    override var focusRingMaskBounds: NSRect { bounds }

    override static func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
        key == "knobPosition" ? CABasicAnimation() : super.defaultAnimation(forKey: key)
    }

    override func drawFocusRingMask() {
        track.fill()
    }

    private var track: NSBezierPath {
        let rect = NSRect(x: (bounds.width - ThemedSwitch.size.width) / 2, y: (bounds.height - ThemedSwitch.size.height) / 2, width: ThemedSwitch.size.width, height: ThemedSwitch.size.height)
        return NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = track
        let rect = track.bounds
        Theme.inactiveSelection.setFill()
        track.fill()
        if knobPosition > 0 {
            Theme.accent.withAlphaComponent(knobPosition).setFill()
            track.fill()
        }
        Theme.divider.setStroke()
        track.lineWidth = 1
        track.stroke()
        let side = rect.height - 4
        let knob = NSRect(x: rect.minX + 2 + (rect.width - side - 4) * knobPosition, y: rect.minY + 2, width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowBlurRadius = 1
        shadow.set()
        Theme.knob.setFill()
        NSBezierPath(ovalIn: knob).fill()
        NSGraphicsContext.restoreGraphicsState()
        if !isEnabled {
            Theme.content.withAlphaComponent(0.5).setFill()
            track.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        toggle()
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            toggle()
        } else {
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        toggle()
        return true
    }

    private func toggle() {
        let next: NSControl.StateValue = state == .on ? .off : .on
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            animator().knobPosition = next == .on ? 1 : 0
        }
        state = next
        sendAction(action, to: target)
    }
}

final class ThemedSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let bar = NSRect(x: rect.minX, y: rect.midY - 2, width: rect.width, height: 4)
        let track = NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2)
        Theme.inactiveSelection.setFill()
        track.fill()
        let knob = knobRect(flipped: flipped)
        var filled = bar
        filled.size.width = max(knob.midX - bar.minX, 0)
        Theme.accent.setFill()
        NSBezierPath(roundedRect: filled, xRadius: 2, yRadius: 2).fill()
    }

    override func drawKnob(_ knobRect: NSRect) {
        let side = min(knobRect.width, knobRect.height) - 4
        let knob = NSRect(x: knobRect.midX - side / 2, y: knobRect.midY - side / 2, width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowBlurRadius = 1.5
        shadow.set()
        Theme.knob.setFill()
        NSBezierPath(ovalIn: knob).fill()
        NSGraphicsContext.restoreGraphicsState()
        Theme.divider.setStroke()
        let outline = NSBezierPath(ovalIn: knob.insetBy(dx: 0.5, dy: 0.5))
        outline.lineWidth = 1
        outline.stroke()
    }
}

final class ThemedSlider: NSSlider {
    override class var cellClass: AnyClass? {
        get { ThemedSliderCell.self }
        set {}
    }
}

enum ThemedText {
    @MainActor
    static func apply(to editor: NSTextView) {
        editor.selectedTextAttributes = [.backgroundColor: Theme.selection, .foregroundColor: Theme.text]
        editor.insertionPointColor = Theme.text
    }
}

final class ThemedSearchFieldCell: NSSearchFieldCell {
    override func searchButtonRect(forBounds rect: NSRect) -> NSRect {
        NSRect(x: rect.minX + 6, y: rect.midY - 7, width: 14, height: 14)
    }

    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
        NSRect(x: rect.maxX - 20, y: rect.midY - 7, width: 14, height: 14)
    }

    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        let height = (font ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)).boundingRectForFont.height.rounded(.up)
        return NSRect(x: rect.minX + 24, y: (rect.midY - height / 2).rounded(), width: max(rect.width - 48, 0), height: height)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        searchTextRect(forBounds: rect)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

final class ThemedSearchField: NSSearchField {
    override class var cellClass: AnyClass? {
        get { ThemedSearchFieldCell.self }
        set {}
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBezeled = false
        isBordered = false
        drawsBackground = false
        textColor = Theme.text
        guard let cell = cell as? NSSearchFieldCell else { return }
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium).applying(.init(paletteColors: [Theme.secondaryText]))
        cell.searchButtonCell?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")?.withSymbolConfiguration(configuration)
        cell.searchButtonCell?.alternateImage = cell.searchButtonCell?.image
        cell.cancelButtonCell?.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear")?.withSymbolConfiguration(configuration)
        cell.cancelButtonCell?.alternateImage = cell.cancelButtonCell?.image
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override var placeholderString: String? {
        didSet {
            placeholderAttributedString = placeholderString.map {
                NSAttributedString(string: $0, attributes: [.foregroundColor: Theme.tertiaryText, .font: font ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)])
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        Theme.inactiveSelection.setFill()
        path.fill()
        (currentEditor() == nil ? Theme.divider : Theme.accent).setStroke()
        path.lineWidth = 1
        path.stroke()
        cell?.drawInterior(withFrame: bounds, in: self)
    }

    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        needsDisplay = true
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        needsDisplay = true
    }
}
