import Foundation

/// A replacement to make in the editor, and the selection to show afterwards. All ranges are UTF-16.
struct TextEdit: Equatable {
    var range: NSRange
    var replacement: String
    var selection: NSRange

    /// The text after applying the edit; used by tests.
    func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}

extension NSString {
    /// The range of the line containing `location`, without its line break.
    func lineContentRange(at location: Int) -> NSRange {
        var start = 0, contentsEnd = 0
        getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }
}
