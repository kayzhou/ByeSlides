/// Reading-mode typography, applied to the page as CSS custom properties.
struct ReadingStyle: Equatable {
    let fontSize: Int
    let lineSpacingTenths: Int

    /// Custom properties consumed by `reading.css`.
    var cssVariables: [(name: String, value: String)] {
        [
            ("--reading-size", "\(fontSize)px"),
            ("--line-height", "\(Double(lineSpacingTenths) / 10)"),
        ]
    }

    /// Declarations for a CSS rule, e.g. `--reading-size: 18px; --line-height: 1.7`.
    var cssDeclarations: String {
        cssVariables.map { "\($0.name): \($0.value)" }.joined(separator: "; ")
    }

    /// JavaScript that updates the variables on an already loaded page.
    var updateScript: String {
        cssVariables
            .map { "document.documentElement.style.setProperty('\($0.name)', '\($0.value)');" }
            .joined(separator: "\n")
    }
}
