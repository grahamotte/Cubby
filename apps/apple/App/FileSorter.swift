import Foundation

enum FileSorter {
    static let nameOptions: String.CompareOptions = [.caseInsensitive, .numeric, .widthInsensitive, .forcedOrdering]

    static func sorted(_ items: [FileItem], by key: SortKey, ascending: Bool, seed: UInt64 = 0, counts: [String: Int] = [:]) -> [FileItem] {
        switch key {
        case .count:
            let values = items.map { $0.isFolder ? counts[$0.path] : nil }
            return sortIndexed(items, ascending: ascending) { lhs, rhs in
                switch (values[lhs], values[rhs]) {
                case (nil, nil): .orderedSame
                case (nil, _): ascending ? .orderedDescending : .orderedAscending
                case (_, nil): ascending ? .orderedAscending : .orderedDescending
                case let (left?, right?): left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
                }
            }
        case .random:
            let ranks = items.map { randomRank($0.name, seed: seed) }
            return sortIndexed(items, ascending: true) { lhs, rhs in
                ranks[lhs] == ranks[rhs] ? .orderedSame : (ranks[lhs] < ranks[rhs] ? .orderedAscending : .orderedDescending)
            }
        case .name:
            return sortIndexed(items, ascending: ascending, byName: true) { _, _ in .orderedSame }
        case .kind:
            let kinds = items.map(\.kind)
            return sortIndexed(items, ascending: ascending) { lhs, rhs in
                kinds[lhs].compare(kinds[rhs], options: nameOptions)
            }
        case .size:
            return sortValues(items, ascending: ascending) { Double($0.isDirectory ? -1 : $0.size) }
        case .modified:
            return sortValues(items, ascending: ascending) { $0.modified }
        case .created:
            return sortValues(items, ascending: ascending) { $0.created }
        case .added:
            return sortValues(items, ascending: ascending) { $0.added }
        }
    }

    static func daySeed(_ date: Date = Date(), calendar: Calendar = .current) -> UInt64 {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return UInt64((day.year ?? 0) * 10000 + (day.month ?? 0) * 100 + (day.day ?? 0))
    }

    static func randomRank(_ name: String, seed: UInt64) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325 ^ seed
        for byte in name.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        hash = (hash ^ (hash >> 30)) &* 0xbf58476d1ce4e5b9
        hash = (hash ^ (hash >> 27)) &* 0x94d049bb133111eb
        return hash ^ (hash >> 31)
    }

    static func filtered(_ items: [FileItem], visibility: Visibility, query: String) -> [FileItem] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        if visibility.showsEverything && needle.isEmpty { return items }
        return items.filter { item in
            visibility.shows(item) && (needle.isEmpty || item.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
        }
    }

    static func matchRanges(in name: String, query: String) -> [NSRange] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard needle.count > 1 else { return [] }
        var ranges: [NSRange] = []
        var start = name.startIndex
        while start < name.endIndex, let found = name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: start..<name.endIndex) {
            if name.distance(from: found.lowerBound, to: found.upperBound) > 1 {
                ranges.append(NSRange(found, in: name))
            }
            start = found.upperBound
        }
        return ranges
    }

    private static func sortValues(_ items: [FileItem], ascending: Bool, value: (FileItem) -> Double) -> [FileItem] {
        let values = items.map(value)
        return sortIndexed(items, ascending: ascending) { lhs, rhs in
            values[lhs] == values[rhs] ? .orderedSame : (values[lhs] < values[rhs] ? .orderedAscending : .orderedDescending)
        }
    }

    private static func sortIndexed(_ items: [FileItem], ascending: Bool, byName: Bool = false, compare: (Int, Int) -> ComparisonResult) -> [FileItem] {
        let keys = items.map { Array($0.name.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil).utf16) }
        let indices = items.indices.sorted { lhs, rhs in
            let order = compare(lhs, rhs)
            if order != .orderedSame {
                return ascending ? order == .orderedAscending : order == .orderedDescending
            }
            var nameOrder = naturalCompare(keys[lhs], keys[rhs])
            if nameOrder == .orderedSame {
                nameOrder = items[lhs].name < items[rhs].name ? .orderedAscending : (items[lhs].name == items[rhs].name ? .orderedSame : .orderedDescending)
            }
            return ascending || !byName ? nameOrder == .orderedAscending : nameOrder == .orderedDescending
        }
        return indices.map { items[$0] }
    }

    static func naturalCompare(_ lhs: [UInt16], _ rhs: [UInt16]) -> ComparisonResult {
        lhs.withUnsafeBufferPointer { a in
            rhs.withUnsafeBufferPointer { b in
                var i = 0
                var j = 0
                while i < a.count && j < b.count {
                    let x = a[i]
                    let y = b[j]
                    if isDigit(x) && isDigit(y) {
                        var iEnd = i
                        while iEnd < a.count && isDigit(a[iEnd]) { iEnd += 1 }
                        var jEnd = j
                        while jEnd < b.count && isDigit(b[jEnd]) { jEnd += 1 }
                        var iStart = i
                        while iStart < iEnd - 1 && a[iStart] == 48 { iStart += 1 }
                        var jStart = j
                        while jStart < jEnd - 1 && b[jStart] == 48 { jStart += 1 }
                        let iLength = iEnd - iStart
                        let jLength = jEnd - jStart
                        if iLength != jLength { return iLength < jLength ? .orderedAscending : .orderedDescending }
                        var k = 0
                        while k < iLength {
                            if a[iStart + k] != b[jStart + k] { return a[iStart + k] < b[jStart + k] ? .orderedAscending : .orderedDescending }
                            k += 1
                        }
                        i = iEnd
                        j = jEnd
                        continue
                    }
                    if x != y { return x < y ? .orderedAscending : .orderedDescending }
                    i += 1
                    j += 1
                }
                if i < a.count { return .orderedDescending }
                if j < b.count { return .orderedAscending }
                return .orderedSame
            }
        }
    }

    private static func isDigit(_ unit: UInt16) -> Bool {
        unit >= 48 && unit <= 57
    }
}
