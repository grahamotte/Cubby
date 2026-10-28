import AppKit

final class PreviewView: NSView {
    private let imageView = ThumbnailView()
    private let name = NSTextField(labelWithString: "")
    private let info = NSTextField(labelWithString: "")
    private var item: FileItem?
    private var requestedSize: CGFloat = 0
    var showsName = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.textColor = Theme.text
        info.textColor = Theme.secondaryText
        info.font = .systemFont(ofSize: 11)
        for label in [name, info] {
            label.alignment = .center
            label.lineBreakMode = .byTruncatingMiddle
            label.translatesAutoresizingMaskIntoConstraints = false
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        addSubview(imageView)
        addSubview(name)
        addSubview(info)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            name.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),
            name.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            name.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            info.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2),
            info.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            info.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            info.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func show(_ item: FileItem?, emptyText: String = "") {
        self.item = item
        guard let item else {
            imageView.show(nil)
            name.stringValue = emptyText
            info.stringValue = ""
            return
        }
        name.stringValue = item.name
        info.stringValue = [item.kind, item.isFolder ? nil : FileFormat.size(item), "Modified " + FileFormat.date(item.modified)].compactMap { $0 }.joined(separator: "  ·  ")
        requestedSize = previewSize
        if let cached = ThumbnailCache.shared.cached(for: item, size: requestedSize) {
            imageView.show(cached)
        } else {
            imageView.show(IconCache.shared.icon(for: item))
        }
        let scale = window?.backingScaleFactor ?? 2
        ThumbnailCache.shared.thumbnail(for: item, size: requestedSize, scale: scale) { [weak self] thumbnail in
            guard let self, self.item === item else { return }
            self.imageView.show(thumbnail)
        }
    }

    private var previewSize: CGFloat {
        let side = max(bounds.width, bounds.height, 700)
        return min(CGFloat(Int(side / 256) + 1) * 256, 1536)
    }
}

final class ThumbnailView: NSView {
    private let imageView = NSImageView()
    private var rounded = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = true
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    var image: NSImage? { imageView.image }

    func show(_ image: NSImage?) {
        imageView.image = image
        rounded = false
        needsLayout = true
    }

    func show(_ thumbnail: Thumbnail) {
        imageView.image = thumbnail.image
        rounded = thumbnail.rounded
        needsLayout = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard rounded, let size = imageView.image?.size, size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else {
            imageView.frame = bounds
            imageView.layer?.cornerRadius = 0
            imageView.layer?.borderWidth = 0
            return
        }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let width = max((size.width * scale).rounded(), 1)
        let height = max((size.height * scale).rounded(), 1)
        imageView.frame = NSRect(x: ((bounds.width - width) / 2).rounded(), y: ((bounds.height - height) / 2).rounded(), width: width, height: height)
        imageView.layer?.cornerRadius = min(max(min(width, height) * 0.05, 4), 12)
        imageView.layer?.borderWidth = 1 / (window?.backingScaleFactor ?? 2)
        var color: CGColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = Theme.divider.cgColor
        }
        imageView.layer?.borderColor = color
    }
}
