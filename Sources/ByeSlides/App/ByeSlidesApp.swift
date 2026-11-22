import AppKit
import SwiftUI

@main
struct ByeSlidesApp: App {
    init() {
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        PreferencesMigration.run()
    }

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 960, height: 640)
        .commands {
            // Find, spelling, substitutions and speech, served by the text views.
            TextEditingCommands()
            DisplayModeCommands()
            FormatCommands()
            PrintCommands()
        }
    }
}
