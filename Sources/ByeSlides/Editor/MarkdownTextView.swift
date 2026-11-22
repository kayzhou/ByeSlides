import AppKit
import UniformTypeIdentifiers

/// The source editor's text view: list-aware Return and Tab, the Format menu actions,
/// a centred text column, and pasted or dropped images.
final class MarkdownTextView: NSTextView {
    /// Folder of the saved document; nil while it is untitled.
    var documentFolder: URL?

    /// Widest the text column gets; wider windows centre it.
    var columnWidth: CGFloat = 640 {
        didSet { updateColumnInset() }
    }

    static let minimumInset = NSSize(width: 20, height: 16)

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateColumnInset()
    }

    private func updateColumnInset() {
        let side = max(Self.minimumInset.width, ((bounds.width - columnWidth) / 2).rounded())
        let inset = NSSize(width: side, height: Self.minimumInset.height)
        if textContainerInset != inset { textContainerInset = inset }
    }

    /// Makes an edit the way typing would: undoable, and reported to the delegate.
    func apply(_ edit: TextEdit, actionName: String? = nil) {
        breakUndoCoalescing()
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
        scrollRangeToVisible(edit.selection)
        if let actionName { undoManager?.setActionName(actionName) }
        breakUndoCoalescing()
    }

    // MARK: Lists

    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText(), let edit = ListEditing.newline(in: string as NSString, selection: selectedRange()) else {
            return super.insertNewline(sender)
        }
        apply(edit)
    }

    override func insertTab(_ sender: Any?) {
        guard !hasMarkedText(), let edit = ListEditing.indent(in: string as NSString, selection: selectedRange()) else {
            return super.insertTab(sender)
        }
        apply(edit, actionName: "缩进")
    }

    override func insertBacktab(_ sender: Any?) {
        guard !hasMarkedText(), let edit = ListEditing.outdent(in: string as NSString, selection: selectedRange()) else {
            return super.insertBacktab(sender)
        }
        apply(edit, actionName: "减少缩进")
    }

    // MARK: Format menu

    @objc func toggleMarkdownBold(_ sender: Any?) {
        apply(InlineFormatting.toggle(.bold, in: string as NSString, selection: selectedRange()), actionName: "粗体")
    }

    @objc func toggleMarkdownItalic(_ sender: Any?) {
        apply(InlineFormatting.toggle(.italic, in: string as NSString, selection: selectedRange()), actionName: "斜体")
    }

    @objc func insertMarkdownLink(_ sender: Any?) {
        apply(InlineFormatting.link(in: string as NSString, selection: selectedRange()), actionName: "链接")
    }

    // MARK: Images

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + [.fileURL, .png, .tiff]
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + [.fileURL, .png, .tiff]
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        insertImages(from: pboard) ?? super.readSelection(from: pboard, type: type)
    }

    /// Inserts images from a paste or drop. Returns nil when the pasteboard holds something else,
    /// such as text, which a rich-text app may offer alongside a picture of it.
    func insertImages(from pboard: NSPasteboard) -> Bool? {
        let files = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let images = files.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
        var pasted: Data?
        if files.isEmpty, pboard.availableType(from: [.string]) == nil {
            pasted = pboard.data(forType: .png)
                ?? pboard.data(forType: .tiff).flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
        }
        guard (!images.isEmpty && images.count == files.count) || pasted != nil else { return nil }
        guard let folder = documentFolder else {
            askToSaveFirst()
            return true
        }
        do {
            let markdown = try pasted.map { [try ImageImporter.importData($0, type: .png, into: folder)] }
                ?? images.map { try ImageImporter.importFile($0, into: folder) }
            let text = markdown.joined(separator: "\n")
            let range = selectedRange()
            apply(TextEdit(range: range, replacement: text, selection: NSRange(location: range.location + text.utf16.count, length: 0)),
                  actionName: "插入图片")
        } catch {
            presentError(error)
        }
        return true
    }

    private func askToSaveFirst() {
        let alert = NSAlert()
        alert.messageText = "请先存储这篇文稿"
        alert.informativeText = "图片会拷贝到文稿旁边的 \(ImageImporter.folderName) 文件夹，所以需要先把文稿存储下来。"
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}
