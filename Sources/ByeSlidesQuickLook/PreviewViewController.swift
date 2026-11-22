import ByeSlidesCore
import Cocoa
import QuickLookUI
import WebKit

/// Finder's Quick Look preview of Markdown files, using the same page as reading mode.
/// The extension's sandbox lets it read only the previewed file, so relative images don't show,
/// and remote images stay blocked as in the app.
@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private let resources = DocumentResourceHandler()
    private var webView: WKWebView?
    private var pageLoaded: CheckedContinuation<Void, Never>?

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(resources, forURLScheme: DocumentResourceHandler.scheme)
        for script in PreviewPage.scripts {
            config.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        webView.navigationDelegate = self
        self.webView = webView
        view = webView
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let (markdown, _) = try TextEncoding.decode(Data(contentsOf: url))
        guard let webView = view as? WKWebView else { return }
        await withCheckedContinuation { continuation in
            pageLoaded = continuation
            webView.loadHTMLString(PreviewPage.html(markdown: markdown, style: .standard), baseURL: PreviewPage.baseURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { resumeLoad() }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { resumeLoad() }

    private func resumeLoad() {
        pageLoaded?.resume()
        pageLoaded = nil
    }

    // A preview never navigates; links stay inert.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.navigationType == .other ? .allow : .cancel)
    }
}
