import AppKit
import SwiftUI
import Testing
@testable import ByeSlides
@testable import ByeSlidesCore

@MainActor
struct SourceEditorTests {
    /// A source editor's text view in a window, so it has an undo manager, wired to its coordinator.
    private func makeEditor(text: String, folder: URL? = nil) -> (MarkdownTextView, SourceEditor.Coordinator, () -> String) {
        var stored = MarkdownSource(text)
        var selection = NSRange(location: 0, length: 0)
        let style = EditorStyle(fontSize: 14, lineSpacingTenths: 15)
        let editor = SourceEditor(source: Binding(get: { stored }, set: { stored = $0 }),
                                  selection: Binding(get: { selection }, set: { selection = $0 }),
                                  style: style, documentFolder: folder, anchor: ScrollAnchor())
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = MarkdownTextView.scrollablePlainDocumentContentTextView()
        scroll.frame = window.contentView!.bounds
        let view = scroll.documentView as! MarkdownTextView
        view.allowsUndo = true
        view.isRichText = false
        view.string = text
        view.documentFolder = folder
        window.contentView!.addSubview(scroll)
        window.makeFirstResponder(view)
        let coordinator = editor.makeCoordinator()
        coordinator.style = style
        view.delegate = coordinator
        coordinator.observeUndo(in: view)
        return (view, coordinator, { stored.text })
    }

    @Test func typingUpdatesTheDocument() {
        let (view, _, document) = makeEditor(text: "")
        view.insertText("你好", replacementRange: view.selectedRange())
        #expect(document() == "你好")
    }

    @Test func preservesTheExactUnicodeSpellingOfAnEdit() {
        let (view, coordinator, document) = makeEditor(text: "é")
        defer { withExtendedLifetime(coordinator) {} }
        let decomposed = "e\u{0301}"
        view.insertText(decomposed, replacementRange: NSRange(location: 0, length: 1))
        #expect(Array(document().utf8) == Array(decomposed.utf8))
    }

    @Test func turningOffListContinuationKeepsReturnAsAPlainNewline() {
        let (view, coordinator, document) = makeEditor(text: "- item")
        defer { withExtendedLifetime(coordinator) {} }
        view.preferences.continuesLists = false
        view.setSelectedRange(NSRange(location: 6, length: 0))
        view.insertNewline(nil)
        #expect(document() == "- item\n")
    }

    @Test func committingMarkedTextUpdatesTheDocument() {
        let (view, coordinator, document) = makeEditor(text: "ab")
        defer { withExtendedLifetime(coordinator) {} }
        view.setSelectedRange(NSRange(location: 2, length: 0))
        view.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: view.selectedRange())
        #expect(view.hasMarkedText())
        #expect(document() == "ab")

        view.insertText("中", replacementRange: view.markedRange())
        #expect(!view.hasMarkedText())
        #expect(document() == "ab中")
    }

    // Undoing typing after the text was replaced used to raise NSRangeException and crash.
    @Test func undoAfterOutsideChangeDoesNotCrash() throws {
        let (view, coordinator, _) = makeEditor(text: "")
        view.insertText("hello world", replacementRange: view.selectedRange())
        view.breakUndoCoalescing()
        view.setSelectedRange(NSRange(location: 5, length: 0))

        coordinator.replaceText(in: view, with: "x")
        #expect(view.selectedRange() == NSRange(location: 1, length: 0))

        let undoManager = try #require(view.undoManager)
        while undoManager.canUndo { undoManager.undo() }
        #expect(view.string == "x")
    }

    @Test func outsideChangeKeepsTheCursor() {
        let (view, coordinator, document) = makeEditor(text: "abcdef")
        view.setSelectedRange(NSRange(location: 3, length: 0))
        coordinator.replaceText(in: view, with: "abcdefgh")
        #expect(view.selectedRange() == NSRange(location: 3, length: 0))
        #expect(document() == "abcdef", "The replacement must not be written back into the binding.")
    }

    @Test func returnContinuesListsAndUndoesInOneStep() throws {
        let (view, _, document) = makeEditor(text: "- [x] 买菜")
        // Outside an event loop, group each key press the way AppKit does for each event.
        let undoManager = try #require(view.undoManager)
        undoManager.groupsByEvent = false
        func press(_ action: () -> Void) {
            undoManager.beginUndoGrouping()
            action()
            undoManager.endUndoGrouping()
        }
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        press { view.insertNewline(nil) }
        #expect(document() == "- [x] 买菜\n- [ ] ")
        press { view.insertNewline(nil) }
        #expect(document() == "- [x] 买菜\n", "Return on an empty item ends the list.")
        undoManager.undo()
        #expect(view.string == "- [x] 买菜\n- [ ] ")
    }

    @Test func returnRenumbersTheListAndUndoesInOneStep() throws {
        let original = "1. 第一项\n2. 第二项\n3. 第三项"
        let (view, coordinator, document) = makeEditor(text: original)
        defer { withExtendedLifetime(coordinator) {} }
        let undoManager = try #require(view.undoManager)
        undoManager.groupsByEvent = false
        view.setSelectedRange(NSRange(location: "1. 第一项".utf16.count, length: 0))

        undoManager.beginUndoGrouping()
        view.insertNewline(nil)
        undoManager.endUndoGrouping()

        #expect(document() == "1. 第一项\n2. \n3. 第二项\n4. 第三项")
        #expect(view.selectedRange() == NSRange(location: "1. 第一项\n2. ".utf16.count, length: 0))
        undoManager.undo()
        #expect(view.string == original)
        #expect(document() == original)
        undoManager.redo()
        #expect(document() == "1. 第一项\n2. \n3. 第二项\n4. 第三项")
    }

    @Test func formatMenuWrapsTheSelection() {
        let (view, _, document) = makeEditor(text: "重点内容")
        view.setSelectedRange(NSRange(location: 0, length: 2))
        view.toggleMarkdownBold(nil)
        #expect(document() == "**重点**内容")
        #expect(view.selectedRange() == NSRange(location: 2, length: 2))
        view.toggleMarkdownBold(nil)
        #expect(document() == "重点内容")
        #expect(view.undoManager?.undoActionName == "粗体")
    }

    @Test func stylesMarkdownAfterEachEdit() throws {
        let (view, _, _) = makeEditor(text: "")
        view.insertText("# 标题\n正文 **重点**", replacementRange: view.selectedRange())
        let storage = try #require(view.textStorage)
        let heading = try #require(storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)
        #expect(storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor == EditorStyle.ink)
        #expect(heading.fontDescriptor.symbolicTraits.contains(.bold))
        let marker = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(marker == EditorStyle.muted)
        let strongOffset = (view.string as NSString).range(of: "重点").location
        #expect(storage.attribute(.foregroundColor, at: strongOffset, effectiveRange: nil) as? NSColor == EditorStyle.emphasis)
        let body = try #require(storage.attribute(.font, at: 5, effectiveRange: nil) as? NSFont)
        #expect(!body.fontDescriptor.symbolicTraits.contains(.bold))
        let paragraph = storage.attribute(.paragraphStyle, at: 5, effectiveRange: nil) as? NSParagraphStyle
        #expect(paragraph?.lineHeightMultiple == 1.5)
    }

    /// Font weight and colour at every offset, for comparing two style passes.
    private func styleSummary(_ storage: NSAttributedString) -> [String] {
        (0..<storage.length).map { index in
            let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
            return "\(font?.fontDescriptor.symbolicTraits.contains(.bold) == true ? "B" : "-")\(color?.description ?? "nil")"
        }
    }

    // Edits restyle only nearby lines; the result must match styling the whole text.
    @Test func restylingEditedLinesMatchesAFullPass() throws {
        let text = "# 标题\n\n段落一\n\n```\n# 代码里不是标题\n```\n\n表头 | 列\n--- | ---\n格 | 格\n\n末段"
        let (view, coordinator, _) = makeEditor(text: text)
        coordinator.restyle(view)
        for (anchor, typed) in [("段落一", "**新**"), ("# 代码里", "## "), ("格 | 格", "|加"), ("末段", "\n===")] {
            let location = NSMaxRange((view.string as NSString).range(of: anchor))
            view.setSelectedRange(NSRange(location: location, length: 0))
            view.insertText(typed, replacementRange: view.selectedRange())
            let reference = NSTextStorage(string: view.string)
            try #require(coordinator.style).apply(to: reference)
            #expect(styleSummary(view.textStorage!) == styleSummary(reference), "after typing \(typed) after \(anchor)")
        }
        let code = (view.string as NSString).range(of: "# 代码里")
        #expect((view.textStorage!.attribute(.font, at: code.location + 2, effectiveRange: nil) as? NSFont)?
            .fontDescriptor.symbolicTraits.contains(.bold) == false, "Headings inside code are not styled.")
    }

    @Test func removingAFenceRestylesTheLinesBelow() throws {
        let (view, coordinator, _) = makeEditor(text: "```\n# 原本在代码里\n```")
        coordinator.restyle(view)
        let heading = (view.string as NSString).range(of: "原本")
        #expect((view.textStorage!.attribute(.font, at: heading.location, effectiveRange: nil) as? NSFont)?
            .fontDescriptor.symbolicTraits.contains(.bold) == false)
        view.setSelectedRange(NSRange(location: 0, length: 4))
        view.insertText("", replacementRange: view.selectedRange())
        let moved = (view.string as NSString).range(of: "原本")
        #expect((view.textStorage!.attribute(.font, at: moved.location, effectiveRange: nil) as? NSFont)?
            .fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test func backgroundStylingDoesNotApplyAnOldSnapshotAfterTyping() async throws {
        let text = "# 标题\n\n" + String(repeating: "正文 **重点**\n\n", count: 2_000)
        let (view, coordinator, document) = makeEditor(text: text)
        coordinator.restyle(view)
        view.insertText("x", replacementRange: NSRange(location: 0, length: 1))

        let storage = try #require(view.textStorage)
        let last = (view.string as NSString).range(of: "重点", options: .backwards).location
        let until = ContinuousClock.now + .seconds(3)
        while storage.attribute(.foregroundColor, at: last, effectiveRange: nil) as? NSColor != EditorStyle.emphasis,
              ContinuousClock.now < until {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(storage.attribute(.foregroundColor, at: last, effectiveRange: nil) as? NSColor == EditorStyle.emphasis)
        let font = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == false)
        #expect(document().hasPrefix("x 标题"))
    }

    @Test func keepsPageMarginsWhenTheEditorResizes() throws {
        let (view, _, _) = makeEditor(text: "")
        let scroll = try #require(view.enclosingScrollView)
        let container = try #require(view.textContainer)
        for width in [540.0, 1000.0, 1400.0] {
            scroll.setFrameSize(NSSize(width: width, height: 300))
            #expect(view.bounds.width == scroll.contentSize.width)
            #expect(view.textContainerOrigin.x + container.lineFragmentPadding == 32)
            #expect(container.size.width - 2 * container.lineFragmentPadding == view.bounds.width - 64)
        }
    }

    @Test func pastedImagesAreCopiedNextToTheDocument() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (view, _, document) = makeEditor(text: "图：", folder: folder)
        view.setSelectedRange(NSRange(location: 2, length: 0))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        let png = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            .representation(using: .png, properties: [:])!
        pasteboard.setData(png, forType: .png)

        #expect(view.insertImages(from: pasteboard) == true)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("assets").path)
        #expect(files.count == 1)
        #expect(document() == "图：![](assets/\(files[0]))")

        pasteboard.clearContents()
        pasteboard.setString("文字", forType: .string)
        pasteboard.setData(png, forType: .png)
        #expect(view.insertImages(from: pasteboard) == nil, "Text with a picture of it pastes as text.")
    }
}
