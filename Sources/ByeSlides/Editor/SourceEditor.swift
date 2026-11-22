import AppKit
import SwiftUI

/// Plain-text Markdown source editor backed by `MarkdownTextView`.
struct SourceEditor: NSViewRepresentable {
    @Binding var text: String
    /// UTF-16 offset of the insertion point, restored when the editor is recreated.
    @Binding var cursorOffset: Int
    @Binding var selection: NSRange
    let style: EditorStyle
    let documentFolder: URL?
    let anchor: ScrollAnchor

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = MarkdownTextView.scrollablePlainDocumentContentTextView()
        let view = scroll.documentView as! MarkdownTextView
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isIncrementalSearchingEnabled = true
        view.string = text
        view.documentFolder = documentFolder
        view.columnWidth = style.columnWidth
        let coordinator = context.coordinator
        coordinator.style = style
        coordinator.restyle(view)
        view.delegate = coordinator
        coordinator.observeScrolling(of: scroll)
        // Wait for SwiftUI to give the view its size, so positions can be laid out.
        DispatchQueue.main.async {
            coordinator.restorePosition(in: view)
            view.window?.makeFirstResponder(view)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.owner = self
        // The input method owns the marked range until the candidate is committed.
        guard let view = scroll.documentView as? MarkdownTextView, !view.hasMarkedText() else { return }
        view.documentFolder = documentFolder
        if coordinator.style != style {
            coordinator.style = style
            view.columnWidth = style.columnWidth
            coordinator.restyle(view)
        }
        if view.string != text { coordinator.replaceText(in: view, with: text) }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObservingScrolling()
    }
}
