import SwiftUI

/// Popover for the toolbar's **Aa** button.
struct TypographyPanel: View {
    @AppStorage(TypographySetting.editorFontSize.key)
    private var editorFontSize = TypographySetting.editorFontSize.defaultValue
    @AppStorage(TypographySetting.readerFontSize.key)
    private var readerFontSize = TypographySetting.readerFontSize.defaultValue
    @AppStorage(TypographySetting.readerLineSpacing.key)
    private var readerLineSpacing = TypographySetting.readerLineSpacing.defaultValue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("排版设置").font(.headline)
            Stepper(value: $editorFontSize, in: TypographySetting.editorFontSize.range) {
                Text("编辑字号　\(editorFontSize) pt")
            }
            Stepper(value: $readerFontSize, in: TypographySetting.readerFontSize.range) {
                Text("阅读字号　\(readerFontSize) px")
            }
            Stepper(value: $readerLineSpacing, in: TypographySetting.readerLineSpacing.range) {
                Text("阅读行距　\(Double(readerLineSpacing) / 10, specifier: "%.1f") 倍")
            }
            Divider()
            Button("恢复默认值", action: reset)
        }
        .monospacedDigit()
        .padding(18)
        .frame(width: 260)
    }

    private func reset() {
        editorFontSize = TypographySetting.editorFontSize.defaultValue
        readerFontSize = TypographySetting.readerFontSize.defaultValue
        readerLineSpacing = TypographySetting.readerLineSpacing.defaultValue
    }
}
