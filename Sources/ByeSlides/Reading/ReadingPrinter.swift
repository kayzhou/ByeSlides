import AppKit
import ByeSlidesCore
import UniformTypeIdentifiers
import WebKit

/// What File > Print and Export as PDF need from the focused window.
struct PrintableDocument {
    let source: MarkdownSource
    let directory: URL?
    let style: ReadingStyle
    let allowsRemoteImages: Bool
    let title: String
}

/// Prints the document, or saves it as a PDF, with the reading layout. The page is rendered in
/// an offscreen web view in light appearance, whatever mode the window is in.
@MainActor
final class ReadingPrinter: NSObject, WKNavigationDelegate {
    /// Keeps each printer alive until its print operation ends.
    private static var active: Set<ReadingPrinter> = []

    private let document: PrintableDocument
    private let destination: URL?
    private weak var window: NSWindow?
    private let completion: (Bool) -> Void
    private let resources = DocumentResourceHandler()
    private let webView: WKWebView
    /// WebKit only finishes a print operation for a web view that is in a window.
    /// This one is never shown.
    private let offscreenWindow: NSWindow

    static func print(_ document: PrintableDocument, from window: NSWindow) {
        start(document, saveTo: nil, from: window)
    }

    static func exportPDF(_ document: PrintableDocument, from window: NSWindow) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = document.title + ".pdf"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { start(document, saveTo: url, from: window) }
        }
    }

    /// Prints with the print panel, or straight to a PDF file when `destination` is set.
    static func start(_ document: PrintableDocument, saveTo destination: URL?, from window: NSWindow,
                      completion: @escaping (Bool) -> Void = { _ in }) {
        let printer = ReadingPrinter(document: document, destination: destination, window: window, completion: completion)
        active.insert(printer)
        printer.load()
    }

    private init(document: PrintableDocument, destination: URL?, window: NSWindow, completion: @escaping (Bool) -> Void) {
        self.document = document
        self.destination = destination
        self.window = window
        self.completion = completion
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(resources, forURLScheme: DocumentResourceHandler.scheme)
        for script in PreviewPage.scripts {
            config.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        // A4 width at 72 dpi; the print operation lays the page out again for the chosen paper.
        let frame = NSRect(x: 0, y: 0, width: 595, height: 842)
        webView = WKWebView(frame: frame, configuration: config)
        offscreenWindow = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        offscreenWindow.isReleasedWhenClosed = false
        offscreenWindow.appearance = NSAppearance(named: .aqua)
        offscreenWindow.contentView = webView
        super.init()
        webView.navigationDelegate = self
        resources.folder = document.directory.map(DocumentFolder.init)
    }

    private func load() {
        let html = PreviewPage.html(markdown: document.source.text, style: document.style,
                                    options: PreviewOptions(allowsRemoteImages: document.allowsRemoteImages))
        webView.loadHTMLString(html, baseURL: PreviewPage.baseURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task {
            // Print only after the reading font has arrived.
            _ = try? await webView.callAsyncJavaScript("await document.fonts.ready", contentWorld: .page)
            runPrintOperation()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(success: false)
    }

    private func runPrintOperation() {
        guard let window else { return finish(success: false) }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        (info.topMargin, info.bottomMargin, info.leftMargin, info.rightMargin) = (54, 54, 54, 54)
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        if let destination {
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination
        }
        let operation = webView.printOperation(with: info)
        operation.jobTitle = document.title
        operation.showsPrintPanel = destination == nil
        operation.showsProgressPanel = destination == nil
        operation.printPanel.options.formUnion([.showsPaperSize, .showsOrientation, .showsScaling, .showsPreview])
        // Without a frame the web view prints blank pages.
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: self,
                           didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    // Without a print panel, AppKit runs the job on its own thread and calls this from there.
    @objc nonisolated private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool,
                                                        contextInfo: UnsafeMutableRawPointer?) {
        Task { @MainActor in self.finish(success: success) }
    }

    private func finish(success: Bool) {
        completion(success)
        Self.active.remove(self)
    }
}
