import Foundation

/// Converts between UTF-16 offsets and zero-based line numbers, counting lines the way
/// markdown-it does: "\r\n", "\r" and "\n" each end a line.
enum SourceLines {
    static func line(atOffset offset: Int, in text: String) -> Int {
        var line = 0
        var previous: UInt16 = 0
        for unit in text.utf16.prefix(max(0, offset)) {
            if unit == 0x0D || (unit == 0x0A && previous != 0x0D) { line += 1 }
            previous = unit
        }
        return line
    }

    /// The offset where a line starts, or the end of the text if it has fewer lines.
    static func offset(ofLine line: Int, in text: String) -> Int {
        guard line > 0 else { return 0 }
        let units = Array(text.utf16)
        var current = 0
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit == 0x0D || unit == 0x0A {
                if unit == 0x0D, index + 1 < units.count, units[index + 1] == 0x0A { index += 1 }
                current += 1
                if current == line { return index + 1 }
            }
            index += 1
        }
        return units.count
    }
}

/// The passage at the top of the window, shared by both display modes so that switching
/// keeps it in view. Updated while scrolling, without causing SwiftUI updates.
@MainActor
final class ScrollAnchor {
    private enum Position {
        /// Reported by the source editor: the first visible character.
        case offset(Int)
        /// Reported by the reading page: the first visible source line.
        case line(Int)
    }

    /// Nil until either mode has scrolled, so the editor first opens at the restored cursor.
    private var position: Position?

    var readerDidScroll: Bool {
        if case .line = position { return true }
        return false
    }

    func editorScrolled(toOffset offset: Int) { position = .offset(offset) }
    func readerScrolled(toLine line: Int) { position = .line(line) }

    func line(in text: String) -> Int {
        switch position {
        case .offset(let offset): SourceLines.line(atOffset: offset, in: text)
        case .line(let line): line
        case nil: 0
        }
    }

    /// Offset of the first character to show at the top of the editor.
    func offset(in text: String) -> Int {
        switch position {
        case .offset(let offset): min(offset, text.utf16.count)
        case .line(let line): SourceLines.offset(ofLine: line, in: text)
        case nil: 0
        }
    }
}
