import ByeSlidesCore
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
    @AppStorage(TypographySetting.editorLineSpacing.key)
    private var editorLineSpacing = TypographySetting.editorLineSpacing.defaultValue
    @AppStorage(TypographySetting.readerFontSize.key)
    private var readerFontSize = TypographySetting.readerFontSize.defaultValue
    @AppStorage(TypographySetting.readerLineSpacing.key)
    private var readerLineSpacing = TypographySetting.readerLineSpacing.defaultValue

    // Not `@State`: that is a macro, and the SwiftUIMacros plugin is missing from Command Line Tools.
    private let showsTypography = State(initialValue: false)
    private let selection = State(initialValue: NSRange(location: 0, length: 0))
    /// Remote images load only after the reader asks, and only for this window.
    private let allowsRemoteImages = State(initialValue: false)
    private let anchor = State(initialValue: ScrollAnchor())
    @StateObject private var finder = ReadingFinder()

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
            .onChange(of: mode) { finder.isVisible = false }
            .focusedSceneValue(\.displayMode, $mode)
            .focusedSceneValue(\.printableDocument, PrintableDocument(
                markdown: document.text, directory: directory, style: readingStyle,
                allowsRemoteImages: allowsRemoteImages.wrappedValue, title: title))
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .editing:
            VStack(spacing: 0) {
                SourceEditor(text: $document.text, cursorOffset: $cursorOffset, selection: selection.projectedValue,
                             style: EditorStyle(fontSize: editorFontSize, lineSpacingTenths: editorLineSpacing),
                             documentFolder: directory, anchor: anchor.wrappedValue)
                Divider()
                EditorStatusBar(text: document.text, selection: selection.wrappedValue)
            }
        case .reading:
            VStack(spacing: 0) {
                if finder.isVisible {
                    ReadingFindBar(finder: finder)
                    Divider()
                }
                MarkdownPreview(markdown: document.text, directory: directory, style: readingStyle,
                                allowsRemoteImages: allowsRemoteImages.wrappedValue, anchor: anchor.wrappedValue,
                                finder: finder, loadRemoteImages: { allowsRemoteImages.wrappedValue = true })
            }
        }
    }

    private var directory: URL? { fileURL?.deletingLastPathComponent() }
    private var title: String { fileURL?.deletingPathExtension().lastPathComponent ?? "未命名" }
    private var readingStyle: ReadingStyle {
        ReadingStyle(fontSize: readerFontSize, lineSpacingTenths: readerLineSpacing)
    }
}
