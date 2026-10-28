import AppKit

final class GalleryBrowser: TileBrowser {
    private let preview = PreviewView()
    private var stripHeight: NSLayoutConstraint?
    private var previewedPath: String?

    override func makeLayout() -> NSCollectionViewLayout {
        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        return layout
    }

    override func loadView() {
        super.loadView()
        let container = NSView()
        preview.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        container.addSubview(preview)
        container.addSubview(scrollView)
        let height = scrollView.heightAnchor.constraint(equalToConstant: 120)
        stripHeight = height
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            preview.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            preview.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            height,
        ])
        view = container
        updateLayout()
    }

    override func updateLayout() {
        guard let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
        let size = min(iconSize, 96)
        layout.itemSize = NSSize(width: size + 16, height: size + 16)
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        layout.sectionInset = NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12)
        stripHeight?.constant = size + 36
    }

    override func configure(_ tile: FileTileItem, _ item: FileItem) {
        tile.showsLabel = false
        super.configure(tile, item)
    }

    override func reload(_ change: DirectoryModel.Change) {
        super.reload(change)
        selectFirstIfNeeded()
        updatePreview()
    }

    override func select(paths: Set<String>, scroll: Bool) {
        super.select(paths: paths, scroll: scroll)
        selectFirstIfNeeded()
    }

    private func selectFirstIfNeeded() {
        guard selectedItems.isEmpty, let first = items.first else { return }
        super.select(paths: [first.path], scroll: true)
    }

    override func selectionChanged() {
        super.selectionChanged()
        updatePreview()
    }

    override func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 125 || event.keyCode == 126, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            return true
        }
        return super.handleKey(event)
    }

    private func updatePreview() {
        let item = selectedItems.last
        guard item?.path != previewedPath else { return }
        previewedPath = item?.path
        preview.show(item, emptyText: items.isEmpty ? "No items" : "")
    }
}
