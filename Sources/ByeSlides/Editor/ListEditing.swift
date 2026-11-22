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

        func contentColumn(with marker: String) -> Int {
            ListEditing.column(after: spacing, startingAt: ListEditing.column(after: indent) + marker.utf16.count)
        }

        func nextOrderedMarker() -> String? {
            guard let number, number < 999_999_999 else { return nil }
            let digits = String(number + 1)
            let padding = max(0, marker.utf16.count - 1 - digits.count)
            return String(repeating: "0", count: padding) + digits + marker.suffix(1)
        }
    }

    private static let pattern = try! NSRegularExpression(
        pattern: #"^([ \t]*)([-*+]|(\d{1,9})([.)]))([ \t]+)(\[[ xX]\][ \t]+)?"#)

    static func item(onLineAt location: Int, in text: NSString) -> Item? {
        let line = text.lineContentRange(at: location)
        return item(in: text.substring(with: line), at: line)
    }

    private static func item(in content: String, at line: NSRange) -> Item? {
        guard let match = pattern.firstMatch(
            in: content, options: .anchored, range: NSRange(location: 0, length: line.length)
        ) else { return nil }
        let text = content as NSString
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
        if let number = item.number {
            guard let marker = item.nextOrderedMarker() else { return nil }
            return continueOrderedList(in: text, at: selection.location, after: item, nextNumber: number + 1, marker: marker)
        }
        let continuation = "\n" + item.indent + item.marker + item.spacing + (item.isTask ? "[ ] " : "")
        return TextEdit(range: selection, replacement: continuation,
                        selection: NSRange(location: selection.location + continuation.utf16.count, length: 0))
    }

    private static func continueOrderedList(
        in text: NSString, at cursor: Int, after current: Item, nextNumber: Int, marker: String
    ) -> TextEdit? {
        let lineEnd = NSMaxRange(text.lineRange(for: current.line))
        let contentEnd = NSMaxRange(current.line)
        let newline = lineEnd == contentEnd ? "\n" : text.substring(
            with: NSRange(location: contentEnd, length: lineEnd - contentEnd)
        )
        let continuation = newline + current.indent + marker + current.spacing + (current.isTask ? "[ ] " : "")
        let selection = NSRange(location: cursor + continuation.utf16.count, length: 0)

        // Combine the insertion and the following marker edits into one undoable change.
        var replacement = continuation
        var copiedThrough = cursor
        func replace(_ range: NSRange, with value: String) {
            replacement += text.substring(with: NSRange(location: copiedThrough, length: range.location - copiedThrough))
            replacement += value
            copiedThrough = NSMaxRange(range)
        }

        let level = column(after: current.indent)
        var previousContentColumn = current.contentColumn(with: current.marker)
        var indentationIncrease = current.contentColumn(with: marker) - previousContentColumn
        var expected = nextNumber
        var offset = lineEnd
        while offset < text.length {
            let start = offset
            var end = start
            text.getLineStart(nil, end: &offset, contentsEnd: &end, for: NSRange(location: start, length: 0))
            let line = NSRange(location: start, length: end - start)
            let content = text.substring(with: line)
            let indent = content.prefix { $0 == " " || $0 == "\t" }
            guard indent.endIndex != content.endIndex else { continue }
            let indentColumn = column(after: indent)
            if indentColumn > level {
                // When a marker grows, keep its indented content aligned under it.
                if indentationIncrease > 0, indentColumn >= previousContentColumn {
                    let endOfIndent = line.location + indent.utf16.count
                    replace(NSRange(location: endOfIndent, length: 0), with: String(repeating: " ", count: indentationIncrease))
                }
                continue
            }
            guard indentColumn == level,
                  let sibling = item(in: content, at: line),
                  sibling.marker.last == current.marker.last,
                  sibling.number == expected else { break }
            guard let newMarker = sibling.nextOrderedMarker() else { return nil }
            replace(NSRange(location: line.location + indent.utf16.count, length: sibling.marker.utf16.count), with: newMarker)
            expected += 1
            previousContentColumn = sibling.contentColumn(with: sibling.marker)
            indentationIncrease = sibling.contentColumn(with: newMarker) - previousContentColumn
        }
        return TextEdit(range: NSRange(location: cursor, length: copiedThrough - cursor),
                        replacement: replacement, selection: selection)
    }

    private static func column(after whitespace: some StringProtocol, startingAt start: Int = 0) -> Int {
        whitespace.reduce(start) { column, character in
            column + (character == "\t" ? 4 - column % 4 : 1)
        }
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
