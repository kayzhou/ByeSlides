import ByeSlidesCore
import Foundation
import UniformTypeIdentifiers

/// Decides where a link clicked in reading mode opens. The page itself never navigates.
enum LinkPolicy {
    /// File types inside the document's folder that a link may open with the default app.
    static func opensLocalFile(of type: UTType) -> Bool {
        type == .pdf || type.conforms(to: .plainText) || type.conforms(to: .image)
    }

    /// The URL to hand to `NSWorkspace`, or nil to ignore the click.
    static func destination(for url: URL, in folder: DocumentFolder?) -> URL? {
        switch url.scheme?.lowercased() {
        case "https", "http":
            return url.host == nil ? nil : url
        case "mailto":
            return url
        case DocumentResourceHandler.scheme:
            guard url.host == DocumentResourceHandler.documentHost,
                  let file = folder?.file(atPath: url.path),
                  let type = UTType(filenameExtension: file.pathExtension), opensLocalFile(of: type),
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            return file
        default:
            return nil
        }
    }
}
