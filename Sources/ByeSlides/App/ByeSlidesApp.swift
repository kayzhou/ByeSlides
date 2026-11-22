import AppKit
import Carbon
import SwiftUI

@main
struct ByeSlidesApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: ByeSlidesAppDelegate
    @StateObject private var folderBrowser = FolderBrowser()

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        PreferencesMigration.run()
    }

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentView(document: file.$document, fileURL: file.fileURL, folderBrowser: folderBrowser)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 960, height: 640)
        .commands {
            // Find, spelling, substitutions and speech, served by the text views.
            TextEditingCommands()
            DisplayModeCommands()
            FolderBrowserCommands()
            FormatCommands()
            PrintCommands()
            HelpCommands()
        }
        Settings {
            SettingsView()
        }
        Window("ByeSlides 帮助", id: HelpView.windowID) {
            HelpView()
        }
        .defaultSize(width: 800, height: 720)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

@MainActor
final class ByeSlidesAppDelegate: NSObject, NSApplicationDelegate {
    private var receivedFileOpen = false

    static var dailyNotesFolder: URL {
        URL.applicationSupportDirectory.appending(path: "ByeSlides", directoryHint: .isDirectory)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        DocumentSwitcher.shared.observeFileMenu()
        // The open-application event has no document URL. Finder opens files with a separate event.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(openApplication(_:reply:)),
                                                    forEventClass: AEEventClass(kCoreEventClass),
                                                    andEventID: AEEventID(kAEOpenApplication))
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(openDocuments(_:reply:)),
                                                    forEventClass: AEEventClass(kCoreEventClass),
                                                    andEventID: AEEventID(kAEOpenDocuments))
    }

    @objc private func openApplication(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        DispatchQueue.main.async {
            guard !self.receivedFileOpen else { return }
            let preference = AppPreferences.launch
            let action = UserDefaults.standard.string(forKey: preference.key).flatMap(LaunchAction.init(rawValue:))
                ?? preference.defaultValue
            switch action {
            case .dailyNote:
                self.prepareWritingAudio()
                self.openDailyNote()
            case .blankDocument:
                self.prepareWritingAudio()
                DocumentSwitcher.shared.newDocument()
            case .noDocument: break
            }
        }
    }

    @objc private func openDocuments(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let files = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)),
              let url = files.atIndex(1)?.fileURLValue ?? files.fileURLValue else { return }
        receivedFileOpen = true
        DispatchQueue.main.async {
            self.prepareWritingAudio()
            DocumentSwitcher.shared.open(url)
        }
    }

    private func prepareWritingAudio() {
        let defaults = UserDefaults.standard
        let mode = AppPreferences.openingMode
        let enabled = AppPreferences.typingSound
        let volume = AppPreferences.typingVolume
        let tone = AppPreferences.typingTone
        guard (defaults.string(forKey: mode.key).flatMap(DisplayMode.init(rawValue:)) ?? mode.defaultValue) == .editing,
              (defaults.object(forKey: enabled.key) as? Bool ?? enabled.defaultValue),
              (defaults.object(forKey: volume.key) as? Double ?? volume.defaultValue) > 0 else { return }
        let sound = defaults.string(forKey: tone.key).flatMap(TypingTone.init(rawValue:)) ?? tone.defaultValue
        // The audio device can take longer to start than the editor takes to accept input.
        // Warm it in parallel, only when opening directly into writing with sound enabled.
        Task.detached(priority: .utility) { await TypingSound.shared.prepare(sound) }
    }

    private func openDailyNote() {
        do {
            let note = try Self.prepareDailyNote(in: Self.dailyNotesFolder)
            DocumentSwitcher.shared.open(note)
        } catch {
            NSApp.presentError(error)
        }
    }

    nonisolated static func prepareDailyNote(in folder: URL, date: Date = .now, timeZone: TimeZone = .current) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let note = folder.appending(path: MarkdownDocument.dateName(for: date, timeZone: timeZone), directoryHint: .notDirectory)
            .appendingPathExtension("md")
        do {
            try Data().write(to: note, options: .withoutOverwriting)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            // The existing note contains the user's writing.
        }
        return note
    }
}
