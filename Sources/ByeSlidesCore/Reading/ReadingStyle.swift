/// Reading-mode typography, applied to the page as CSS custom properties.
package struct ReadingStyle: Equatable, Sendable {
    package let fontSize: Int
    package let lineSpacingTenths: Int
    package let pageMargin: Int
    package let justifiesText: Bool
    package let spacesMixedScripts: Bool
    package let hangsPunctuation: Bool

    package init(fontSize: Int, lineSpacingTenths: Int, pageMargin: Int = TypographySetting.pageMargin.defaultValue,
                 justifiesText: Bool = true, spacesMixedScripts: Bool = true, hangsPunctuation: Bool = true) {
        self.fontSize = fontSize
        self.lineSpacingTenths = lineSpacingTenths
        self.pageMargin = pageMargin
        self.justifiesText = justifiesText
        self.spacesMixedScripts = spacesMixedScripts
        self.hangsPunctuation = hangsPunctuation
    }

    /// The default settings, for places that can't read the user's, such as Quick Look.
    package static let standard = ReadingStyle(fontSize: TypographySetting.readerFontSize.defaultValue,
                                               lineSpacingTenths: TypographySetting.readerLineSpacing.defaultValue)

    /// Custom properties consumed by `reading.css`.
    var cssVariables: [(name: String, value: String)] {
        [
            ("--reading-size", "\(fontSize)px"),
            ("--line-height", "\(Double(lineSpacingTenths) / 10)"),
            ("--page-margin", "\(pageMargin)px"),
            ("--paragraph-alignment", justifiesText ? "justify" : "start"),
            ("--mixed-script-spacing", spacesMixedScripts ? "normal" : "no-autospace"),
            ("--hanging-punctuation", hangsPunctuation ? "allow-end" : "none"),
        ]
    }

    /// Declarations for a CSS rule, e.g. `--reading-size: 18px; --line-height: 1.7`.
    package var cssDeclarations: String {
        cssVariables.map { "\($0.name): \($0.value)" }.joined(separator: "; ")
    }

    /// JavaScript that updates the variables on an already loaded page.
    package var updateScript: String {
        cssVariables
            .map { "document.documentElement.style.setProperty('\($0.name)', '\($0.value)');" }
            .joined(separator: "\n")
    }
}

/// The cobalt and snow-white palette shared by AppKit, SwiftUI and WebKit.
package enum Palette {
    package static let paper = "#FFFFFF"
    package static let chrome = "#F4F6F9"
    package static let ink = "#1C2633"
    package static let muted = "#586778"
    package static let emphasis = "#2458A6"
    package static let currentLine = "#EEF4FE"
    package static let caret = "#2463B9"
    package static let selection = "#CADEFA"
    package static let surface = "#F1F5FB"
    package static let border = "#DDE4EF"
    package static let quote = "#A8BBD8"

    static let cssDeclarations = """
    --paper: \(paper); --ink: \(ink); --muted: \(muted); --emphasis: \(emphasis);
    --selection: \(selection); --surface: \(surface); --table-border: \(border); --quote-border: \(quote);
    """
}
