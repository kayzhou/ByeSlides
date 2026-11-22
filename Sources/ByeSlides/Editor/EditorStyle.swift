import AppKit
import ByeSlidesCore

/// Fonts and colours of the source editor. Syntax is shown through weight and grey only;
/// bold text uses the same emphasis colour as reading mode.
struct EditorStyle: Equatable {
    let fontSize: Int
    let lineSpacingTenths: Int

    var font: NSFont { .monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular) }

    var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = CGFloat(lineSpacingTenths) / 10
        return [.font: font, .paragraphStyle: paragraph, .foregroundColor: Self.ink]
    }

    func attributes(for kind: MarkdownHighlighter.Kind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .heading: [.font: NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .semibold)]
        case .strong: [.foregroundColor: Self.emphasis]
        case .url, .syntax: [.foregroundColor: Self.muted]
        }
    }

    static let emphasis = NSColor(hex: Palette.emphasis)
    static let ink = NSColor(hex: Palette.ink)
    static let muted = NSColor(hex: Palette.muted)

    /// Restyles whole lines of the text, or all of it. Styling only the lines around an edit keeps
    /// typing fast in long documents.
    func apply(to storage: NSTextStorage, lines: NSRange? = nil, preparedRuns: [MarkdownHighlighter.Run]? = nil) {
        let text = storage.string as NSString
        let range = lines.map { text.lineRange(for: $0) } ?? NSRange(location: 0, length: text.length)
        let runs = preparedRuns ?? MarkdownHighlighter.runs(in: storage.string, limitedTo: lines == nil ? nil : range)
        // Built once per pass; creating fonts and dictionaries per run dominates the cost otherwise.
        let base = baseAttributes
        let styles: [MarkdownHighlighter.Kind: [NSAttributedString.Key: Any]] = [
            .heading: attributes(for: .heading), .strong: attributes(for: .strong),
            .url: attributes(for: .url), .syntax: attributes(for: .syntax),
        ]
        storage.beginEditing()
        storage.setAttributes(base, range: range)
        // Headings first so their font doesn't hide colours applied inside them.
        for kind in [MarkdownHighlighter.Kind.heading, .url, .strong, .syntax] {
            for run in runs where run.kind == kind {
                let clipped = NSIntersectionRange(run.range, range)
                if clipped.length > 0 { storage.addAttributes(styles[kind]!, range: clipped) }
            }
        }
        storage.endEditing()
    }
}

extension NSColor {
    /// `#RRGGBB` in sRGB.
    convenience init(hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
