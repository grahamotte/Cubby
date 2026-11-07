import Foundation

enum CrumbFit {
    static func widths(_ natural: [CGFloat], available: CGFloat) -> [CGFloat] {
        guard natural.reduce(0, +) > available else { return natural }
        guard available > 0 else { return natural.map { _ in 0 } }
        var remaining = available
        var count = CGFloat(natural.count)
        for width in natural.sorted() {
            let cap = remaining / count
            if width > cap { return natural.map { min($0, cap) } }
            remaining -= width
            count -= 1
        }
        return natural
    }
}
