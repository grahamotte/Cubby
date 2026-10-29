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

    static func text(_ name: String, width: CGFloat, font: NSFont, color: NSColor, bold: [NSRange] = []) -> NSAttributedString {
        let wrapping = NSMutableParagraphStyle()
        wrapping.alignment = .center
        wrapping.lineBreakMode = .byWordWrapping
        guard let lines = lines(name, width: width, font: font) else {
            let text = NSMutableAttributedString(string: name, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: wrapping])
            embolden(text, bold, font: font)
            return text
        }
        let truncating = NSMutableParagraphStyle()
        truncating.alignment = .center
        truncating.lineBreakMode = .byTruncatingMiddle
        let text = NSMutableAttributedString(string: lines.first + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: wrapping])
        text.append(NSAttributedString(string: lines.rest, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: truncating]))
        let split = (lines.first as NSString).length
        embolden(text, bold.flatMap { range -> [NSRange] in
            guard range.location < split, NSMaxRange(range) > split else { return [range.location < split ? range : NSRange(location: range.location + 1, length: range.length)] }
            return [NSRange(location: range.location, length: split - range.location), NSRange(location: split + 1, length: NSMaxRange(range) - split)]
        }, font: font)
        return text
    }

    static func embolden(_ text: NSMutableAttributedString, _ ranges: [NSRange], font: NSFont) {
        let boldFont = NSFont.systemFont(ofSize: font.pointSize, weight: .bold)
        for range in ranges where NSMaxRange(range) <= text.length {
            text.addAttribute(.font, value: boldFont, range: range)
        }
    }
}
