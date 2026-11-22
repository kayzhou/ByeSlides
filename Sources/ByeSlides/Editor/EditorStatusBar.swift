import SwiftUI

/// The strip below the source editor: the word count, and the selection's when there is one.
struct EditorStatusBar: View {
    let text: String
    let selection: NSRange

    var body: some View {
        HStack {
            Spacer()
            Text(Self.summary(text: text, selection: selection))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .padding(8)
    }

    static func summary(text: String, selection: NSRange) -> String {
        let total = WordCount.count(text).formatted()
        let nsText = text as NSString
        guard selection.length > 0, NSMaxRange(selection) <= nsText.length else { return "\(total) 字" }
        let selected = WordCount.count(nsText.substring(with: selection)).formatted()
        return "已选 \(selected) 字，共 \(total) 字"
    }
}
