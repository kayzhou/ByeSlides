import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

/// The source editor's text view: list-aware Return and Tab, the Format menu actions,
/// fixed page margins, and pasted or dropped images.
final class MarkdownTextView: NSTextView {
    /// Folder of the saved document; nil while it is untitled.
    var documentFolder: URL?

    private let writingCaret = WritingCaretView()
    private var revealCaret: DispatchWorkItem?

    override class func scrollablePlainDocumentContentTextView() -> NSScrollView {
        let scroll = super.scrollablePlainDocumentContentTextView()
        let editor = scroll.documentView as! MarkdownTextView
        // The text container adds its own padding inside the inset.
        let fragmentPadding = editor.textContainer?.lineFragmentPadding ?? 0
        editor.textContainerInset = NSSize(width: 32 - fragmentPadding, height: 16)
        return scroll
    }

    // MARK: Writing caret

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        guard let indicator = subview as? NSTextInsertionIndicator else { return }
        indicator.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(refreshWritingCaret(_:)),
                                               name: NSView.frameDidChangeNotification, object: indicator)
        if writingCaret.superview == nil {
            writingCaret.isHidden = true
            addSubview(writingCaret, positioned: .above, relativeTo: indicator)
        }
        updateWritingCaret()
    }

    override func willRemoveSubview(_ subview: NSView) {
        if subview is NSTextInsertionIndicator {
            NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: subview)
            writingCaret.isHidden = true
        }
        super.willRemoveSubview(subview)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            if let window { center.removeObserver(self, name: name, object: window) }
            if let newWindow { center.addObserver(self, selector: #selector(refreshWritingCaret(_:)), name: name, object: newWindow) }
        }
        writingCaret.isHidden = true
        super.viewWillMove(toWindow: newWindow)
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        // The window assigns firstResponder after this method returns.
        DispatchQueue.main.async { [weak self] in self?.updateWritingCaret() }
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        writingCaret.isHidden = true
        return true
    }

    override func didChangeText() {
        super.didChangeText()
        revealCaret?.cancel()
        let reveal = DispatchWorkItem { [weak self] in self?.showWritingCaret() }
        revealCaret = reveal
        updateWritingCaret()
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400), execute: reveal)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        showWritingCaret()
    }

    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        switch Int(event.keyCode) {
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            showWritingCaret()
        default:
            break
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        updateWritingCaret()
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        updateWritingCaret()
    }

    override func unmarkText() {
        super.unmarkText()
        updateWritingCaret()
    }

    private func showWritingCaret() {
        revealCaret?.cancel()
        revealCaret = nil
        updateWritingCaret()
    }

    @objc private func refreshWritingCaret(_ notification: Notification) {
        updateWritingCaret()
    }

    private func updateWritingCaret() {
        let indicators = subviews.compactMap { $0 as? NSTextInsertionIndicator }
        guard let indicator = indicators.last else { return }
        let useOverlay = !hasMarkedText() && selectedRanges.count == 1
        // TextKit 2 positions the caret and draws it for input methods and multiple selections.
        let color: NSColor = useOverlay ? .clear : insertionPointColor
        for indicator in indicators where indicator.color != color { indicator.color = color }

        let caret = indicator.frame
        guard useOverlay, revealCaret == nil, isEditable, window?.isKeyWindow == true,
              window?.firstResponder === self, selectedRange().length == 0, caret.height > 0 else {
            writingCaret.isHidden = true
            return
        }
        let typingFont = typingAttributes[.font] as? NSFont ?? font
        let glyphHeight = min(typingFont?.pointSize ?? caret.height, caret.height)
        writingCaret.frame = NSRect(x: caret.midX - 3, y: caret.maxY - glyphHeight - 4,
                                    width: 6, height: glyphHeight + 8)
        writingCaret.isHidden = false
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

private final class WritingCaretView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let needles = NSBezierPath()
        for (edge, tip) in [(bounds.minY, bounds.minY + 3), (bounds.maxY, bounds.maxY - 3)] {
            needles.move(to: NSPoint(x: bounds.minX, y: edge))
            needles.line(to: NSPoint(x: bounds.midX, y: tip))
            needles.line(to: NSPoint(x: bounds.maxX, y: edge))
            needles.close()
        }
        EditorStyle.emphasis.setFill()
        needles.fill()
    }
}
