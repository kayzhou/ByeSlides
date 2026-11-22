import Foundation

/// List editing for Return, Tab and Shift-Tab. Each function returns nil when the cursor is not
/// in a list item, so the key keeps its usual meaning.
enum ListEditing {
    /// A list item marker at the start of a line: `- `, `* `, `+ `, `1. ` or `1) `, then an optional task box.
    struct Item {
        let line: NSRange
        let indent: String
        let marker: String
        let number: Int?
        let spacing: String
        let isTask: Bool
        /// UTF-16 length from the line start through the task box, if any.
        let prefixLength: Int

        /// Indentation that nests this item under the one before it.
        var nestingWidth: Int { (marker + spacing).utf16.count }
    }

    private static let pattern = try! NSRegularExpression(
        pattern: #"^([ \t]*)([-*+]|(\d{1,9})([.)]))([ \t]+)(\[[ xX]\][ \t]+)?"#)

    static func item(onLineAt location: Int, in text: NSString) -> Item? {
        let line = text.lineContentRange(at: location)
        guard let match = pattern.firstMatch(in: text as String, options: .anchored, range: line) else { return nil }
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : text.substring(with: range)
        }
        return Item(line: line, indent: group(1) ?? "", marker: group(2) ?? "-", number: group(3).flatMap { Int($0) },
                    spacing: group(5) ?? " ", isTask: group(6) != nil, prefixLength: match.range.length)
    }

    /// Return: starts the next item, or ends the list when pressed on an empty item.
    static func newline(in text: NSString, selection: NSRange) -> TextEdit? {
        guard selection.length == 0, let item = item(onLineAt: selection.location, in: text) else { return nil }
        let prefixEnd = item.line.location + item.prefixLength
        guard selection.location >= prefixEnd else { return nil }
        let content = text.substring(with: NSRange(location: prefixEnd, length: NSMaxRange(item.line) - prefixEnd))
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            return TextEdit(range: item.line, replacement: "", selection: NSRange(location: item.line.location, length: 0))
        }
        let marker = item.number.map { "\($0 + 1)\(item.marker.suffix(1))" } ?? item.marker
        let continuation = "\n" + item.indent + marker + item.spacing + (item.isTask ? "[ ] " : "")
        return TextEdit(range: selection, replacement: continuation,
                        selection: NSRange(location: selection.location + continuation.utf16.count, length: 0))
    }

    /// Tab: nests the selected list items one level deeper.
    static func indent(in text: NSString, selection: NSRange) -> TextEdit? {
        shift(text, selection) { item in String(repeating: " ", count: item.nestingWidth) + item.indent }
    }

    /// Shift-Tab: moves the selected list items one level out.
    static func outdent(in text: NSString, selection: NSRange) -> TextEdit? {
        shift(text, selection) { item in
            if item.indent.hasPrefix("\t") { return String(item.indent.dropFirst()) }
            let spaces = item.indent.prefix { $0 == " " }.count
            return String(item.indent.dropFirst(min(spaces, item.nestingWidth)))
        }
    }

    /// Replaces the indentation of every list item on the selected lines.
    private static func shift(_ text: NSString, _ selection: NSRange, newIndent: (Item) -> String) -> TextEdit? {
        guard item(onLineAt: selection.location, in: text) != nil else { return nil }
        var lines: [NSRange] = []
        text.enumerateSubstrings(in: text.lineRange(for: selection), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            lines.append(range)
        }
        if lines.isEmpty { lines = [text.lineContentRange(at: selection.location)] }
        let start = lines[0].location
        let block = NSMutableString(string: text.substring(with: NSRange(location: start, length: NSMaxRange(lines.last!) - start)))
        var firstLineDelta = 0
        var totalDelta = 0
        for (index, line) in lines.enumerated().reversed() {
            guard let item = item(onLineAt: line.location, in: text) else { continue }
            let indent = newIndent(item)
            let delta = indent.utf16.count - item.indent.utf16.count
            block.replaceCharacters(in: NSRange(location: line.location - start, length: item.indent.utf16.count), with: indent)
            totalDelta += delta
            if index == 0 { firstLineDelta = delta }
        }
        guard totalDelta != 0 || firstLineDelta != 0 else { return nil }
        let location = max(start, selection.location + firstLineDelta)
        let length = max(0, selection.length + totalDelta - firstLineDelta)
        return TextEdit(range: NSRange(location: start, length: NSMaxRange(lines.last!) - start), replacement: block as String,
                        selection: NSRange(location: location, length: selection.length == 0 ? 0 : length))
    }
}
