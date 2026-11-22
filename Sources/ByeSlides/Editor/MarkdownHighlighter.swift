import Foundation

/// Finds the parts of Markdown source the editor styles. It is a light approximation of
/// CommonMark, tuned to be fast enough to run on every keystroke.
enum MarkdownHighlighter {
    enum Kind: Hashable, Sendable {
        /// An ATX or setext heading line.
        case heading
        /// Text between `**` markers.
        case strong
        /// Link destinations and titles.
        case url
        /// Markdown punctuation: `#`, `*`, `>`, list markers, fences, brackets.
        case syntax
    }

    struct Run: Equatable, Sendable {
        let range: NSRange
        let kind: Kind
    }

    @concurrent
    static func runsInBackground(in string: String) async -> [Run] {
        guard !Task.isCancelled else { return [] }
        return runs(in: string)
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
        let string = text as String
        var blockRange = NSRange(location: 0, length: text.length)
        if let limit {
            // Tables and setext headings need paragraph context. Only fence markers can
            // affect highlighting across a blank line.
            var start = limit.location
            while start > 0 {
                let previous = lineContent(at: start - 1, in: text)
                guard !isBlank(previous, in: text) else { break }
                start = previous.location
            }
            let end = NSMaxRange(text.lineRange(for: NSRange(location: NSMaxRange(limit), length: 0)))
            blockRange = NSRange(location: start, length: end - start)
            fence.enumerateMatches(in: string, options: .withoutAnchoringBounds, range: NSRange(location: 0, length: start)) { match, _, _ in
                guard let marker = match?.range(at: 1) else { return }
                let character = text.character(at: marker.location)
                let line = lineContent(at: marker.location, in: text)
                if let current = openFence {
                    if marker.length >= current.length, character == current.character,
                       closingFence.firstMatch(in: string, options: .anchored, range: line) != nil {
                        code.append(NSRange(location: current.start, length: NSMaxRange(line) - current.start))
                        openFence = nil
                    }
                } else {
                    openFence = (character, marker.length, line.location)
                }
            }
        }
        var lines: [NSRange] = []
        text.enumerateSubstrings(in: blockRange, options: [.byLines, .substringNotRequired]) { _, line, _, _ in lines.append(line) }
        for line in lines {
            func match(_ pattern: NSRegularExpression) -> NSTextCheckingResult? {
                pattern.firstMatch(in: string, options: .anchored, range: line)
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

    private static func lineContent(at offset: Int, in text: NSString) -> NSRange {
        var start = 0
        var end = 0
        text.getLineStart(&start, end: nil, contentsEnd: &end, for: NSRange(location: offset, length: 0))
        return NSRange(location: start, length: end - start)
    }

    private static func isBlank(_ line: NSRange, in text: NSString) -> Bool {
        for index in line.location..<NSMaxRange(line) {
            let character = text.character(at: index)
            if character != 0x20, character != 0x09 { return false }
        }
        return true
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
            var low = 0
            var high = code.count
            while low < high {
                let middle = (low + high) / 2
                if NSMaxRange(code[middle]) <= range.location { low = middle + 1 }
                else { high = middle }
            }
            return low == code.count || code[low].location >= NSMaxRange(range)
        }
        func each(_ pattern: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            for match in pattern.matches(in: string, range: all) where outsideCode(match.range) { body(match) }
        }
        func add(_ match: NSTextCheckingResult, _ groups: [Int], _ kind: Kind) {
            for group in groups where match.range(at: group).location != NSNotFound {
                runs.append(Run(range: match.range(at: group), kind: kind))
            }
        }
        var spans: [NSRange] = []
        each(codeSpan) { match in
            add(match, [1], .syntax)
            runs.append(Run(range: NSRange(location: NSMaxRange(match.range(at: 2)), length: match.range(at: 1).length), kind: .syntax))
            spans.append(match.range)
        }
        addExclusions(spans, to: &code)
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
        addExclusions(addresses, to: &code)
        each(strong) { match in
            add(match, [2], .strong)
            add(match, [1], .syntax)
            runs.append(Run(range: NSRange(location: NSMaxRange(match.range(at: 2)), length: match.range(at: 1).length), kind: .syntax))
        }
        each(emphasis) { match in add(match, [1, 3, 4, 6], .syntax) }
        each(strikethrough) { match in add(match, [1, 3], .syntax) }
    }

    private static func addExclusions(_ added: [NSRange], to ranges: inout [NSRange]) {
        guard !added.isEmpty else { return }
        let sorted = (ranges + added).filter { $0.length > 0 }.sorted { $0.location < $1.location }
        ranges.removeAll(keepingCapacity: true)
        for range in sorted {
            if let last = ranges.last, NSMaxRange(last) >= range.location {
                ranges[ranges.count - 1] = NSUnionRange(last, range)
            } else {
                ranges.append(range)
            }
        }
    }
}
