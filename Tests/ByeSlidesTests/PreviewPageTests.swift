import Foundation
import Testing
@testable import ByeSlides

struct PreviewPageTests {
    @Test func bundledScriptsAndStylesheetAreFound() {
        #expect(PreviewPage.scripts.count == 3)
        #expect(BundledResource.string("reading", "css")?.contains("--table-border") == true)
        #expect(BundledResource.url("LXGWWenKai-Regular", "ttf") != nil)
    }

    @Test func embedsTheDocumentAsBase64() throws {
        let markdown = "</script><script>alert(1)</script> 中文"
        let html = PreviewPage.html(markdown: markdown, style: ReadingStyle(fontSize: 18, lineSpacingTenths: 17))
        #expect(!html.contains(markdown))
        #expect(html.contains(Data(markdown.utf8).base64EncodedString()))
    }

    @Test func appliesTheReadingStyle() {
        let style = ReadingStyle(fontSize: 20, lineSpacingTenths: 15)
        #expect(style.cssDeclarations == "--reading-size: 20px; --line-height: 1.5")
        #expect(PreviewPage.html(markdown: "", style: style).contains(":root { --reading-size: 20px; --line-height: 1.5 }"))
        #expect(style.updateScript.contains("setProperty('--line-height', '1.5')"))
    }

    @Test func storedModeValuesStayReadable() {
        #expect(DisplayMode(rawValue: "编辑") == .editing)
        #expect(DisplayMode(rawValue: "阅读") == .reading)
    }
}
