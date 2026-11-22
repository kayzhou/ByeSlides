import AppKit
import WebKit

extension MarkdownPreview {
    final class Coordinator: NSObject, WKNavigationDelegate {
        let resources = DocumentResourceHandler()
        private var renderedMarkdown: String?
        private var directory: URL?
        private var style: ReadingStyle?

        /// Reloads the page when the text or folder changes; otherwise only restyles it.
        func update(_ view: WKWebView, markdown: String, directory: URL?, style: ReadingStyle) {
            let styleChanged = self.style != style
            self.style = style
            guard markdown != renderedMarkdown || directory != self.directory else {
                if styleChanged { applyStyle(to: view) }
                return
            }
            renderedMarkdown = markdown
            self.directory = directory
            resources.folder = directory.map(DocumentFolder.init)
            view.loadHTMLString(PreviewPage.html(markdown: markdown, style: style), baseURL: PreviewPage.baseURL)
        }

        private func applyStyle(to view: WKWebView) {
            guard let style else { return }
            view.evaluateJavaScript(style.updateScript)
        }

        // The style may have changed while the page was loading.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyStyle(to: webView)
        }

        func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            if let url = action.request.url, let target = LinkPolicy.destination(for: url, in: resources.folder) {
                NSWorkspace.shared.open(target)
            }
        }
    }
}
