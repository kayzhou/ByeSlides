import AppKit
import ByeSlidesCore
import WebKit

extension MarkdownPreview {
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var owner: MarkdownPreview
        let resources = DocumentResourceHandler()
        private var rendered: (markdown: String, directory: URL?, allowsRemoteImages: Bool, offersRemoteImages: Bool)?
        private var style: ReadingStyle?

        init(_ owner: MarkdownPreview) { self.owner = owner }

        /// Reloads the page when its content changes; otherwise only restyles it.
        func update(_ view: WKWebView) {
            let previousStyle = style
            style = owner.style
            if let rendered, rendered.markdown == owner.markdown, rendered.directory == owner.directory,
               rendered.allowsRemoteImages == owner.allowsRemoteImages,
               rendered.offersRemoteImages == owner.offersRemoteImages {
                if previousStyle != owner.style { applyStyle(to: view, keepingPosition: true) }
                return
            }
            rendered = (owner.markdown, owner.directory, owner.allowsRemoteImages, owner.offersRemoteImages)
            resources.folder = owner.directory.map(DocumentFolder.init)
            let options = PreviewOptions(allowsRemoteImages: owner.allowsRemoteImages,
                                         offersRemoteImages: owner.offersRemoteImages,
                                         sourceLine: owner.anchor.line(in: owner.markdown))
            view.loadHTMLString(PreviewPage.html(markdown: owner.markdown, style: owner.style, options: options),
                                baseURL: PreviewPage.baseURL)
        }

        private func applyStyle(to view: WKWebView, keepingPosition: Bool = false) {
            guard let style else { return }
            let script = style.updateScript
            view.evaluateJavaScript(keepingPosition ? "withReadingPosition(() => { \(script) });" : script)
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

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            switch body["type"] as? String {
            case "scroll":
                if body["restored"] as? Bool == false, let line = body["line"] as? Int {
                    owner.anchor.readerScrolled(toLine: line)
                }
            case "loadRemoteImages":
                if owner.offersRemoteImages { owner.loadRemoteImages() }
            default:
                break
            }
        }
    }
}
