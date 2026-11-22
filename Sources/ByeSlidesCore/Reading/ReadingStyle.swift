/// Reading-mode typography, applied to the page as CSS custom properties.
package struct ReadingStyle: Equatable, Sendable {
    package let fontSize: Int
    package let lineSpacingTenths: Int

    package init(fontSize: Int, lineSpacingTenths: Int) {
        self.fontSize = fontSize
        self.lineSpacingTenths = lineSpacingTenths
    }

    /// The default settings, for places that can't read the user's, such as Quick Look.
    package static let standard = ReadingStyle(fontSize: TypographySetting.readerFontSize.defaultValue,
                                               lineSpacingTenths: TypographySetting.readerLineSpacing.defaultValue)

    /// Custom properties consumed by `reading.css`.
    var cssVariables: [(name: String, value: String)] {
        [
            ("--reading-size", "\(fontSize)px"),
            ("--line-height", "\(Double(lineSpacingTenths) / 10)"),
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

/// Colours shared by the source editor and the reading page.
package enum Palette {
    /// Bold text is shown in this colour instead of a heavier weight. The reading font has a
    /// single weight, so WebKit would otherwise smear the glyphs to fake bold.
    package static let emphasisLight = "#B03A2E"
    package static let emphasisDark = "#F2917A"
}
