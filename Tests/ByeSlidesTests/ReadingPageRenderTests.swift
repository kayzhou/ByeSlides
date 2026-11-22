import Foundation
import Testing
import WebKit
@testable import ByeSlides
@testable import ByeSlidesCore

/// The real reading page in a `WKWebView`, set up the way `MarkdownPreview` does it.
@MainActor
final class LoadedReadingPage: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let view: WKWebView
    private(set) var messages: [[String: Any]] = []
    private var loaded: CheckedContinuation<Void, Never>?
    private let resources = DocumentResourceHandler()

    init(_ markdown: String, style: ReadingStyle = .standard, options: PreviewOptions = PreviewOptions(),
         height: CGFloat = 600, messageHandler: Bool = true) async {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(resources, forURLScheme: DocumentResourceHandler.scheme)
        for script in PreviewPage.scripts {
            config.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: height), configuration: config)
        super.init()
        if messageHandler { config.userContentController.add(self, name: PreviewPage.messageHandler) }
        view.navigationDelegate = self
        await withCheckedContinuation { continuation in
            loaded = continuation
            view.loadHTMLString(PreviewPage.html(markdown: markdown, style: style, options: options), baseURL: PreviewPage.baseURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume()
        loaded = nil
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any] { messages.append(body) }
    }

    func run(_ script: String) async throws -> Any? {
        try await view.callAsyncJavaScript(script, contentWorld: .page)
    }

    var mainHTML: String {
        get async throws { try await run("return document.querySelector('main').innerHTML") as? String ?? "" }
    }

    /// Waits for pending `postMessage` calls to arrive.
    func settle() async throws {
        _ = try await run("await new Promise(r => setTimeout(r, 120))")
    }
}

@MainActor
struct ReadingPageRenderTests {
    @Test func rendersMarkdownWithStyleAndFont() async throws {
        let page = await LoadedReadingPage("# 标题\n\n| a |\n|---|\n| b |\n\n- [x] 完成",
                                           style: ReadingStyle(fontSize: 20, lineSpacingTenths: 15))
        let result = try await page.run("""
            await document.fonts.load('20px "LXGW WenKai"');
            const body = getComputedStyle(document.body);
            return [body.fontSize, body.lineHeight, body.fontFamily, document.fonts.check('20px "LXGW WenKai"')];
            """) as? [Any]
        let html = try await page.mainHTML
        #expect(html.contains(#"<h1 data-source-line="0" data-source-end="1" id="标题">标题</h1>"#))
        #expect(html.contains(#"<div class="table-scroll"><table"#))
        #expect(html.contains(#"<input type="checkbox" disabled="" checked="">"#))
        #expect(result?[0] as? String == "20px")
        #expect(result?[1] as? String == "30px")
        #expect((result?[2] as? String)?.contains("LXGW WenKai") == true)
        #expect(result?[3] as? Bool == true)
    }

    // The font has one weight, so bold would be faked; colour marks it instead.
    @Test func boldTextIsColouredNotHeavier() async throws {
        let page = await LoadedReadingPage("正文 **重点** 文字\n\n#### 小标题")
        let styles = try await page.run("""
            const s = getComputedStyle(document.querySelector('strong'));
            const h = getComputedStyle(document.querySelector('h4'));
            const p = getComputedStyle(document.querySelector('p'));
            return [s.fontWeight, s.color, h.fontWeight, h.color, p.color, getComputedStyle(document.body).fontSynthesisWeight];
            """) as? [Any]
        #expect(styles?[0] as? String == "400")
        #expect(styles?[1] as? String == "rgb(176, 58, 46)")  // Palette.emphasisLight
        #expect(styles?[2] as? String == "400")
        #expect(styles?[3] as? String == "rgb(176, 58, 46)")
        #expect(styles?[4] as? String != styles?[1] as? String)
        #expect(styles?[5] as? String == "none")
    }

    @Test func holdsRemoteImagesUntilAsked() async throws {
        let markdown = "![猫](https://example.com/cat.png)\n\n![](http://example.com/a.png)\n\n![本地](data:image/png;base64,iVBORw0KGgo=)"
        let blocked = await LoadedReadingPage(markdown)
        let html = try await blocked.mainHTML
        #expect(!html.contains("<img src=\"https"))
        #expect(html.contains(#"<span class="blocked-image" title="https://example.com/cat.png">猫</span>"#))
        #expect(html.contains("为保护隐私，未载入 2 张远程图片。<button type=\"button\">载入</button>"))
        #expect(html.contains("<img src=\"data:image/png"))

        _ = try await blocked.run("document.querySelector('.remote-notice button').click()")
        try await blocked.settle()
        #expect(blocked.messages.contains { $0["type"] as? String == "loadRemoteImages" })

        let allowed = await LoadedReadingPage(markdown, options: PreviewOptions(allowsRemoteImages: true))
        let allowedHTML = try await allowed.mainHTML
        #expect(allowedHTML.contains(#"<img src="https://example.com/cat.png" alt="猫">"#))
        #expect(!allowedHTML.contains("remote-notice"))
    }

    @Test func quickLookShowsNoLoadButton() async throws {
        let page = await LoadedReadingPage("![](https://example.com/a.png)", messageHandler: false)
        let html = try await page.mainHTML
        #expect(html.contains("未载入 1 张远程图片"))
        #expect(!html.contains("<button"))
    }

    @Test func scrollsToAndReportsSourceLines() async throws {
        let markdown = (0..<80).map { "第 \($0) 段，" + String(repeating: "内容", count: 30) }.joined(separator: "\n\n")
        let page = await LoadedReadingPage(markdown, options: PreviewOptions(sourceLine: 100), height: 300)
        let top = try await page.run("await document.fonts.ready; return topSourceLine()") as? Int
        #expect(top == 100, "Paragraph 50 starts on line 100 and should be at the top.")

        _ = try await page.run("window.scrollTo(0, 0)")
        try await page.settle()
        #expect(page.messages.last?["type"] as? String == "scroll")
        #expect(page.messages.last?["line"] as? Int == 0)

        _ = try await page.run("scrollToSourceLine(40)")
        try await page.settle()
        #expect(page.messages.last?["line"] as? Int == 40)
    }
}
