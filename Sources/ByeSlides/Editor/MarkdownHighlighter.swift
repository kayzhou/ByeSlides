import Foundation

/// Finds the parts of Markdown source the editor styles. It is a light approximation of
/// CommonMark, tuned to be fast enough to run on every keystroke.
enum MarkdownHighlighter {
    enum Kind: Hashable {
        /// An ATX or setext heading line.
        case heading
        /// Text between `**` markers.
        case strong
        /// Link destinations and titles.
        case url
        /// Markdown punctuation: `#`, `*`, `>`, list markers, fences, brackets.
        case syntax
    }

    struct Run: Equatable {
        let range: NSRange
        let kind: Kind
    }

    /// Runs in the whole text, or at least those in `range` when given. A range should cover whole
    /// lines; runs that only partly overlap it may be returned too.
    static func runs(in string: String, limitedTo range: NSRange? = nil) -> [Run] {
        let text = string as NSString
        var runs: [Run] = []
        var code: [NSRange] = []
        scanBlocks(text, limitedTo: range, into: &runs, code: &code)
        scanInline(text, in: range ?? NSRange(location: 0, length: text.length), into: &runs, code: &code)
        return runs
    }

    // MARK: Blocks

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    private static let fence = regex(#"^ {0,3}(`{3,}|~{3,})"#)
    private static let closingFence = regex(#"^ {0,3}(`{3,}|~{3,})[ \t]*$"#)
    private static let atxHeading = regex(#"^ {0,3}(#{1,6})(?=[ \t]|$).*?([ \t]+#+[ \t]*)?$"#)
    private static let setextUnderline = regex(#"^ {0,3}(=+|-+)[ \t]*$"#)
    private static let thematicBreak = regex(#"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    private static let quote = regex(#"^(?: {0,3}>[ \t]?)+"#)
    private static let listMarker = regex(#"^[ \t]*(?:[-*+]|\d{1,9}[.)])(?=[ \t])(?:[ \t]+\[[ xX]\](?=[ \t]|$))?"#)
    private static let tableDelimiter = regex(#"^[ \t]*\|?(?:[ \t]*:?-+:?[ \t]*\|)+(?:[ \t]*:?-+:?[ \t]*)?\|?[ \t]*$"#)
    private static let definition = regex(#"^ {0,3}\[[^\]\n]+\]:[ \t]*\S.*$"#)

    private static func scanBlocks(_ text: NSString, limitedTo limit: NSRange?, into runs: inout [Run], code: inout [NSRange]) {
        var openFence: (character: unichar, length: Int, start: Int)?
        var previousParagraph: NSRange?
        var inTable = false
        var lines: [NSRange] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length),
                                 options: [.byLines, .substringNotRequired]) { _, line, _, _ in lines.append(line) }
        let string = text as String
        // With a limit, lines before the block holding it are only checked for code fences,
        // which can open far above. Setext headings and tables only look back within a block.
        var firstStyledLine = 0
        var lastStyledLine = lines.count - 1
        if let limit {
            let first = lines.firstIndex { NSMaxRange($0) >= limit.location } ?? lines.count
            firstStyledLine = first
            while firstStyledLine > 0, !isBlank(lines[firstStyledLine - 1], in: text) { firstStyledLine -= 1 }
            lastStyledLine = lines.lastIndex { $0.location <= NSMaxRange(limit) } ?? -1
        }
        for (index, line) in lines.enumerated() {
            if index > lastStyledLine { break }
            func match(_ pattern: NSRegularExpression) -> NSTextCheckingResult? {
                pattern.firstMatch(in: string, options: .anchored, range: line)
            }
            if index < firstStyledLine {
                trackFence(line, in: text, open: &openFence, code: &code)
                continue
            }
            if let open = openFence {
                if let close = match(closingFence), close.range(at: 1).length >= open.length,
                   text.character(at: close.range(at: 1).location) == open.character {
                    runs.append(Run(range: line, kind: .syntax))
                    code.append(NSRange(location: open.start, length: NSMaxRange(line) - open.start))
                    openFence = nil
                }
                continue
            }
            let isBlank = isBlank(line, in: text)
            defer { if isBlank { inTable = false } }
            if let open = match(fence) {
                let marker = open.range(at: 1)
                openFence = (text.character(at: marker.location), marker.length, line.location)
                runs.append(Run(range: line, kind: .syntax))
                previousParagraph = nil
                continue
            }
            if let heading = match(atxHeading) {
                runs.append(Run(range: line, kind: .heading))
                runs.append(Run(range: heading.range(at: 1), kind: .syntax))
                if heading.range(at: 2).location != NSNotFound { runs.append(Run(range: heading.range(at: 2), kind: .syntax)) }
                previousParagraph = nil
                continue
            }
            if let paragraph = previousParagraph, match(setextUnderline) != nil {
                runs.append(Run(range: paragraph, kind: .heading))
                runs.append(Run(range: line, kind: .syntax))
                previousParagraph = nil
                continue
            }
            if match(thematicBreak) != nil || match(definition) != nil {
                runs.append(Run(range: line, kind: match(definition) != nil ? .url : .syntax))
                previousParagraph = nil
                continue
            }
            var content = line
            for pattern in [quote, listMarker] {
                if let prefix = pattern.firstMatch(in: string, options: .anchored, range: content) {
                    runs.append(Run(range: prefix.range, kind: .syntax))
                    content = NSRange(location: NSMaxRange(prefix.range), length: NSMaxRange(content) - NSMaxRange(prefix.range))
                }
            }
            if match(tableDelimiter) != nil, let header = previousParagraph, text.substring(with: header).contains("|") {
                inTable = true
                markPipes(in: header, of: text, into: &runs)
                runs.append(Run(range: line, kind: .syntax))
            } else if inTable {
                markPipes(in: line, of: text, into: &runs)
            }
            previousParagraph = isBlank || content.length < line.length ? nil : line
        }
        if let open = openFence {
            code.append(NSRange(location: open.start, length: text.length - open.start))
        }
    }

    private static func isBlank(_ line: NSRange, in text: NSString) -> Bool {
        for index in line.location..<NSMaxRange(line) {
            let character = text.character(at: index)
            if character != 0x20, character != 0x09 { return false }
        }
        return true
    }

    /// Fence bookkeeping for lines that are not styled. Checks characters before using a regex.
    private static func trackFence(_ line: NSRange, in text: NSString,
                                   open: inout (character: unichar, length: Int, start: Int)?, code: inout [NSRange]) {
        var index = line.location
        while index < NSMaxRange(line), index - line.location < 4, text.character(at: index) == 0x20 { index += 1 }
        guard NSMaxRange(line) - index >= 3 else { return }
        let character = text.character(at: index)
        guard character == 0x60 || character == 0x7E,
              text.character(at: index + 1) == character, text.character(at: index + 2) == character else { return }
        let string = text as String
        if let current = open {
            if let close = closingFence.firstMatch(in: string, options: .anchored, range: line),
               close.range(at: 1).length >= current.length, text.character(at: close.range(at: 1).location) == current.character {
                code.append(NSRange(location: current.start, length: NSMaxRange(line) - current.start))
                open = nil
            }
        } else if let opening = fence.firstMatch(in: string, options: .anchored, range: line) {
            open = (text.character(at: opening.range(at: 1).location), opening.range(at: 1).length, line.location)
        }
    }

    private static func markPipes(in line: NSRange, of text: NSString, into runs: inout [Run]) {
        for index in line.location..<NSMaxRange(line) where text.character(at: index) == 0x7C {
            runs.append(Run(range: NSRange(location: index, length: 1), kind: .syntax))
        }
    }

    // MARK: Inline

    private static let codeSpan = try! NSRegularExpression(pattern: #"(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)"#)
    private static let autolink = try! NSRegularExpression(pattern: #"<[A-Za-z][A-Za-z0-9+.-]*:[^>\s]*>"#)
    private static let link = try! NSRegularExpression(
        pattern: #"(!?\[)[^\]\n]*(\]\()([^()\s]*(?:\([^()\s]*\)[^()\s]*)*(?:[ \t]+"[^"\n]*")?)(\))"#)
    private static let referenceLink = try! NSRegularExpression(pattern: #"(!?\[)[^\]\n]+(\]\[)([^\]\n]*)(\])"#)
    private static let strong = try! NSRegularExpression(pattern: #"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let emphasis = try! NSRegularExpression(
        pattern: #"(?<![*\\])(\*)(?![\s*])(.+?)(?<![\s*\\])(\*)(?!\*)|(?<![_\w])(_)(?![\s_])(.+?)(?<![\s_])(_)(?![_\w])"#)
    private static let strikethrough = try! NSRegularExpression(pattern: #"(~~)(?=\S)(.+?)(?<=\S)(~~)"#)

    private static func scanInline(_ text: NSString, in all: NSRange, into runs: inout [Run], code: inout [NSRange]) {
        let string = text as String
        func outsideCode(_ range: NSRange) -> Bool {
            !code.contains { NSIntersectionRange($0, range).length > 0 }
        }
        func each(_ pattern: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            for match in pattern.matches(in: string, range: all) where outsideCode(match.range) { body(match) }
        }
        func add(_ match: NSTextCheckingResult, _ groups: [Int], _ kind: Kind) {
            for group in groups where match.range(at: group).location != NSNotFound {
                runs.append(Run(range: match.range(at: group), kind: kind))
            }
        }
        each(codeSpan) { match in
            add(match, [1], .syntax)
            runs.append(Run(range: NSRange(location: NSMaxRange(match.range(at: 2)), length: match.range(at: 1).length), kind: .syntax))
            code.append(match.range)
        }
        var addresses: [NSRange] = []
        each(autolink) { match in
            runs.append(Run(range: match.range, kind: .url))
            addresses.append(match.range)
        }
        for pattern in [link, referenceLink] {
            each(pattern) { match in
                add(match, [1, 2, 4], .syntax)
                add(match, [3], .url)
                addresses.append(match.range(at: 3))
            }
        }
        code += addresses
        each(strong) { match in
            add(match, [2], .strong)
            add(match, [1], .syntax)
            runs.append(Run(range: NSRange(location: NSMaxRange(match.range(at: 2)), length: match.range(at: 1).length), kind: .syntax))
        }
        each(emphasis) { match in add(match, [1, 3, 4, 6], .syntax) }
        each(strikethrough) { match in add(match, [1, 3], .syntax) }
    }
}
