import AppKit
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
         height: CGFloat = 600, messageHandler: Bool = true, appearance: NSAppearance.Name = .aqua) async {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(resources, forURLScheme: DocumentResourceHandler.scheme)
        for script in PreviewPage.scripts {
            config.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: height), configuration: config)
        super.init()
        view.appearance = NSAppearance(named: appearance)
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
    @Test func bundledHelpRendersItsContentsAndExamples() async throws {
        let markdown = try #require(BundledResource.string("Help", "md"))
        let page = await LoadedReadingPage(markdown)
        let result = try await page.run("""
            const main = document.querySelector('main');
            const contents = [...main.querySelectorAll('a[href^="#"]')];
            const missing = contents.filter(link => !document.getElementById(decodeURIComponent(link.hash.slice(1))));
            return [
                main.querySelector('h1').textContent,
                contents.length >= 12 && missing.length === 0,
                main.querySelectorAll('pre code').length >= 10,
                main.querySelector('td[align="right"]') !== null,
                main.querySelector('input[type="checkbox"]:checked:disabled') !== null,
                main.querySelector('img') === null
            ];
            """) as? [Any]
        #expect(result?.first as? String == "ByeSlides 帮助")
        #expect(result?.dropFirst().compactMap { $0 as? Bool } == [true, true, true, true, true])
    }

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

    @Test func readingContentFollowsTheWindowWidth() async throws {
        let page = await LoadedReadingPage("正文")
        for width in [540.0, 1000.0, 1400.0] {
            page.view.setFrameSize(CGSize(width: width, height: 600))
            let layout = try await page.run("""
                const bounds = document.querySelector('main').getBoundingClientRect();
                return [bounds.left, bounds.width, document.documentElement.clientWidth - bounds.right];
                """) as? [Double]
            #expect(layout == [32, width - 64, 32])
        }
    }

    @Test func changingFontSizeKeepsTheReadingPositionWithinALongParagraph() async throws {
        let paragraph = String(repeating: "这是一段用于检查字号缩放后阅读位置的正文。", count: 170)
        let page = await LoadedReadingPage("## 标题\n\n\(paragraph)\n\n\(paragraph)")
        let larger = ReadingStyle(fontSize: 27, lineSpacingTenths: 15)
        let result = try await page.run("""
            await document.fonts.ready;
            const paragraph = document.querySelector('p');
            const before = paragraph.getBoundingClientRect();
            window.scrollTo(0, before.top + window.scrollY + before.height * 0.4);
            withReadingPosition(() => { \(larger.updateScript) });
            const after = paragraph.getBoundingClientRect();
            return [-after.top / after.height, parseInt(getComputedStyle(paragraph).fontSize)];
            """) as? [Double]
        #expect(abs((result?.first ?? 0) - 0.4) < 0.005)
        #expect(result?.last == 27)
    }

    // The font has one weight, so bold would be faked; colour marks it instead.
    @Test(arguments: [false, true])
    func boldTextIsBlueInLightReadingPage(darkHost: Bool) async throws {
        let page = await LoadedReadingPage("正文 **重点** 文字\n\n#### 小标题", appearance: darkHost ? .darkAqua : .aqua)
        let styles = try await page.run("""
            const s = getComputedStyle(document.querySelector('strong'));
            const h = getComputedStyle(document.querySelector('h4'));
            const p = getComputedStyle(document.querySelector('p'));
            const scheme = getComputedStyle(document.documentElement).colorScheme;
            return [s.fontWeight, s.color, h.fontWeight, h.color, p.color, getComputedStyle(document.body).fontSynthesisWeight, scheme];
            """) as? [Any]
        let emphasis = "rgb(36, 88, 166)"
        #expect(styles?[0] as? String == "400")
        #expect(styles?[1] as? String == emphasis)
        #expect(styles?[2] as? String == "400")
        #expect(styles?[3] as? String == emphasis)
        #expect(styles?[4] as? String != styles?[1] as? String)
        #expect(styles?[5] as? String == "none")
        #expect(styles?[6] as? String == "light")
    }

    @Test func rendersTheCobaltAndSnowWhitePalette() async throws {
        let page = await LoadedReadingPage("[链接](https://example.com) `code`\n\n> 引用\n\n| 标题 |\n|---|\n| 内容 |")
        let colors = try await page.run("""
            const style = selector => getComputedStyle(document.querySelector(selector));
            return [style('html').backgroundColor, style('body').color, style('a').color,
                    style('code').backgroundColor, style('blockquote').backgroundColor,
                    style('th').backgroundColor, style('th').borderTopColor];
            """) as? [String]
        #expect(colors == ["rgb(255, 255, 255)", "rgb(28, 38, 51)", "rgb(36, 88, 166)",
                           "rgb(241, 245, 251)", "rgb(241, 245, 251)", "rgb(241, 245, 251)", "rgb(221, 228, 239)"])
    }

    @Test func holdsRemoteImagesUntilAsked() async throws {
        let markdown = "![猫](https://example.com/cat.png)\n\n![](http://example.com/a.png)\n\n![本地](data:image/png;base64,iVBORw0KGgo=)"
        let blocked = await LoadedReadingPage(markdown, options: PreviewOptions(offersRemoteImages: true))
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

    @Test func permanentlyBlockedImagesHaveNoLoadButtonEvenInTheApp() async throws {
        let page = await LoadedReadingPage("![](https://example.com/a.png)")
        let html = try await page.mainHTML
        #expect(html.contains("未载入 1 张远程图片"))
        #expect(!html.contains("<button"))
        #expect(!html.contains("<img"))
    }

    @Test func readingPreferencesChangeTheRenderedPage() async throws {
        let page = await LoadedReadingPage("你好 world。")
        let style = ReadingStyle(fontSize: 18, lineSpacingTenths: 15, pageMargin: 48, justifiesText: false,
                                 spacesMixedScripts: false, hangsPunctuation: false)
        let settings = try await page.run("""
            \(style.updateScript)
            const body = getComputedStyle(document.body);
            const paragraph = getComputedStyle(document.querySelector('main > p'));
            return [body.paddingLeft, paragraph.textAlign, body.textAutospace, body.hangingPunctuation];
            """) as? [String]
        #expect(settings == ["48px", "start", "no-autospace", "none"])
    }

    @Test func quickLookShowsNoLoadButton() async throws {
        let page = await LoadedReadingPage("![](https://example.com/a.png)", messageHandler: false)
        let html = try await page.mainHTML
        #expect(html.contains("未载入 1 张远程图片"))
        #expect(!html.contains("<button"))
    }

    @Test func relativeResourcesStayInsideTheDocumentFolder() async throws {
        let page = await LoadedReadingPage("""
            ![local](assets/image.png)
            ![parent](../assets/image.png)
            ![same-name](../note/assets/image.png)
            ![root](/assets/image.png)
            [sibling](drafts/../other.md)
            """)
        let references = try await page.run("""
            return [...document.querySelector('main').querySelectorAll('img, a')].map(element =>
                (element.hasAttribute('src') ? element.src : element.hasAttribute('href') ? element.href : 'blocked'));
            """) as? [String]
        let base = PreviewPage.baseURL.absoluteString
        #expect(references == [base + "assets/image.png", "blocked", "blocked", base + "assets/image.png", base + "other.md"])
    }

    @Test func scrollsToAndReportsSourceLines() async throws {
        let markdown = (0..<80).map { "第 \($0) 段，" + String(repeating: "内容", count: 30) }.joined(separator: "\n\n")
        let page = await LoadedReadingPage(markdown, options: PreviewOptions(sourceLine: 100), height: 300)
        let top = try await page.run("await document.fonts.ready; return topSourceLine()") as? Int
        #expect(top == 100, "Paragraph 50 starts on line 100 and should be at the top.")
        try await page.settle()
        #expect(page.messages.last?["restored"] as? Bool == true)

        _ = try await page.run("window.scrollTo(0, 0)")
        try await page.settle()
        #expect(page.messages.last?["type"] as? String == "scroll")
        #expect(page.messages.last?["line"] as? Int == 0)
        #expect(page.messages.last?["restored"] as? Bool == false)

        _ = try await page.run("scrollToSourceLine(40)")
        try await page.settle()
        #expect(page.messages.last?["line"] as? Int == 40)
    }
}
