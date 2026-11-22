import ByeSlidesCore
import SwiftUI

/// The contents of one document window: the source editor or the reading view, plus the toolbar.
struct DocumentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?
    let folderBrowser: FolderBrowser

    @AppStorage("showsFolderSidebar") private var showsFolderSidebar = false

    @SceneStorage("documentMode") private var storedMode: DisplayMode?
    @SceneStorage("documentZoomPercent") private var zoom = DocumentZoom.standard
    @AppStorage(AppPreferences.openingMode.key) private var openingMode = AppPreferences.openingMode.defaultValue
    @AppStorage(TypographySetting.pageMargin.key) private var pageMargin = TypographySetting.pageMargin.defaultValue
    @AppStorage(TypographySetting.editorFontSize.key)
    private var editorFontSize = TypographySetting.editorFontSize.defaultValue
    @AppStorage(TypographySetting.editorLineSpacing.key)
    private var editorLineSpacing = TypographySetting.editorLineSpacing.defaultValue
    @AppStorage(TypographySetting.readerFontSize.key)
    private var readerFontSize = TypographySetting.readerFontSize.defaultValue
    @AppStorage(TypographySetting.readerLineSpacing.key)
    private var readerLineSpacing = TypographySetting.readerLineSpacing.defaultValue
    @AppStorage(AppPreferences.highlightLine.key) private var highlightLine = AppPreferences.highlightLine.defaultValue
    @AppStorage(AppPreferences.showWordCount.key) private var showWordCount = AppPreferences.showWordCount.defaultValue
    @AppStorage(AppPreferences.continueLists.key) private var continueLists = AppPreferences.continueLists.defaultValue
    @AppStorage(AppPreferences.readerJustifies.key) private var justifies = AppPreferences.readerJustifies.defaultValue
    @AppStorage(AppPreferences.readerSpacedScripts.key) private var spacedScripts = AppPreferences.readerSpacedScripts.defaultValue
    @AppStorage(AppPreferences.readerHangingPunctuation.key) private var hangingPunctuation = AppPreferences.readerHangingPunctuation.defaultValue
    @AppStorage(AppPreferences.remoteImages.key) private var remoteImages = AppPreferences.remoteImages.defaultValue
    @AppStorage(AppPreferences.typingSound.key) private var typingSound = AppPreferences.typingSound.defaultValue
    @AppStorage(AppPreferences.typingTone.key) private var typingTone = AppPreferences.typingTone.defaultValue
    @AppStorage(AppPreferences.typingVolume.key) private var typingVolume = AppPreferences.typingVolume.defaultValue

    // Not `@State`: that is a macro, and the SwiftUIMacros plugin is missing from Command Line Tools.
    private let selection = State(initialValue: NSRange(location: 0, length: 0))
    private let hasOpenedEditor = State(initialValue: false)
    /// Remote images load only after the reader asks, and only for this window.
    private let approvedRemoteImages = State(initialValue: false)
    private let anchor = State(initialValue: ScrollAnchor())
    @StateObject private var finder = ReadingFinder()

    var body: some View {
        HSplitView {
            if showsFolderSidebar {
                FolderSidebar(browser: folderBrowser, currentFile: fileURL)
                    .frame(minWidth: 172, idealWidth: 220, maxWidth: 320)
            }
            content.frame(minWidth: 540, minHeight: 360)
        }
            .tint(Color(nsColor: EditorStyle.emphasis))
            .toolbarBackground(Color(nsColor: NSColor(hex: Palette.chrome)), for: .windowToolbar)
            .background {
                if fileURL == nil { DraftDocumentName() }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(showsFolderSidebar ? "隐藏文件夹侧栏" : "显示文件夹侧栏", systemImage: "sidebar.left") {
                        showsFolderSidebar.toggle()
                    }
                    .labelStyle(.iconOnly)
                    .help(showsFolderSidebar ? "隐藏文件夹侧栏" : "显示文件夹侧栏")
                }
                ToolbarItem {
                    Picker("显示模式", selection: modeSelection) {
                        ForEach(DisplayMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .onAppear { if storedMode == nil { storedMode = openingMode } }
            .onChange(of: mode) { finder.isVisible = false }
            .onChange(of: remoteImages) { approvedRemoteImages.wrappedValue = false }
            .focusedSceneValue(\.displayMode, modeSelection)
            .focusedSceneValue(\.documentZoom, $zoom)
            .focusedSceneValue(\.folderSidebar, $showsFolderSidebar)
            .focusedSceneValue(\.openFolder, {
                showsFolderSidebar = true
                folderBrowser.chooseFolder(startingAt: directory)
            })
            .focusedSceneValue(\.printableDocument, PrintableDocument(
                markdown: document.text, directory: directory, style: readingStyle(zoom: .standard),
                allowsRemoteImages: allowsRemoteImages, title: title))
    }

    private var content: some View {
        ZStack {
            // Keep AppKit's selection and undo stack across a reading session. Opening
            // directly in reading mode still defers creation of the editor until needed.
            if mode == .editing || hasOpenedEditor.wrappedValue {
                editor
                    .opacity(mode == .editing ? 1 : 0)
                    .allowsHitTesting(mode == .editing)
                    .accessibilityHidden(mode != .editing)
                    .onAppear { hasOpenedEditor.wrappedValue = true }
            }
            if mode == .reading {
                VStack(spacing: 0) {
                    if finder.isVisible {
                        ReadingFindBar(finder: finder)
                        Divider()
                    }
                    MarkdownPreview(markdown: document.text, directory: directory, style: readingStyle(zoom: zoom),
                                    allowsRemoteImages: allowsRemoteImages, offersRemoteImages: remoteImages == .ask,
                                    anchor: anchor.wrappedValue, finder: finder,
                                    loadRemoteImages: { approvedRemoteImages.wrappedValue = true })
                }
            }
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            SourceEditor(text: $document.text, selection: selection.projectedValue,
                         style: EditorStyle(fontSize: zoom.fontSize(editorFontSize), lineSpacingTenths: editorLineSpacing),
                         documentFolder: directory, anchor: anchor.wrappedValue, isActive: mode == .editing,
                         preferences: SourceEditorPreferences(margin: pageMargin, highlightsLine: highlightLine,
                                                              continuesLists: continueLists,
                                                              typingTone: typingSound ? typingTone : nil,
                                                              typingVolume: typingVolume))
            if showWordCount {
                Rectangle().fill(Color(nsColor: NSColor(hex: Palette.border))).frame(height: 1)
                EditorStatusBar(text: document.text, selection: selection.wrappedValue)
            }
        }
    }

    private var directory: URL? { fileURL?.deletingLastPathComponent() }
    private var title: String { fileURL?.deletingPathExtension().lastPathComponent ?? "未命名" }
    private var mode: DisplayMode { storedMode ?? openingMode }
    private var modeSelection: Binding<DisplayMode> { Binding(get: { mode }, set: { storedMode = $0 }) }
    private var allowsRemoteImages: Bool { remoteImages.allowsImages(approvedInWindow: approvedRemoteImages.wrappedValue) }
    private func readingStyle(zoom: DocumentZoom) -> ReadingStyle {
        ReadingStyle(fontSize: zoom.fontSize(readerFontSize), lineSpacingTenths: readerLineSpacing, pageMargin: pageMargin,
                     justifiesText: justifies, spacesMixedScripts: spacedScripts, hangsPunctuation: hangingPunctuation)
    }
}

private struct DraftDocumentName: NSViewRepresentable {
    func makeNSView(context: Context) -> DraftNameView { DraftNameView() }
    func updateNSView(_ view: DraftNameView, context: Context) {}

    final class DraftNameView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Wait until the SwiftUI document window is attached to its NSDocument.
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window,
                      let document = NSDocumentController.shared.document(for: window),
                      document.fileURL == nil,
                      document.displayName.hasPrefix(document.defaultDraftName()) else { return }
                document.displayName = MarkdownDocument.dateName()
            }
        }
    }
}
