import Testing
@testable import ByeSlides

struct DocumentZoomTests {
    @Test func scalesEachModesConfiguredFontAndStopsAtTheLimits() {
        let zoom = DocumentZoom.standard
        #expect(zoom.larger.fontSize(16) == 18)
        #expect(zoom.larger.fontSize(22) == 24)
        #expect(zoom.larger.smaller.fontSize(22) == 22)
        #expect(DocumentZoom(rawValue: 200).larger.rawValue == 200)
        #expect(DocumentZoom(rawValue: 50).smaller.rawValue == 50)
    }
}
