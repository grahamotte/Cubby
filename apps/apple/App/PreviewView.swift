import AppKit

final class PreviewView: NSView {
    private let imageView = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let info = NSTextField(labelWithString: "")
    private var item: FileItem?
    private var requestedSize: CGFloat = 0
    var showsName = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        info.textColor = .secondaryLabelColor
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
            imageView.image = nil
            name.stringValue = emptyText
            info.stringValue = ""
            return
        }
        name.stringValue = item.name
        info.stringValue = [item.kind, item.isFolder ? nil : FileFormat.size(item), "Modified " + FileFormat.date(item.modified)].compactMap { $0 }.joined(separator: "  ·  ")
        requestedSize = previewSize
        imageView.image = ThumbnailCache.shared.cached(for: item, size: requestedSize) ?? IconCache.shared.icon(for: item)
        let scale = window?.backingScaleFactor ?? 2
        ThumbnailCache.shared.thumbnail(for: item, size: requestedSize, scale: scale) { [weak self] image in
            guard let self, self.item === item else { return }
            self.imageView.image = image
        }
    }

    private var previewSize: CGFloat {
        let side = max(bounds.width, bounds.height, 700)
        return min(CGFloat(Int(side / 256) + 1) * 256, 1536)
    }
}
