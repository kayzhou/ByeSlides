import Foundation
import Testing
@testable import ByeSlides
@testable import ByeSlidesCore

struct MarkdownDocumentTests {
    @Test(arguments: [
        (Data(), String.Encoding.utf8),
        (Data([0xEF, 0xBB, 0xBF]), .utf8),
        (Data([0xFF, 0xFE]), .utf16LittleEndian),
        (Data([0xFE, 0xFF]), .utf16BigEndian),
        (Data([0xFF, 0xFE, 0x00, 0x00]), .utf32LittleEndian),
        (Data([0x00, 0x00, 0xFE, 0xFF]), .utf32BigEndian),
        (Data(), TextEncoding.gb18030.encoding),
    ])
    func savesInTheEncodingItWasReadWith(bom: Data, encoding: String.Encoding) throws {
        let original = bom + "# 标题\n正文".data(using: encoding)!
        var document = try MarkdownDocument(data: original)
        #expect(document.text == "# 标题\n正文")

        document.text += "。"
        #expect(try document.data() == bom + "# 标题\n正文。".data(using: encoding)!)
    }

    @Test func opensGBKFilesWithoutMistakingUTF8ForThem() throws {
        #expect(try MarkdownDocument(data: Data([0xB1, 0xEA, 0xCC, 0xE2])).text == "标题")
        #expect(try MarkdownDocument(data: Data("标题".utf8)).text == "标题")
    }

    @Test func rejectsBytesNoSupportedEncodingCanRead() {
        #expect(throws: CocoaError.self) { try MarkdownDocument(data: Data([0x80, 0xFF])) }
    }

    @Test func newDocumentIsEmptyUTF8() throws {
        let document = MarkdownDocument()
        #expect(document.text.isEmpty)
        #expect(try MarkdownDocument(text: "a").data() == Data("a".utf8))
    }
}
