import SwiftUI

/// The strip below the source editor showing the character count.
struct EditorStatusBar: View {
    let text: String

    var body: some View {
        HStack {
            Spacer()
            Text("\(text.count) 字符")
        }
        .font(.caption)
        .padding(8)
    }
}
