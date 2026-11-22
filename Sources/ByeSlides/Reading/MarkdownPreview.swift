import SwiftUI
import WebKit

/// Reading mode: renders the document's Markdown in a `WKWebView`.
struct MarkdownPreview: NSViewRepresentable {
    let markdown: String
    /// Folder of the saved document, used to resolve relative images and links.
    let directory: URL?
    let style: ReadingStyle

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(context.coordinator.resources, forURLScheme: DocumentResourceHandler.scheme)
        for script in PreviewPage.scripts {
            config.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.update(view, markdown: markdown, directory: directory, style: style)
    }
}
