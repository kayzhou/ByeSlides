import Foundation

/// Counts words the way Chinese writing is usually measured: each Han character, kana or
/// Hangul syllable counts as one, and each run of other letters or digits counts as one word.
/// Whitespace, punctuation, Markdown symbols and link addresses are not counted.
enum WordCount {
    static func count(_ text: String) -> Int {
        let prose = urls.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        var count = 0
        var inWord = false
        for scalar in prose.unicodeScalars {
            if isCJK(scalar) {
                count += 1
                inWord = false
            } else if scalar.properties.isAlphabetic || scalar.properties.numericType != nil
                        || (inWord && (scalar == "'" || scalar == "\u{2019}")) {
                if !inWord { count += 1 }
                inWord = true
            } else {
                inWord = false
            }
        }
        return count
    }

    /// Link destinations, autolinks and bare web addresses.
    private static let urls = try! NSRegularExpression(
        pattern: #"\]\([^)\n]*\)|<[A-Za-z][A-Za-z0-9+.-]*:[^>\s]*>|https?://[^\s)>\]]+"#)

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3005, 0x3007,          // 々 〇
             0x3040...0x30FF,         // Hiragana, Katakana
             0x31F0...0x31FF,         // Katakana phonetic extensions
             0x3400...0x4DBF,         // CJK Extension A
             0x4E00...0x9FFF,         // CJK Unified Ideographs
             0xAC00...0xD7AF,         // Hangul syllables
             0xF900...0xFAFF,         // CJK compatibility ideographs
             0x20000...0x323AF:       // CJK Extensions B–H
            true
        default:
            false
        }
    }
}
