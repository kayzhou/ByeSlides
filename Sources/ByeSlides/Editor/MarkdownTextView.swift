import AppKit
import ByeSlidesCore
import QuartzCore
import UniformTypeIdentifiers

/// The source editor's text view: list-aware Return and Tab, the Format menu actions,
/// page margins, typing sounds, and pasted or dropped images.
final class MarkdownTextView: NSTextView {
    /// Folder of the saved document; nil while it is untitled.
    var documentFolder: URL?

    var preferences = SourceEditorPreferences() {
        didSet {
            if preferences.margin != oldValue.margin { updateTextInset() }
            if preferences.highlightsLine != oldValue.highlightsLine { setNeedsDisplay(lineBackgroundRect(caretLine)) }
            if preferences.typingTone != oldValue.typingTone || (preferences.typingVolume > 0) != (oldValue.typingVolume > 0) {
                updateTypingSound(hasFocus: window?.firstResponder === self)
            }
        }
    }

    private let soundSession = UUID()
    private var activeTypingTone: TypingTone?
    private var soundFocusUpdate: Task<Void, Never>?

    private func updateTypingSound(hasFocus: Bool) {
        let tone = hasFocus && window?.isKeyWindow == true && preferences.typingVolume > 0 ? preferences.typingTone : nil
        guard tone != activeTypingTone else { return }
        activeTypingTone = tone
        soundFocusUpdate?.cancel()
        soundFocusUpdate = Task(priority: .utility) { [soundSession] in
            await TypingSound.shared.setEditorTone(tone, for: soundSession)
        }
    }

    private weak var currentIndicator: NSTextInsertionIndicator?
    private var caretLine = NSRect.zero
    private static let lineColor = NSColor(hex: Palette.currentLine)

    override class func scrollablePlainDocumentContentTextView() -> NSScrollView {
        let scroll = super.scrollablePlainDocumentContentTextView()
        let editor = scroll.documentView as! MarkdownTextView
        editor.updateTextInset()
        scroll.backgroundColor = NSColor(hex: Palette.paper)
        editor.backgroundColor = scroll.backgroundColor
        editor.insertionPointColor = NSColor(hex: Palette.caret)
        editor.selectedTextAttributes[.backgroundColor] = NSColor(hex: Palette.selection)
        editor.selectedTextAttributes[.foregroundColor] = EditorStyle.ink
        return scroll
    }

    private func updateTextInset() {
        // The text container adds its own padding inside the inset.
        let fragmentPadding = textContainer?.lineFragmentPadding ?? 0
        textContainerInset = NSSize(width: CGFloat(preferences.margin) - fragmentPadding, height: 16)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        let volume = preferences.typingVolume
        if isEditable, volume > 0, let tone = preferences.typingTone, let key = TypingKey(event: event) {
            TypingSound.shared.enqueue(key, tone: tone, volume: volume, timestamp: event.timestamp, isRepeat: event.isARepeat)
        }
        super.keyDown(with: event)
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        guard let indicator = subview as? NSTextInsertionIndicator else { return }
        currentIndicator = indicator
        // Keep AppKit's caret animation while narrowing its 2 pt stroke to 1 pt.
        // The half-point offset leaves the stroke inside the highlight at the left margin.
        indicator.layer?.sublayerTransform = CATransform3DMakeAffineTransform(
            CGAffineTransform(a: 0.5, b: 0, c: 0, d: 1, tx: 0.5, ty: 0)
        )
        indicator.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(insertionIndicatorFrameChanged(_:)),
                                               name: NSView.frameDidChangeNotification, object: indicator)
        fitInsertionIndicator(indicator)
    }

    override func willRemoveSubview(_ subview: NSView) {
        if subview is NSTextInsertionIndicator {
            NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: subview)
        }
        if subview === currentIndicator {
            currentIndicator = nil
            updateCaretLine(.zero)
        }
        super.willRemoveSubview(subview)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        updateTypingSound(hasFocus: false)
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            if let window { center.removeObserver(self, name: name, object: window) }
            if let newWindow { center.addObserver(self, selector: #selector(windowFocusChanged(_:)), name: name, object: newWindow) }
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTypingSound(hasFocus: window?.firstResponder === self)
    }

    @objc private func windowFocusChanged(_ notification: Notification) {
        setNeedsDisplay(lineBackgroundRect(caretLine))
        updateTypingSound(hasFocus: window?.firstResponder === self)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            setNeedsDisplay(lineBackgroundRect(caretLine))
            updateTypingSound(hasFocus: true)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            setNeedsDisplay(lineBackgroundRect(caretLine))
            updateTypingSound(hasFocus: false)
        }
        return resigned
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        setNeedsDisplay(lineBackgroundRect(caretLine))
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard preferences.highlightsLine, window?.isKeyWindow == true, window?.firstResponder === self,
              selectedRanges.count == 1, selectedRange().length == 0 else { return }
        let background = rect.intersection(lineBackgroundRect(caretLine))
        guard !background.isEmpty else { return }
        Self.lineColor.setFill()
        background.fill()
    }

    private func lineBackgroundRect(_ frame: NSRect) -> NSRect {
        let margin = textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0)
        return NSRect(x: margin, y: frame.minY, width: max(0, bounds.width - margin * 2), height: frame.height)
    }

    private func updateCaretLine(_ frame: NSRect) {
        guard caretLine.minY != frame.minY || caretLine.height != frame.height else { return }
        setNeedsDisplay(lineBackgroundRect(caretLine))
        caretLine = frame
        setNeedsDisplay(lineBackgroundRect(caretLine))
    }

    @objc private func insertionIndicatorFrameChanged(_ notification: Notification) {
        guard let indicator = notification.object as? NSTextInsertionIndicator else { return }
        fitInsertionIndicator(indicator)
    }

    private func fitInsertionIndicator(_ indicator: NSTextInsertionIndicator) {
        guard indicator === currentIndicator else { return }
        let frame = indicator.frame
        let typingFont = typingAttributes[.font] as? NSFont ?? font
        let padding: CGFloat = 3
        guard let textHeight = typingFont?.pointSize, frame.height > textHeight + padding * 2 else {
            updateCaretLine(frame)
            return
        }
        // The background and caret extend equally above and below the text box.
        let fitted = NSRect(x: frame.minX, y: frame.maxY - textHeight - padding,
                            width: frame.width, height: textHeight + padding * 2)
        updateCaretLine(fitted)
        indicator.frame = fitted
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
        guard preferences.continuesLists, !hasMarkedText(),
              let edit = ListEditing.newline(in: string as NSString, selection: selectedRange()) else {
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
