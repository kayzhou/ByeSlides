import Foundation

/// The encoding and byte order mark a file was read with, so it can be saved the same way.
struct TextEncoding: Equatable {
    let encoding: String.Encoding
    let byteOrderMark: Data

    static let `default` = TextEncoding(encoding: .utf8, byteOrderMark: Data())

    static let gb18030 = TextEncoding(encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))), byteOrderMark: Data())

    /// Byte order marks recognised when opening a file. UTF-32 comes first because
    /// its little-endian mark begins with the UTF-16 one.
    static let byteOrderMarked: [TextEncoding] = [
        TextEncoding(encoding: .utf32LittleEndian, byteOrderMark: Data([0xFF, 0xFE, 0x00, 0x00])),
        TextEncoding(encoding: .utf32BigEndian, byteOrderMark: Data([0x00, 0x00, 0xFE, 0xFF])),
        TextEncoding(encoding: .utf16LittleEndian, byteOrderMark: Data([0xFF, 0xFE])),
        TextEncoding(encoding: .utf16BigEndian, byteOrderMark: Data([0xFE, 0xFF])),
        TextEncoding(encoding: .utf8, byteOrderMark: Data([0xEF, 0xBB, 0xBF])),
    ]

    /// Tried in order for a file without a byte order mark. GB18030 covers older
    /// Chinese files saved as GBK or GB2312.
    static let unmarked: [TextEncoding] = [.default, .gb18030]

    static func decode(_ data: Data) throws -> (text: String, encoding: TextEncoding) {
        let candidates = byteOrderMarked.first { data.starts(with: $0.byteOrderMark) }.map { [$0] } ?? unmarked
        for format in candidates {
            if let text = String(data: data.dropFirst(format.byteOrderMark.count), encoding: format.encoding) {
                return (text, format)
            }
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    func encode(_ text: String) throws -> Data {
        guard let body = text.data(using: encoding) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return byteOrderMark + body
    }
}
