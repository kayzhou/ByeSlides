import Foundation
import Testing
@testable import ByeSlides

/// Applies an edit to `text` with the cursor at `|` (or a selection between `[` and `]`), and
/// returns the result with the new cursor or selection marked the same way.
private func edit(_ marked: String, _ make: (NSString, NSRange) -> TextEdit?) -> String? {
    var text = marked
    let selection: NSRange
    if !marked.contains("|"), let start = text.firstIndex(of: "["), let end = text.firstIndex(of: "]") {
        let location = text.utf16.distance(from: text.startIndex, to: start)
        let length = text.utf16.distance(from: text.index(after: start), to: end)
        text.remove(at: end)
        text.remove(at: start)
        selection = NSRange(location: location, length: length)
    } else {
        let index = text.firstIndex(of: "|")!
        selection = NSRange(location: text.utf16.distance(from: text.startIndex, to: index), length: 0)
        text.remove(at: index)
    }
    guard let result = make(text as NSString, selection) else { return nil }
    let output = NSMutableString(string: result.applied(to: text))
    if result.selection.length == 0 {
        output.insert("|", at: result.selection.location)
    } else {
        output.insert("]", at: NSMaxRange(result.selection))
        output.insert("[", at: result.selection.location)
    }
    return output as String
}

struct ListEditingTests {
    @Test(arguments: [
        ("- 苹果|", "- 苹果\n- |"),
        ("  * 嵌套|", "  * 嵌套\n  * |"),
        ("9. 第九|", "9. 第九\n10. |"),
        ("1) 甲|", "1) 甲\n2) |"),
        ("- [x] 完成|", "- [x] 完成\n- [ ] |"),
        ("- 前|后", "- 前\n- |后"),
        ("- |", "|"),
        ("- [ ] |", "|"),
    ])
    func returnKey(before: String, after: String) {
        #expect(edit(before, ListEditing.newline) == after)
    }

    @Test(arguments: [
        ("1. 第一项|\n2. 第二项\n3. 第三项", "1. 第一项\n2. |\n3. 第二项\n4. 第三项"),
        ("1) [x] 前🙂|后\n2) [x] 保留任务", "1) [x] 前🙂\n2) [ ] |后\n3) [x] 保留任务"),
        ("1. 甲|\r\n2. 乙", "1. 甲\r\n2. |\r\n3. 乙"),
        ("1. 甲|\n   1. 子项\n\n2. 乙\n   1. 另一子项\n3. 丙",
         "1. 甲\n2. |\n   1. 子项\n\n3. 乙\n   1. 另一子项\n4. 丙"),
        ("1. 外层\n   1. 甲|\n   2. 乙\n2. 另一外层",
         "1. 外层\n   1. 甲\n   2. |\n   3. 乙\n2. 另一外层"),
        ("8. 八|\n9. 九\n   - 子项\n10. 十",
         "8. 八\n9. |\n10. 九\n    - 子项\n11. 十"),
        ("1. 甲|\n2. 乙\n\n新段落\n\n3. 独立列表",
         "1. 甲\n2. |\n3. 乙\n\n新段落\n\n3. 独立列表"),
        ("1. 甲|\n3. 乙\n4. 丙", "1. 甲\n2. |\n3. 乙\n4. 丙"),
        ("1. 甲|\n2) 乙", "1. 甲\n2. |\n2) 乙"),
    ])
    func middleInsertionRenumbersFollowingItems(before: String, after: String) {
        #expect(edit(before, ListEditing.newline) == after)
    }

    @Test(arguments: ["普通段落|", "|- 光标在标记前", "-不是列表|"])
    func returnOutsideListsKeepsItsUsualMeaning(text: String) {
        #expect(edit(text, ListEditing.newline) == nil)
    }

    @Test func tabNestsUnderThePreviousItem() {
        #expect(edit("- 甲\n- 乙|", ListEditing.indent) == "- 甲\n  - 乙|")
        #expect(edit("1. 甲\n2. 乙|", ListEditing.indent) == "1. 甲\n   2. 乙|")
        #expect(edit("段落|", ListEditing.indent) == nil)
    }

    @Test func shiftTabMovesItemsOut() {
        #expect(edit("- 甲\n  - 乙|", ListEditing.outdent) == "- 甲\n- 乙|")
        #expect(edit("\t- 乙|", ListEditing.outdent) == "- 乙|")
        #expect(edit("- 顶层|", ListEditing.outdent) == nil)
    }

    @Test func tabShiftsEverySelectedItem() {
        #expect(edit("[- 甲\n- 乙]", ListEditing.indent) == "  [- 甲\n  - 乙]")
    }
}

struct InlineFormattingTests {
    private func bold(_ text: String) -> String? { edit(text) { InlineFormatting.toggle(.bold, in: $0, selection: $1) } }
    private func italic(_ text: String) -> String? { edit(text) { InlineFormatting.toggle(.italic, in: $0, selection: $1) } }
    private func link(_ text: String) -> String? { edit(text) { InlineFormatting.link(in: $0, selection: $1) } }

    @Test func boldWrapsAndUnwraps() {
        #expect(bold("这是[重点]") == "这是**[重点]**")
        #expect(bold("这是**[重点]**") == "这是[重点]")
        #expect(bold("这是[**重点**]") == "这是[重点]")
        #expect(bold("空|白") == "空**|**白")
    }

    @Test func italicLeavesBoldAlone() {
        #expect(italic("**[词]**") == "***[词]***")
        #expect(italic("***[词]***") == "**[词]**")
        #expect(bold("***[词]***") == "*[词]*")
        #expect(italic("*[词]*") == "[词]")
    }

    @Test func linkPutsTheCursorWhereTypingContinues() {
        #expect(link("[文字]") == "[文字](|)")
        #expect(link("[https://example.com]") == "[|](https://example.com)")
        #expect(link("|") == "[](|)")
    }
}

struct MarkdownHighlighterTests {
    private func spans(_ text: String, _ kind: MarkdownHighlighter.Kind) -> [String] {
        MarkdownHighlighter.runs(in: text).filter { $0.kind == kind }.map { (text as NSString).substring(with: $0.range) }
    }

    @Test func headings() {
        #expect(spans("# 标题 #\n正文", .heading) == ["# 标题 #"])
        #expect(spans("# 标题 #\n正文", .syntax) == ["#", " #"])
        #expect(spans("## 没有结尾符号\n正文", .heading) == ["## 没有结尾符号"])
        #expect(spans("## 没有结尾符号\n正文", .syntax) == ["##"])
        #expect(spans("#\n####### 七个", .heading) == ["#"])
        #expect(spans("标题\n===\n\n#不是标题", .heading) == ["标题"])
    }

    @Test func inlineMarkup() {
        let text = "**粗**、*斜*、~~删~~、`code`、[文字](https://a.com \"题\")"
        #expect(spans(text, .strong) == ["粗"])
        #expect(spans(text, .url) == ["https://a.com \"题\""])
        #expect(spans(text, .syntax) == ["`", "`", "[", "](", ")", "**", "**", "*", "*", "~~", "~~"])
    }

    @Test func blockMarkers() {
        #expect(spans("> 引用\n- [ ] 任务\n1. 一\n\n---", .syntax) == ["> ", "- [ ]", "1.", "---"])
        #expect(spans("| a | b |\n|---|:-:|\n| 1 | 2 |", .syntax).filter { $0 == "|" }.count == 6)
    }

    @Test func nothingInsideCode() {
        let text = "```\n# 不是标题 **不粗**\n```\n`**也不粗**`\n    "
        #expect(spans(text, .heading).isEmpty)
        #expect(spans(text, .strong).isEmpty)
        #expect(spans(text, .syntax).contains("```"))
    }

    @Test func emphasisNeedsWordBoundariesForUnderscores() {
        #expect(spans("snake_case_name 和 _强调_", .syntax) == ["_", "_"])
    }
}

struct WordCountTests {
    @Test(arguments: [
        ("你好，世界！", 4),
        ("Hello, world.", 2),
        ("我用 iPhone 15 写作", 6),
        ("# 标题\n\n- **重点** don't", 5),
        ("看[这里](https://example.com/very/long)和 https://a.com/x", 4),
        ("日本語のテキスト", 8),
        ("   \n\n", 0),
    ])
    func counts(text: String, words: Int) {
        #expect(WordCount.count(text) == words)
    }

    @Test func statusBarShowsTheSelection() {
        #expect(EditorStatusBar.summary(total: 4, selected: nil) == "4 字")
        #expect(EditorStatusBar.summary(total: 4, selected: 2) == "已选 2 字，共 4 字")
    }
}

struct SourceLinesTests {
    @Test func countsLinesLikeMarkdownIt() {
        let text = "a\nb\r\nc\rd"
        #expect(SourceLines.line(atOffset: 0, in: text) == 0)
        #expect(SourceLines.line(atOffset: 2, in: text) == 1)
        #expect(SourceLines.line(atOffset: 5, in: text) == 2)
        #expect(SourceLines.line(atOffset: 7, in: text) == 3)
        #expect((0...4).map { SourceLines.offset(ofLine: $0, in: text) } == [0, 2, 5, 7, 8])
    }

    @MainActor @Test func anchorConvertsBetweenModes() {
        let text = "一\n二\n三\n四"
        let anchor = ScrollAnchor()
        #expect(!anchor.readerDidScroll)
        anchor.editorScrolled(toOffset: 4)
        #expect(anchor.line(in: text) == 2)
        anchor.readerScrolled(toLine: 3)
        #expect(anchor.readerDidScroll)
        #expect(anchor.offset(in: text) == 6)
    }
}

struct ImageImporterTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func copiesFilesFromElsewhereAndAvoidsNameClashes() throws {
        let document = try folder(), elsewhere = try folder()
        let photo = elsewhere.appendingPathComponent("旅行 照片 (1).png")
        try Data([1]).write(to: photo)
        #expect(try ImageImporter.importFile(photo, into: document) == "![旅行 照片 (1)](assets/旅行%20照片%20%281%29.png)")
        #expect(try ImageImporter.importFile(photo, into: document) == "![旅行 照片 (1)](assets/旅行%20照片%20%281%29-2.png)")
    }

    @Test func referencesFilesAlreadyBesideTheDocument() throws {
        let document = try folder()
        try FileManager.default.createDirectory(at: document.appendingPathComponent("img"), withIntermediateDirectories: true)
        let photo = document.appendingPathComponent("img/a.png")
        try Data([1]).write(to: photo)
        #expect(try ImageImporter.importFile(photo, into: document) == "![a](img/a.png)")
        #expect(!FileManager.default.fileExists(atPath: document.appendingPathComponent("assets").path))
    }

    @Test func namesPastedImagesByTime() throws {
        let document = try folder()
        let date = DateComponents(calendar: .current, year: 2026, month: 11, day: 22, hour: 9, minute: 5, second: 7).date!
        #expect(try ImageImporter.importData(Data([1]), type: .png, into: document, date: date) == "![](assets/image-20261122-090507.png)")
    }
}
