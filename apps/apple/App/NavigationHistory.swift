import Foundation

struct NavigationHistory: Equatable {
    static let limit = 100

    private(set) var entries: [String] = []
    private(set) var index = -1

    var current: String? { entries.indices.contains(index) ? entries[index] : nil }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < entries.count - 1 }

    mutating func visit(_ path: String) {
        guard path != current else { return }
        if canGoForward {
            entries.removeSubrange((index + 1)...)
        }
        entries.append(path)
        if entries.count > NavigationHistory.limit {
            entries.removeFirst(entries.count - NavigationHistory.limit)
        }
        index = entries.count - 1
    }

    mutating func back() -> String? {
        guard canGoBack else { return nil }
        index -= 1
        return current
    }

    mutating func forward() -> String? {
        guard canGoForward else { return nil }
        index += 1
        return current
    }

    mutating func replaceCurrent(with path: String) {
        guard entries.indices.contains(index) else { return visit(path) }
        entries[index] = path
    }
}
