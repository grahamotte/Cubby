import AppKit

enum TileLabel {
    static func lines(_ name: String, width: CGFloat, font: NSFont) -> (first: String, rest: String)? {
        let string = NSAttributedString(string: name, attributes: [.font: font])
        let typesetter = CTTypesetterCreateWithAttributedString(string)
        let first = CTTypesetterSuggestLineBreak(typesetter, 0, width)
        guard first > 0, first < string.length else { return nil }
        let second = CTTypesetterSuggestLineBreak(typesetter, first, width)
        guard first + second < string.length else { return nil }
        let text = name as NSString
        return (text.substring(to: first), text.substring(from: first))
    }

    static func text(_ name: String, width: CGFloat, font: NSFont, color: NSColor) -> NSAttributedString {
        let wrapping = NSMutableParagraphStyle()
        wrapping.alignment = .center
        wrapping.lineBreakMode = .byWordWrapping
        guard let lines = lines(name, width: width, font: font) else {
            return NSAttributedString(string: name, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: wrapping])
        }
        let truncating = NSMutableParagraphStyle()
        truncating.alignment = .center
        truncating.lineBreakMode = .byTruncatingMiddle
        let text = NSMutableAttributedString(string: lines.first + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: wrapping])
        text.append(NSAttributedString(string: lines.rest, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: truncating]))
        return text
    }
}
