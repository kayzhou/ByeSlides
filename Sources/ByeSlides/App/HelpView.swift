import ByeSlidesCore
import SwiftUI

struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("ByeSlides 帮助") { openWindow(id: HelpView.windowID) }
        }
    }
}

struct HelpView: View {
    static let windowID = "help"
    private static let guide = BundledResource.string("Help", "md")

    @StateObject private var finder = ReadingFinder()
    private let anchor = State(initialValue: ScrollAnchor())

    var body: some View {
        VStack(spacing: 0) {
            if let guide = Self.guide {
                if finder.isVisible {
                    ReadingFindBar(finder: finder)
                    Divider()
                }
                MarkdownPreview(markdown: guide, directory: nil, style: .standard,
                                allowsRemoteImages: false, offersRemoteImages: false,
                                anchor: anchor.wrappedValue, finder: finder, loadRemoteImages: {})
            } else {
                ContentUnavailableView("无法载入帮助文档", systemImage: "book.closed")
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}
