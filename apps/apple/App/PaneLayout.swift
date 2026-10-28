import Foundation

enum PaneLayout: String, Codable, CaseIterable {
    case single
    case sideBySide
    case stacked
    case triple
    case grid

    var title: String {
        switch self {
        case .single: "Single Pane"
        case .sideBySide: "Side by Side"
        case .stacked: "Stacked"
        case .triple: "Three Panes"
        case .grid: "Four Panes"
        }
    }

    var symbolName: String {
        switch self {
        case .single: "square"
        case .sideBySide: "rectangle.split.2x1"
        case .stacked: "rectangle.split.1x2"
        case .triple: "rectangle.split.3x1"
        case .grid: "square.grid.2x2"
        }
    }

    var rows: [Int] {
        switch self {
        case .single: [1]
        case .sideBySide: [2]
        case .stacked: [1, 1]
        case .triple: [3]
        case .grid: [2, 2]
        }
    }

    var paneCount: Int { rows.reduce(0, +) }
}
