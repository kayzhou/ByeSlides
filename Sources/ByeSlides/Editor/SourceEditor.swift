import AppKit
import SwiftUI

/// Plain-text Markdown source editor backed by `NSTextView`.
struct SourceEditor: NSViewRepresentable {
    @Binding var text: String
    /// UTF-16 offset of the insertion point, restored when the editor is recreated.
    @Binding var cursorOffset: Int
    let fontSize: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollablePlainDocumentContentTextView()
        let view = scroll.documentView as! NSTextView
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.font = font
        view.textContainerInset = NSSize(width: 20, height: 16)
        view.string = text
        let cursor = NSRange(location: min(cursorOffset, text.utf16.count), length: 0)
        view.setSelectedRange(cursor)
        view.scrollRangeToVisible(cursor)
        view.delegate = context.coordinator
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.owner = self
        // The input method owns the marked range until the candidate is committed.
        guard let view = scroll.documentView as? NSTextView, !view.hasMarkedText() else { return }
        if view.font?.pointSize != CGFloat(fontSize) { view.font = font }
        if view.string != text { context.coordinator.replaceText(in: view, with: text) }
    }

    private var font: NSFont {
        .monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
    }
}
