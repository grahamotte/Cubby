import Foundation

struct ScrollAnchor: Equatable {
    var paths: [String]
    var offset: Double

    init(paths: [String], offset: Double) {
        self.paths = paths
        self.offset = offset
    }

    init?(rows: [String], top: Int, offset: Double) {
        guard rows.indices.contains(top) else { return nil }
        var paths = [rows[top]]
        var distance = 1
        while top + distance < rows.count || top - distance >= 0 {
            if top + distance < rows.count { paths.append(rows[top + distance]) }
            if top - distance >= 0 { paths.append(rows[top - distance]) }
            distance += 1
        }
        self.init(paths: paths, offset: offset)
    }

    func resolve(_ index: (String) -> Int?) -> (index: Int, offset: Double)? {
        for (position, path) in paths.enumerated() {
            if let found = index(path) {
                return (found, position == 0 ? offset : 0)
            }
        }
        return nil
    }
}

struct ScrollMemory {
    static let limit = 300

    private var anchors: [String: ScrollAnchor] = [:]
    private(set) var order: [String] = []

    mutating func save(_ anchor: ScrollAnchor?, for folder: String) {
        order.removeAll { $0 == folder }
        guard let anchor else {
            anchors[folder] = nil
            return
        }
        anchors[folder] = anchor
        order.append(folder)
        if order.count > ScrollMemory.limit {
            for evicted in order.prefix(order.count - ScrollMemory.limit) {
                anchors[evicted] = nil
            }
            order.removeFirst(order.count - ScrollMemory.limit)
        }
    }

    mutating func anchor(for folder: String) -> ScrollAnchor? {
        guard let anchor = anchors[folder] else { return nil }
        order.removeAll { $0 == folder }
        order.append(folder)
        return anchor
    }
}
