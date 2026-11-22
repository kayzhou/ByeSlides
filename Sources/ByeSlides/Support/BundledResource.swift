import Foundation

/// Files shipped in `Sources/ByeSlides/Resources`.
enum BundledResource {
    /// Looks in the packaged app first (`build-app.sh` copies the folder's contents into
    /// `Contents/Resources`), then in the SwiftPM resource bundle used by `swift run`.
    static func url(_ name: String, _ fileExtension: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: fileExtension)
            ?? Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "Resources")
    }

    static func string(_ name: String, _ fileExtension: String) -> String? {
        url(name, fileExtension).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}
