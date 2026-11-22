import Foundation

/// The Format menu: wraps the selection in Markdown, or removes the wrapping if it is already there.
enum InlineFormatting {
    enum Style {
        case bold, italic

        var marker: String { self == .bold ? "**" : "*" }

        /// Whether a run of `count` asterisks includes this style: `**` is bold, `*` italic, `***` both.
        func isPresent(inRunOf count: Int) -> Bool {
            self == .bold ? count == 2 || count == 3 : count == 1 || count == 3
        }
    }

    static func toggle(_ style: Style, in text: NSString, selection: NSRange) -> TextEdit {
        let width = style.marker.utf16.count
        let before = asterisks(in: text, endingAt: selection.location)
        let after = asterisks(in: text, startingAt: NSMaxRange(selection))
        // `**word**` with only the word selected.
        if style.isPresent(inRunOf: before), style.isPresent(inRunOf: after) {
            let range = NSRange(location: selection.location - width, length: selection.length + 2 * width)
            return TextEdit(range: range, replacement: text.substring(with: selection),
                            selection: NSRange(location: range.location, length: selection.length))
        }
        // `**word**` selected with its markers.
        let selected = text.substring(with: selection) as NSString
        let leading = asterisks(in: selected, startingAt: 0)
        if selected.length > 2 * leading, style.isPresent(inRunOf: leading),
           style.isPresent(inRunOf: asterisks(in: selected, endingAt: selected.length)) {
            let inner = selected.substring(with: NSRange(location: width, length: selected.length - 2 * width))
            return TextEdit(range: selection, replacement: inner,
                            selection: NSRange(location: selection.location, length: inner.utf16.count))
        }
        return TextEdit(range: selection, replacement: style.marker + (selected as String) + style.marker,
                        selection: NSRange(location: selection.location + width, length: selection.length))
    }

    /// `[selection]()` with the cursor between the parentheses, or `[](address)` when an address is selected.
    static func link(in text: NSString, selection: NSRange) -> TextEdit {
        let selected = text.substring(with: selection)
        if selected.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:\S+$"#, options: .regularExpression) != nil {
            return TextEdit(range: selection, replacement: "[](\(selected))",
                            selection: NSRange(location: selection.location + 1, length: 0))
        }
        let replacement = "[\(selected)]()"
        return TextEdit(range: selection, replacement: replacement,
                        selection: NSRange(location: selection.location + replacement.utf16.count - 1, length: 0))
    }

    private static func asterisks(in text: NSString, endingAt end: Int) -> Int {
        var count = 0
        while end - count > 0, text.character(at: end - count - 1) == 0x2A { count += 1 }
        return count
    }

    private static func asterisks(in text: NSString, startingAt start: Int) -> Int {
        var count = 0
        while start + count < text.length, text.character(at: start + count) == 0x2A { count += 1 }
        return count
    }
}
