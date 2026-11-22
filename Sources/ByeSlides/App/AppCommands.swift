import AppKit
import SwiftUI

// Focused values let the menu bar act on the frontmost document window.
// The keys are written out because the `@Entry` macro needs SwiftUI's macro plugin.

struct DisplayModeKey: FocusedValueKey { typealias Value = Binding<DisplayMode> }
struct PrintableDocumentKey: FocusedValueKey { typealias Value = PrintableDocument }

extension FocusedValues {
    var displayMode: Binding<DisplayMode>? {
        get { self[DisplayModeKey.self] }
        set { self[DisplayModeKey.self] = newValue }
    }

    var printableDocument: PrintableDocument? {
        get { self[PrintableDocumentKey.self] }
        set { self[PrintableDocumentKey.self] = newValue }
    }
}

/// View > 编辑模式 ⌘1, 阅读模式 ⌘2.
struct DisplayModeCommands: Commands {
    @FocusedBinding(\.displayMode) private var mode

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            ForEach(DisplayMode.allCases) { candidate in
                Toggle(isOn: Binding(get: { mode == candidate }, set: { if $0 { mode = candidate } })) {
                    Text(candidate.menuTitle)
                }
                .keyboardShortcut(candidate.shortcut)
                .disabled(mode == nil)
            }
            Divider()
        }
    }
}

/// The Format menu. Its actions go to the source editor through the responder chain.
struct FormatCommands: Commands {
    @FocusedBinding(\.displayMode) private var mode

    var body: some Commands {
        CommandMenu("格式") {
            Group {
                Button("粗体") { send(#selector(MarkdownTextView.toggleMarkdownBold(_:))) }
                    .keyboardShortcut("b")
                Button("斜体") { send(#selector(MarkdownTextView.toggleMarkdownItalic(_:))) }
                    .keyboardShortcut("i")
                Button("链接") { send(#selector(MarkdownTextView.insertMarkdownLink(_:))) }
                    .keyboardShortcut("k")
            }
            .disabled(mode != .editing)
        }
    }

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }
}

/// File > 导出为 PDF… and 打印… ⌘P, both using the reading layout.
struct PrintCommands: Commands {
    @FocusedValue(\.printableDocument) private var document

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("导出为 PDF…") { run(ReadingPrinter.exportPDF) }
                .disabled(document == nil)
            Button("打印…") { run(ReadingPrinter.print) }
                .keyboardShortcut("p")
                .disabled(document == nil)
        }
    }

    private func run(_ action: (PrintableDocument, NSWindow) -> Void) {
        guard let document, let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        action(document, window)
    }
}
