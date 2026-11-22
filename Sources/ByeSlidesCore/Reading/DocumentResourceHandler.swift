import UniformTypeIdentifiers
import WebKit

/// Serves `document-resource://` requests for the reading page.
/// Host `assets` serves bundled files such as the reading font; host `document` serves images
/// from the document's folder.
package final class DocumentResourceHandler: NSObject, WKURLSchemeHandler {
    package nonisolated static let scheme = "document-resource"
    package nonisolated static let assetsHost = "assets"
    package nonisolated static let documentHost = "document"
    package nonisolated static let documentPathPrefix = "/note/"

    /// Bundled files the page may request from the `assets` host, keyed by URL path.
    private static let assets: [String: (name: String, fileExtension: String, mimeType: String)] = [
        "/LXGWWenKai-Regular.ttf": ("LXGWWenKai-Regular", "ttf", "font/ttf"),
    ]

    /// Folder of the open document, or nil for an unsaved one.
    package var folder: DocumentFolder?

    /// The extra path component lets WebKit normalize links without turning a path
    /// above the document folder into a different file inside that folder.
    package nonisolated static func documentPath(for url: URL) -> String? {
        guard url.scheme == scheme, url.host == documentHost,
              url.path.hasPrefix(documentPathPrefix) else { return nil }
        return String(url.path.dropFirst(documentPathPrefix.count))
    }

    package func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let payload = url.host == Self.assetsHost ? asset(for: url) : image(for: url) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        task.didReceive(payload.response)
        task.didReceive(payload.data)
        task.didFinish()
    }

    package func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private func asset(for url: URL) -> (data: Data, response: URLResponse)? {
        guard let asset = Self.assets[url.path],
              let file = BundledResource.url(asset.name, asset.fileExtension),
              let data = try? Data(contentsOf: file, options: .mappedIfSafe),
              // The page's origin is the `document` host, so fonts need a CORS header.
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
                  "Content-Type": asset.mimeType, "Access-Control-Allow-Origin": "*",
              ]) else { return nil }
        return (data, response)
    }

    private func image(for url: URL) -> (data: Data, response: URLResponse)? {
        guard let path = Self.documentPath(for: url), let file = folder?.file(atPath: path),
              let type = UTType(filenameExtension: file.pathExtension), type.conforms(to: .image),
              let data = try? Data(contentsOf: file) else { return nil }
        let response = URLResponse(url: url, mimeType: type.preferredMIMEType,
                                   expectedContentLength: data.count, textEncodingName: nil)
        return (data, response)
    }
}
