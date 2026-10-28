import Foundation

enum FileSorter {
    static let nameOptions: String.CompareOptions = [.caseInsensitive, .numeric, .widthInsensitive, .forcedOrdering]

    static func sorted(_ items: [FileItem], by key: SortKey, ascending: Bool) -> [FileItem] {
        switch key {
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

    static func filtered(_ items: [FileItem], showHidden: Bool, query: String) -> [FileItem] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        if showHidden && needle.isEmpty { return items }
        return items.filter { item in
            (showHidden || !item.isHidden) && (needle.isEmpty || item.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
        }
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
