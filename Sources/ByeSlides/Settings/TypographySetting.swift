/// A user-adjustable typography value stored in `UserDefaults` and shared by every window.
struct TypographySetting: Sendable {
    let key: String
    let defaultValue: Int
    let range: ClosedRange<Int>

    /// Monospaced font size in the source editor, in points.
    static let editorFontSize = TypographySetting(key: "editorFontSize", defaultValue: 16, range: 12...32)
    /// Body font size in reading mode, in CSS pixels.
    static let readerFontSize = TypographySetting(key: "readerFontSize", defaultValue: 18, range: 12...36)
    /// Line height in reading mode, in tenths of the font size.
    static let readerLineSpacing = TypographySetting(key: "readerSpacingTenths", defaultValue: 17, range: 12...24)
}
