import ByeSlidesCore
import SwiftUI

/// The strip below the source editor: the word count, and the selection's when there is one.
struct EditorStatusBar: View {
    let source: MarkdownSource
    let selection: NSRange
    private let total = State<Int?>(initialValue: nil)
    private let selected = State<Int?>(initialValue: nil)

    var body: some View {
        HStack {
            Spacer()
            Text(source.text.isEmpty ? Self.summary(total: 0, selected: nil)
                 : Self.summary(total: total.wrappedValue, selected: selection.length > 0 ? selected.wrappedValue : nil))
        }
        .font(.caption)
        .foregroundStyle(Color(nsColor: EditorStyle.muted))
        .monospacedDigit()
        .padding(8)
        .background(Color(nsColor: NSColor(hex: Palette.chrome)))
        .task(id: source) {
            // Coalesce typing bursts. Moving the caret does not invalidate the document count.
            if total.wrappedValue != nil {
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard !Task.isCancelled else { return }
            let count = await WordCount.countInBackground(source.text)
            if !Task.isCancelled { total.wrappedValue = count }
        }
        .task(id: selection.length > 0 ? CountInput(source: source, range: selection) : nil) {
            selected.wrappedValue = nil
            guard selection.length > 0 else { return }
            let count = await WordCount.countInBackground(source.text, in: selection)
            if !Task.isCancelled { selected.wrappedValue = count }
        }
    }

    static func summary(total: Int?, selected: Int?) -> String {
        guard let total else { return "…" }
        guard let selected else { return "\(total.formatted()) 字" }
        return "已选 \(selected.formatted()) 字，共 \(total.formatted()) 字"
    }

    private struct CountInput: Equatable {
        let source: MarkdownSource
        let range: NSRange
    }
}
