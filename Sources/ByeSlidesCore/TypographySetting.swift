/// A user-adjustable typography value stored in `UserDefaults` and shared by every window.
package struct TypographySetting: Sendable {
    package let key: String
    package let defaultValue: Int
    package let range: ClosedRange<Int>

    /// Monospaced font size in the source editor, in points.
    package static let editorFontSize = TypographySetting(key: "editorFontSize", defaultValue: 16, range: 12...32)
    /// Body font size in reading mode, in CSS pixels.
    package static let readerFontSize = TypographySetting(key: "readerFontSize", defaultValue: 18, range: 12...36)
    /// Line height in the source editor, in tenths of the font size.
    package static let editorLineSpacing = TypographySetting(key: "editorSpacingTenths", defaultValue: 15, range: 10...24)
    /// Line height in reading mode, in tenths of the font size.
    package static let readerLineSpacing = TypographySetting(key: "readerSpacingTenths", defaultValue: 17, range: 12...24)

    package static let all: [TypographySetting] = [editorFontSize, editorLineSpacing, readerFontSize, readerLineSpacing]
}
