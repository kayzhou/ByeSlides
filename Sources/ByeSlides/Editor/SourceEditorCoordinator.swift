import AppKit

extension SourceEditor {
    /// Copies committed edits and the insertion point back into SwiftUI state.
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var owner: SourceEditor
        /// Set while the text is replaced from outside, so the change isn't echoed back into SwiftUI state.
        private var isReplacingText = false

        init(_ owner: SourceEditor) { self.owner = owner }

        /// Shows text that changed outside the editor, e.g. after reverting the document.
        func replaceText(in view: NSTextView, with text: String) {
            isReplacingText = true
            defer { isReplacingText = false }
            let cursor = min(view.selectedRange().location, text.utf16.count)
            view.string = text
            // The text view's undo actions hold ranges in the old text; undoing one would raise an exception.
            if let storage = view.textStorage { view.undoManager?.removeAllActions(withTarget: storage) }
            view.setSelectedRange(NSRange(location: cursor, length: 0))
        }

        func textDidChange(_ notification: Notification) {
            guard let view = committedTextView(notification) else { return }
            if owner.text != view.string { owner.text = view.string }
            syncCursor(view)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = committedTextView(notification) else { return }
            syncCursor(view)
        }

        /// The text view, unless an input method is still composing text in it.
        private func committedTextView(_ notification: Notification) -> NSTextView? {
            guard !isReplacingText, let view = notification.object as? NSTextView, !view.hasMarkedText() else { return nil }
            return view
        }

        private func syncCursor(_ view: NSTextView) {
            let location = view.selectedRange().location
            if location != NSNotFound, owner.cursorOffset != location { owner.cursorOffset = location }
        }
    }
}
