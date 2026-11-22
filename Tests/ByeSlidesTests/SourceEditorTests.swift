import AppKit
import SwiftUI
import Testing
@testable import ByeSlides

@MainActor
struct SourceEditorTests {
    /// A text view in a window, so it has an undo manager, wired to an editor coordinator.
    private func makeEditor(text: String) -> (NSTextView, SourceEditor.Coordinator, () -> String) {
        var stored = text
        var cursor = 0
        let editor = SourceEditor(text: Binding(get: { stored }, set: { stored = $0 }),
                                  cursorOffset: Binding(get: { cursor }, set: { cursor = $0 }), fontSize: 14)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSTextView(frame: window.contentView!.bounds)
        view.allowsUndo = true
        view.string = text
        window.contentView!.addSubview(view)
        window.makeFirstResponder(view)
        let coordinator = editor.makeCoordinator()
        view.delegate = coordinator
        return (view, coordinator, { stored })
    }

    @Test func typingUpdatesTheDocument() {
        let (view, _, document) = makeEditor(text: "")
        view.insertText("你好", replacementRange: view.selectedRange())
        #expect(document() == "你好")
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
}
