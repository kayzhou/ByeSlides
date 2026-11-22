import Foundation
import Testing
import WebKit
@testable import ByeSlides

/// Loads the real reading page in a `WKWebView`, the same way `MarkdownPreview` does.
@MainActor
struct ReadingPageRenderTests {
    private final class LoadWaiter: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, Never>?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            continuation?.resume()
            continuation = nil
        }
    }

    private func render(_ markdown: String, style: ReadingStyle) async throws -> WKWebView {
        let resources = DocumentResourceHandler()
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(resources, forURLScheme: DocumentResourceHandler.scheme)
        for script in PreviewPage.scripts {
            config.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        let waiter = LoadWaiter()
        view.navigationDelegate = waiter
        await withCheckedContinuation { continuation in
            waiter.continuation = continuation
            view.loadHTMLString(PreviewPage.html(markdown: markdown, style: style), baseURL: PreviewPage.baseURL)
        }
        return view
    }

    @Test func rendersMarkdownWithStyleAndFont() async throws {
        let view = try await render("# 标题\n\n| a |\n|---|\n| b |\n\n- [x] 完成",
                                    style: ReadingStyle(fontSize: 20, lineSpacingTenths: 15))
        let result = try await view.callAsyncJavaScript("""
            await document.fonts.load('20px "LXGW WenKai"');
            const body = getComputedStyle(document.body);
            return [document.querySelector("main").innerHTML, body.fontSize, body.lineHeight,
                    body.fontFamily, document.fonts.check('20px "LXGW WenKai"')];
            """, contentWorld: .page) as? [Any]
        let html = try #require(result?[0] as? String)
        #expect(html.contains(#"<h1 id="标题">标题</h1>"#))
        #expect(html.contains(#"<div class="table-scroll"><table>"#))
        #expect(html.contains(#"<input type="checkbox" disabled="" checked="">"#))
        #expect(result?[1] as? String == "20px")
        #expect(result?[2] as? String == "30px")
        #expect((result?[3] as? String)?.contains("LXGW WenKai") == true)
        #expect(result?[4] as? Bool == true)
    }
}
