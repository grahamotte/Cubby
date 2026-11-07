import AppKit

@MainActor
final class DropAnimation: NSObject {
    struct Target {
        let view: NSView
        let rect: NSRect
        let radius: CGFloat
        let icon: NSView?
    }

    typealias Icon = (image: NSImage, view: NSView)

    private struct Source {
        let paths: Set<String>
        let icon: (String) -> Icon?
    }

    private static var source: Source?
    private static var running: [DropAnimation] = []
    private static let flight: CFTimeInterval = 0.25
    private static let pulseDuration: CFTimeInterval = 0.3
    private static let limit = 12

    private let overlay: NSWindow
    private let origin: NSPoint
    private let locate: () -> Target?
    private let flyers: [(layer: CALayer, from: NSPoint)]
    private let pulse = CALayer()
    private let pulseDelay: CFTimeInterval
    private var destination: NSPoint
    private var pulseRect: NSRect?
    private var link: CADisplayLink?
    private var start: CFTimeInterval = 0

    static func trackSource(_ urls: [URL], icon: @escaping (String) -> Icon?) {
        source = Source(paths: Set(urls.map(\.standardizedFileURL.path)), icon: icon)
    }

    static func icon(row: Int, in table: NSTableView, column: Int = 0) -> Icon? {
        guard row >= 0, row < table.numberOfRows, column >= 0, table.visibleRect.intersects(table.rect(ofRow: row)),
              let cell = table.view(atColumn: column, row: row, makeIfNecessary: false) as? NSTableCellView,
              let view = cell.imageView, let image = view.image else { return nil }
        return (image, view)
    }

    static func row(_ row: Int, in table: NSTableView, column: Int = 0) -> Target? {
        guard row >= 0, row < table.numberOfRows, let rowView = table.rowView(atRow: row, makeIfNecessary: false) else { return nil }
        let inset = (rowView as? RoundedRowView)?.horizontalInset ?? 0
        let cell = column >= 0 ? table.view(atColumn: column, row: row, makeIfNecessary: false) as? NSTableCellView : nil
        return Target(view: rowView, rect: rowView.bounds.insetBy(dx: inset, dy: 1), radius: 6, icon: cell?.imageView)
    }

    static func run(_ info: NSDraggingInfo, in view: NSView, target: @escaping () -> Target? = { nil }) {
        guard let window = view.window else { return }
        let paths = DragSupport.urls(from: info).map(\.standardizedFileURL.path)
        var icons: [(NSImage, NSRect)] = []
        if let source, source.paths == Set(paths), !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            icons = paths.prefix(limit).compactMap { path in
                source.icon(path).flatMap { icon in screenRect(icon.view, icon.view.bounds).map { (icon.image, $0) } }
            }
        }
        guard !icons.isEmpty || target() != nil else { return }
        let frame = icons.reduce(window.frame) { $0.union($1.1) }
        let animation = DropAnimation(parent: window, frame: frame, icons: icons, drop: window.convertPoint(toScreen: info.draggingLocation), locate: target)
        running.append(animation)
        animation.begin(in: window)
    }

    private static func screenRect(_ view: NSView, _ rect: NSRect) -> NSRect? {
        guard let window = view.window else { return nil }
        return window.convertToScreen(view.convert(rect, to: nil))
    }

    private init(parent: NSWindow, frame: NSRect, icons: [(NSImage, NSRect)], drop: NSPoint, locate: @escaping () -> Target?) {
        overlay = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        origin = frame.origin
        self.locate = locate
        destination = drop
        pulseDelay = icons.isEmpty ? 0 : Self.flight * 0.6
        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        let root = content.layer ?? CALayer()
        let scale = parent.backingScaleFactor
        parent.effectiveAppearance.performAsCurrentDrawingAppearance { [pulse] in
            pulse.backgroundColor = Theme.selection.cgColor
        }
        pulse.opacity = 0
        root.addSublayer(pulse)
        flyers = icons.map { image, rect in
            let layer = CALayer()
            layer.frame = rect.offsetBy(dx: -frame.minX, dy: -frame.minY)
            layer.contents = image.layerContents(forContentsScale: scale)
            layer.contentsScale = scale
            layer.contentsGravity = .resizeAspect
            root.addSublayer(layer)
            return (layer, NSPoint(x: layer.frame.midX, y: layer.frame.midY))
        }
        super.init()
        overlay.isReleasedWhenClosed = false
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.animationBehavior = .none
        overlay.collectionBehavior = [.transient, .ignoresCycle]
        overlay.contentView = content
    }

    private func begin(in parent: NSWindow) {
        start = CACurrentMediaTime()
        update(elapsed: 0)
        parent.addChildWindow(overlay, ordered: .above)
        guard let content = overlay.contentView else { return finish() }
        let link = content.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        let elapsed = CACurrentMediaTime() - start
        update(elapsed: elapsed)
        if elapsed >= pulseDelay + Self.pulseDuration && elapsed >= Self.flight { finish() }
    }

    private func update(elapsed: CFTimeInterval) {
        if let target = locate(), let rect = Self.screenRect(target.view, target.rect) {
            pulseRect = rect
            pulse.cornerRadius = target.radius
            let icon = target.icon.flatMap { Self.screenRect($0, $0.bounds) } ?? rect
            destination = NSPoint(x: icon.midX, y: icon.midY)
        }
        let progress = min(elapsed / Self.flight, 1)
        let eased = progress * progress * (3 - 2 * progress)
        let to = NSPoint(x: destination.x - origin.x, y: destination.y - origin.y)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for flyer in flyers {
            flyer.layer.position = NSPoint(x: flyer.from.x + (to.x - flyer.from.x) * eased, y: flyer.from.y + (to.y - flyer.from.y) * eased)
            flyer.layer.setAffineTransform(CGAffineTransform(scaleX: 1 - 0.6 * eased, y: 1 - 0.6 * eased))
            flyer.layer.opacity = Float(progress < 0.6 ? 1 : (1 - progress) / 0.4)
        }
        if let pulseRect {
            pulse.frame = pulseRect.offsetBy(dx: -origin.x, dy: -origin.y)
            let phase = (elapsed - pulseDelay) / Self.pulseDuration
            pulse.opacity = phase > 0 && phase < 1 ? Float(sin(phase * .pi)) : 0
        }
        CATransaction.commit()
    }

    private func finish() {
        link?.invalidate()
        link = nil
        overlay.parent?.removeChildWindow(overlay)
        overlay.orderOut(nil)
        Self.running.removeAll { $0 === self }
    }
}
