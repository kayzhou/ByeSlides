import AppKit

extension SourceEditor {
    /// Copies committed edits, the selection and the scroll position back to SwiftUI,
    /// and restyles the text after each edit.
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var owner: SourceEditor
        var style: EditorStyle?
        /// Set while the text is replaced from outside, so the change isn't echoed back into SwiftUI state.
        private var isReplacingText = false
        private var scrollObserver: NSObjectProtocol?
        private var pendingRestyle: DispatchWorkItem?
        /// Text changed since the last style pass: where it starts, and how far its end is from the
        /// end of the text. Both stay valid as later edits are made around them.
        private var dirty: (start: Int, distanceFromEnd: Int)?
        private var dirtyNeedsFullPass = false

        /// Above this many UTF-16 units, a full style pass waits for a pause in typing.
        static let immediateStylingLimit = 200_000
        /// Edits larger than this, such as a big paste, restyle the whole text.
        static let localStylingLimit = 20_000

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
            restyle(view)
        }

        /// Restyles the whole text.
        func restyle(_ view: NSTextView) {
            pendingRestyle?.cancel()
            guard let style, let storage = view.textStorage, !view.hasMarkedText() else { return }
            dirty = nil
            dirtyNeedsFullPass = false
            style.apply(to: storage)
            view.typingAttributes = style.baseAttributes
        }

        /// Restyles the lines changed since the last pass, plus one line on each side for setext
        /// headings and tables. Changes to code fences affect every line below, so they restyle everything.
        private func restyleEdits(_ view: NSTextView) {
            guard let style, let storage = view.textStorage else { return }
            // A change that bypassed `shouldChangeText`, such as some undo operations.
            guard let edit = dirty else { return scheduleFullRestyle(view) }
            let text = storage.string as NSString
            let end = max(edit.start, text.length - edit.distanceFromEnd)
            var lines = text.lineRange(for: NSRange(location: min(edit.start, text.length), length: end - min(edit.start, text.length)))
            if lines.location > 0 { lines = NSUnionRange(lines, text.lineRange(for: NSRange(location: lines.location - 1, length: 0))) }
            if NSMaxRange(lines) < text.length { lines = NSUnionRange(lines, text.lineRange(for: NSRange(location: NSMaxRange(lines), length: 0))) }
            if dirtyNeedsFullPass || lines.length > Self.localStylingLimit || Self.containsFence(text.substring(with: lines)) {
                return scheduleFullRestyle(view)
            }
            dirty = nil
            style.apply(to: storage, lines: lines)
            view.typingAttributes = style.baseAttributes
        }

        private func scheduleFullRestyle(_ view: NSTextView) {
            guard (view.textStorage?.length ?? 0) > Self.immediateStylingLimit else { return restyle(view) }
            pendingRestyle?.cancel()
            let work = DispatchWorkItem { [weak self, weak view] in
                if let view { self?.restyle(view) }
            }
            pendingRestyle = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }

        private static func containsFence(_ text: String) -> Bool {
            text.contains("```") || text.contains("~~~")
        }

        // MARK: Delegate

        func textView(_ view: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            let length = (view.string as NSString).length
            if !isReplacingText, NSMaxRange(range) <= length {
                let removed = (view.string as NSString).substring(with: range)
                if Self.containsFence(removed) { dirtyNeedsFullPass = true }
                let start = min(dirty?.start ?? range.location, range.location)
                let distance = min(dirty?.distanceFromEnd ?? Int.max, length - NSMaxRange(range))
                dirty = (start, distance)
            }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let view = committedTextView(notification) else { return }
            if owner.text != view.string { owner.text = view.string }
            restyleEdits(view)
            syncSelection(view)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = committedTextView(notification) else { return }
            syncSelection(view)
        }

        /// The text view, unless an input method is still composing text in it.
        private func committedTextView(_ notification: Notification) -> NSTextView? {
            guard !isReplacingText, let view = notification.object as? NSTextView, !view.hasMarkedText() else { return nil }
            return view
        }

        private func syncSelection(_ view: NSTextView) {
            let range = view.selectedRange()
            guard range.location != NSNotFound else { return }
            if owner.cursorOffset != range.location { owner.cursorOffset = range.location }
            if owner.selection != range { owner.selection = range }
        }

        // MARK: Scroll position

        func observeScrolling(of scroll: NSScrollView) {
            scroll.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
            ) { [weak self, weak scroll] _ in
                MainActor.assumeIsolated {
                    guard let self, let view = scroll?.documentView as? NSTextView else { return }
                    self.owner.anchor.editorScrolled(toOffset: Self.topCharacter(in: view))
                }
            }
        }

        func stopObservingScrolling() {
            scrollObserver.map(NotificationCenter.default.removeObserver)
            scrollObserver = nil
        }

        /// UTF-16 offset of the first character visible at the top of the editor.
        static func topCharacter(in view: NSTextView) -> Int {
            let visible = view.visibleRect
            return view.characterIndexForInsertion(at: NSPoint(x: visible.minX + view.textContainerOrigin.x + 1,
                                                               y: visible.minY + 1))
        }

        /// Puts the cursor back, and shows the passage the reading view was showing, if any.
        func restorePosition(in view: NSTextView) {
            let length = view.string.utf16.count
            let cursor = NSRange(location: min(owner.cursorOffset, length), length: 0)
            view.setSelectedRange(cursor)
            guard owner.anchor.isSet else { return view.scrollRangeToVisible(cursor) }
            let top = owner.anchor.offset(in: view.string)
            Self.scroll(view, toShowOffsetAtTop: top)
            // Typing should happen where the reader was looking, not off screen.
            let visible = view.visibleRect
            let bottom = view.characterIndexForInsertion(at: NSPoint(x: visible.maxX - 1, y: visible.maxY - 1))
            if cursor.location < Self.topCharacter(in: view) || cursor.location > bottom {
                view.setSelectedRange(NSRange(location: top, length: 0))
            }
        }

        static func scroll(_ view: NSTextView, toShowOffsetAtTop offset: Int) {
            guard let layout = view.textLayoutManager, let content = layout.textContentManager,
                  let location = content.location(content.documentRange.location, offsetBy: offset) else { return }
            layout.ensureLayout(for: NSTextRange(location: content.documentRange.location, end: location) ?? content.documentRange)
            guard let fragment = layout.textLayoutFragment(for: location) else { return view.scrollToEndOfDocument(nil) }
            view.scroll(NSPoint(x: 0, y: max(0, fragment.layoutFragmentFrame.minY)))
        }
    }
}
