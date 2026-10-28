import Foundation

enum ViewMode: String, Codable, CaseIterable {
    case list
    case icons
    case columns
    case gallery

    var title: String {
        switch self {
        case .list: "List"
        case .icons: "Icons"
        case .columns: "Columns"
        case .gallery: "Gallery"
        }
    }

    var symbolName: String {
        switch self {
        case .list: "list.bullet"
        case .icons: "square.grid.2x2"
        case .columns: "rectangle.split.3x1"
        case .gallery: "rectangle.bottomthird.inset.filled"
        }
    }
}

enum SortKey: String, Codable, CaseIterable {
    case name
    case modified
    case added
    case created
    case size
    case kind

    var title: String {
        switch self {
        case .name: "Name"
        case .modified: "Date Modified"
        case .added: "Date Added"
        case .created: "Date Created"
        case .size: "Size"
        case .kind: "Kind"
        }
    }

    var defaultAscending: Bool {
        switch self {
        case .name, .kind: true
        case .modified, .added, .created, .size: false
        }
    }
}

struct FolderView: Codable, Equatable {
    static let iconSizes = 32...512

    var mode: ViewMode
    var sort: SortKey
    var ascending: Bool
    var iconSize: Int

    static let standard = FolderView(mode: .list, sort: .name, ascending: true, iconSize: 80)

    init(mode: ViewMode, sort: SortKey, ascending: Bool, iconSize: Int) {
        self.mode = mode
        self.sort = sort
        self.ascending = ascending
        self.iconSize = min(max(iconSize, FolderView.iconSizes.lowerBound), FolderView.iconSizes.upperBound)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = FolderView.standard
        self.init(
            mode: (try? container.decodeIfPresent(ViewMode.self, forKey: .mode)) ?? standard.mode,
            sort: (try? container.decodeIfPresent(SortKey.self, forKey: .sort)) ?? standard.sort,
            ascending: (try? container.decodeIfPresent(Bool.self, forKey: .ascending)) ?? standard.ascending,
            iconSize: (try? container.decodeIfPresent(Int.self, forKey: .iconSize)) ?? standard.iconSize,
        )
    }
}
