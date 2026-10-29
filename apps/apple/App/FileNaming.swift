import Foundation

enum FileNaming {
    static func available(_ name: String, in directory: String, copySuffix: Bool = false, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String {
        let join = { (candidate: String) in (directory as NSString).appendingPathComponent(candidate) }
        if !copySuffix && !exists(join(name)) { return name }
        let (base, ext) = split(name)
        let stem = copySuffix ? strippedCopy(base) + " copy" : base
        for number in 1... {
            let label = number == 1 ? (copySuffix ? stem : "\(stem) 2") : (copySuffix ? "\(stem) \(number)" : "\(stem) \(number + 1)")
            let candidate = ext.isEmpty ? label : "\(label).\(ext)"
            if !exists(join(candidate)) { return candidate }
        }
        return name
    }

    static func validationError(for name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "The name can't be empty." }
        if name.contains("/") { return "The name can't contain “/”." }
        if name.contains(":") { return "The name can't contain “:”." }
        if name == "." || name == ".." { return "That name is reserved." }
        if name.utf8.count > 255 { return "The name is too long." }
        return nil
    }

    static func becomesHidden(renaming name: String, to newName: String) -> Bool {
        newName.hasPrefix(".") && !name.hasPrefix(".")
    }

    static func split(_ name: String) -> (String, String) {
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty, !name.hasPrefix(".") || name.dropFirst().contains(".") else { return (name, "") }
        return (String(name.dropLast(ext.count + 1)), ext)
    }

    private static func strippedCopy(_ base: String) -> String {
        if base.hasSuffix(" copy") { return String(base.dropLast(5)) }
        if let range = base.range(of: #" copy \d+$"#, options: .regularExpression) { return String(base[..<range.lowerBound]) }
        return base
    }
}
