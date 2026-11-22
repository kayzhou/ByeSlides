import SwiftUI

/// The contents of one document window: the source editor or the reading view, plus the toolbar.
struct DocumentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    // An unknown stored mode, e.g. from an older version, falls back to editing.
    @SceneStorage("documentMode") private var mode = DisplayMode.editing
    @SceneStorage("sourceOffset") private var cursorOffset = 0

    @AppStorage(TypographySetting.editorFontSize.key)
    private var editorFontSize = TypographySetting.editorFontSize.defaultValue
    @AppStorage(TypographySetting.readerFontSize.key)
    private var readerFontSize = TypographySetting.readerFontSize.defaultValue
    @AppStorage(TypographySetting.readerLineSpacing.key)
    private var readerLineSpacing = TypographySetting.readerLineSpacing.defaultValue

    // Not `@State`: that is a macro, and the SwiftUIMacros plugin is missing from Command Line Tools.
    private let showsTypography = State(initialValue: false)

    var body: some View {
        content
            .frame(minWidth: 540, minHeight: 360)
            .toolbar {
                Picker("显示模式", selection: $mode) {
                    ForEach(DisplayMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Button { showsTypography.wrappedValue.toggle() } label: { Text(verbatim: "Aa") }
                    .accessibilityLabel("排版设置")
                    .help("排版设置")
                    .popover(isPresented: showsTypography.projectedValue) { TypographyPanel() }
            }
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .editing:
            VStack(spacing: 0) {
                SourceEditor(text: $document.text, cursorOffset: $cursorOffset, fontSize: editorFontSize)
                Divider()
                EditorStatusBar(text: document.text)
            }
        case .reading:
            MarkdownPreview(markdown: document.text, directory: fileURL?.deletingLastPathComponent(),
                            style: ReadingStyle(fontSize: readerFontSize, lineSpacingTenths: readerLineSpacing))
        }
    }
}
