import SwiftUI

@main
struct ByeSlidesApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 960, height: 640)
    }
}
