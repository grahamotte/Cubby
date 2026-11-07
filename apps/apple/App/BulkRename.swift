import Foundation

struct BulkRename: Equatable {
    enum Numbering: String, CaseIterable {
        case none
        case before
        case after

        var title: String {
            switch self {
            case .none: return "None"
            case .before: return "Before Name"
            case .after: return "After Name"
            }
        }
    }

    enum LetterCase: String, CaseIterable {
        case keep
        case lower
        case upper
        case title

        var title: String {
            switch self {
            case .keep: return "Unchanged"
            case .lower: return "lowercase"
            case .upper: return "UPPERCASE"
            case .title: return "Title Case"
            }
        }
    }

    struct Item: Equatable {
        let url: URL
        let splitsExtension: Bool
    }

    struct Row: Equatable {
        let url: URL
        let name: String
        let problem: String?

        var changed: Bool { name != url.lastPathComponent }
    }

    var find = ""
    var replace = ""
    var regex = false
    var prefix = ""
    var suffix = ""
    var removeFirst = 0
    var removeLast = 0
    var numbering = Numbering.none
    var start = 1
    var separator = " "
    var letterCase = LetterCase.keep

    var regexError: String? {
        guard regex, !find.isEmpty else { return nil }
        do {
            _ = try NSRegularExpression(pattern: find)
            return nil
        } catch {
            return "The regular expression is invalid."
        }
    }

    func name(for item: Item, index: Int, total: Int) -> String {
        let original = item.url.lastPathComponent
        let (base, ext) = item.splitsExtension ? FileNaming.split(original) : (original, "")
        var name = String(base.dropFirst(max(removeFirst, 0)).dropLast(max(removeLast, 0)))
        name = replaced(name)
        switch letterCase {
        case .keep: break
        case .lower: name = name.lowercased()
        case .upper: name = name.uppercased()
        case .title: name = name.capitalized
        }
        name = prefix + name + suffix
        let last = start + max(total - 1, 0)
        let width = String(max(last, start)).count
        let digits = String(start + index)
        let number = String(repeating: "0", count: max(width - digits.count, 0)) + digits
        switch numbering {
        case .none: break
        case .before: name = name.isEmpty ? number : number + separator + name
        case .after: name = name.isEmpty ? number : name + separator + number
        }
        return ext.isEmpty ? name : "\(name).\(ext)"
    }

    func plan(_ items: [Item], exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [Row] {
        let names = items.enumerated().map { name(for: $1, index: $0, total: items.count) }
        let sources = Set(items.map { Self.key($0.url) })
        var counts: [String: Int] = [:]
        for (item, name) in zip(items, names) {
            counts[Self.key(item.url.deletingLastPathComponent().appending(path: name)), default: 0] += 1
        }
        return zip(items, names).map { item, name in
            let original = item.url.lastPathComponent
            guard name != original else { return Row(url: item.url, name: name, problem: nil) }
            let destination = item.url.deletingLastPathComponent().appending(path: name)
            let key = Self.key(destination)
            var problem = regexError ?? FileNaming.validationError(for: name)
            if problem == nil, FileNaming.becomesHidden(renaming: original, to: name) {
                problem = "Names that begin with “.” are hidden."
            } else if problem == nil, counts[key, default: 0] > 1 {
                problem = "Another item gets this name."
            } else if problem == nil, !sources.contains(key), exists(destination.path) {
                problem = "An item with this name already exists."
            }
            return Row(url: item.url, name: name, problem: problem)
        }
    }

    static func key(_ url: URL) -> String {
        url.standardizedFileURL.path.lowercased()
    }

    private func replaced(_ name: String) -> String {
        guard !find.isEmpty else { return name }
        guard regex else { return name.replacingOccurrences(of: find, with: replace) }
        guard let expression = try? NSRegularExpression(pattern: find) else { return name }
        return expression.stringByReplacingMatches(in: name, range: NSRange(name.startIndex..., in: name), withTemplate: replace)
    }
}
