import ByeSlidesCore
import Foundation
import UniformTypeIdentifiers

/// Decides where a link clicked in reading mode opens. The page itself never navigates.
enum LinkPolicy {
    /// File types inside the document's folder that a link may open.
    static func opensLocalFile(of type: UTType) -> Bool {
        type == .pdf || type.conforms(to: .plainText) || type.conforms(to: .image)
    }

    static func opensInEditor(_ url: URL) -> Bool {
        url.isFileURL && MarkdownDocument.markdownExtensions.contains(url.pathExtension.lowercased())
    }

    /// The URL to open, or nil to ignore the click.
    static func destination(for url: URL, in folder: DocumentFolder?) -> URL? {
        switch url.scheme?.lowercased() {
        case "https", "http":
            return url.host == nil ? nil : url
        case "mailto":
            return url
        case DocumentResourceHandler.scheme:
            guard let path = DocumentResourceHandler.documentPath(for: url),
                  let file = folder?.file(atPath: path),
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            if opensInEditor(file) { return file }
            return UTType(filenameExtension: file.pathExtension).map(opensLocalFile) == true ? file : nil
        default:
            return nil
        }
    }
}
