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
        private weak var undoView: NSTextView?
        private var textBeforeUndo: String?
        private var pendingRestyle: Task<Void, Never>?
        /// Text changed since the last style pass: where it starts, and how far its end is from the
        /// end of the text. Both stay valid as later edits are made around them.
        private var dirty: (start: Int, distanceFromEnd: Int)?
        private var dirtyNeedsFullPass = false

        /// Longer documents get their base typography immediately and syntax runs off the main thread.
        static let immediateStylingLimit = 16_000
        /// Edits larger than this, such as a big paste, restyle the whole text.
        static let localStylingLimit = 20_000

        init(_ owner: SourceEditor) { self.owner = owner }

        /// Markdown is source text. Compare UTF-16 code units without the normalization
        /// Swift String equality performs for canonically equivalent spellings.
        static func text(in view: NSTextView, matches source: String) -> Bool {
            view.textStorage?.mutableString.isEqual(to: source) ?? false
        }

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
            guard let style, let storage = view.textStorage, !view.hasMarkedText() else { return }
            if storage.length > Self.immediateStylingLimit {
                style.apply(to: storage, preparedRuns: [])
                view.typingAttributes = style.baseAttributes
                scheduleFullRestyle(view, after: .zero)
            } else {
                finishRestyle(in: view)
            }
        }

        private func finishRestyle(in view: NSTextView, runs: [MarkdownHighlighter.Run]? = nil) {
            guard let style, let storage = view.textStorage, !view.hasMarkedText() else { return }
            cancelPendingRestyle()
            dirty = nil
            dirtyNeedsFullPass = false
            style.apply(to: storage, preparedRuns: runs)
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

        private func scheduleFullRestyle(_ view: NSTextView, after delay: Duration = .milliseconds(150)) {
            guard (view.textStorage?.length ?? 0) > Self.immediateStylingLimit else { return finishRestyle(in: view) }
            dirtyNeedsFullPass = true
            pendingRestyle?.cancel()
            pendingRestyle = Task { [weak self, weak view] in
                if delay > .zero { try? await Task.sleep(for: delay) }
                guard !Task.isCancelled, let text = view?.string else { return }
                let runs = await MarkdownHighlighter.runsInBackground(in: text)
                guard !Task.isCancelled, let view, Self.text(in: view, matches: text) else { return }
                self?.finishRestyle(in: view, runs: runs)
            }
        }

        func cancelPendingRestyle() {
            pendingRestyle?.cancel()
            pendingRestyle = nil
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
            commitEdit(in: view)
        }

        private func commitEdit(in view: NSTextView) {
            if !Self.text(in: view, matches: owner.text) { owner.text = view.string }
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
            // The status bar only uses selected text. AppKit keeps the insertion
            // point, avoiding a SwiftUI update for every move of the caret.
            let selection = range.length > 0 ? range : NSRange(location: 0, length: 0)
            if owner.selection != selection { owner.selection = selection }
        }

        // AppKit can restore the text storage without calling textDidChange.
        func observeUndo(in view: NSTextView) {
            undoView = view
            let center = NotificationCenter.default
            for name in [Notification.Name.NSUndoManagerWillUndoChange, .NSUndoManagerWillRedoChange] {
                center.addObserver(self, selector: #selector(willReplayEdit(_:)), name: name, object: nil)
            }
            for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
                center.addObserver(self, selector: #selector(didReplayEdit(_:)), name: name, object: nil)
            }
        }

        func stopObservingUndo() {
            NotificationCenter.default.removeObserver(self)
            undoView = nil
            textBeforeUndo = nil
        }

        @objc private func willReplayEdit(_ notification: Notification) {
            guard let view = undoView, let manager = notification.object as? UndoManager, view.undoManager === manager else { return }
            textBeforeUndo = view.string
        }

        @objc private func didReplayEdit(_ notification: Notification) {
            guard let view = undoView, let manager = notification.object as? UndoManager, view.undoManager === manager else { return }
            defer { textBeforeUndo = nil }
            guard !isReplacingText, !view.hasMarkedText(), let textBeforeUndo,
                  !Self.text(in: view, matches: textBeforeUndo), !Self.text(in: view, matches: owner.text) else { return }
            // SwiftUI's document binding must not create a new undo entry during synchronization.
            manager.disableUndoRegistration()
            defer { manager.enableUndoRegistration() }
            commitEdit(in: view)
        }

        // MARK: Scroll position

        func observeScrolling(of scroll: NSScrollView) {
            scroll.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
            ) { [weak self, weak scroll] _ in
                MainActor.assumeIsolated {
                    guard let self, self.owner.isActive, let view = scroll?.documentView as? NSTextView else { return }
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

        /// Returns focus to the text view. Its native selection stays intact unless the
        /// reader moved to another passage and the old insertion point is now off screen.
        func activate(_ view: NSTextView) {
            guard owner.isActive, let window = view.window else { return }
            if owner.anchor.readerDidScroll {
                let top = owner.anchor.offset(in: view.string)
                Self.scroll(view, toShowOffsetAtTop: top)
                let visible = view.visibleRect
                let bottom = view.characterIndexForInsertion(at: NSPoint(x: visible.maxX - 1, y: visible.maxY - 1))
                let selection = view.selectedRange()
                if selection.location < Self.topCharacter(in: view) || NSMaxRange(selection) > bottom {
                    view.setSelectedRange(NSRange(location: top, length: 0))
                }
                owner.anchor.editorScrolled(toOffset: Self.topCharacter(in: view))
            }
            window.makeFirstResponder(view)
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
