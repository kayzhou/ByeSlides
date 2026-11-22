import AppKit
import ByeSlidesCore
import SwiftUI

struct SourceEditorPreferences: Equatable {
    var margin = TypographySetting.pageMargin.defaultValue
    var highlightsLine = AppPreferences.highlightLine.defaultValue
    var continuesLists = AppPreferences.continueLists.defaultValue
    var typingTone: TypingTone? = nil
    var typingVolume = AppPreferences.typingVolume.defaultValue
}

/// Plain-text Markdown source editor backed by `MarkdownTextView`.
struct SourceEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    let style: EditorStyle
    let documentFolder: URL?
    let anchor: ScrollAnchor
    var isActive = true
    var preferences = SourceEditorPreferences()

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
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.documentFolder = documentFolder
        view.preferences = preferences
        let coordinator = context.coordinator
        coordinator.style = style
        coordinator.restyle(view)
        view.delegate = coordinator
        coordinator.observeScrolling(of: scroll)
        coordinator.observeUndo(in: view)
        // Wait for SwiftUI to give the view its size, so positions can be laid out.
        DispatchQueue.main.async { coordinator.activate(view) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let becameActive = isActive && !coordinator.owner.isActive
        coordinator.owner = self
        guard let view = scroll.documentView as? MarkdownTextView else { return }
        if becameActive {
            DispatchQueue.main.async { coordinator.activate(view) }
        }
        // The input method owns the marked range until the candidate is committed.
        guard !view.hasMarkedText() else { return }
        view.documentFolder = documentFolder
        if view.preferences != preferences { view.preferences = preferences }
        if coordinator.style != style {
            let top = isActive ? Coordinator.topCharacter(in: view) : 0
            coordinator.style = style
            coordinator.restyle(view)
            if top > 0 { Coordinator.scroll(view, toShowOffsetAtTop: top) }
        }
        if view.string != text { coordinator.replaceText(in: view, with: text) }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.cancelPendingRestyle()
        coordinator.stopObservingScrolling()
        coordinator.stopObservingUndo()
    }
}
