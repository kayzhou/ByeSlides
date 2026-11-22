import Foundation

/// Files shipped in `Sources/ByeSlidesCore/Resources`.
package enum BundledResource {
    package static func url(_ name: String, _ fileExtension: String) -> URL? {
        let fileName = "\(name).\(fileExtension)"
        for directory in searchDirectories {
            let url = directory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        #if DEBUG
        // `swift run` and `swift test` read from the SwiftPM resource bundle.
        return Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "Resources")
        #else
        return nil
        #endif
    }

    package static func string(_ name: String, _ fileExtension: String) -> String? {
        url(name, fileExtension).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    /// `build-app.sh` copies the resources into `Contents/Resources` of the app and of the
    /// Quick Look extension. The extension only gets the small files; it reads the font from
    /// the app around it, which its sandbox allows once the app is in /Applications.
    private static let searchDirectories: [URL] = {
        var directories = Bundle.main.resourceURL.map { [$0] } ?? []
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "appex" {
            // …/ByeSlides.app/Contents/PlugIns/ByeSlidesQuickLook.appex
            directories.append(bundle.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources"))
        }
        return directories
    }()
}
