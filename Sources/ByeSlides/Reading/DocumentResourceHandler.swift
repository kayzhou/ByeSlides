import UniformTypeIdentifiers
import WebKit

/// Serves `document-resource://` requests for the reading page.
/// Host `assets` serves bundled files such as the reading font; host `document` serves images
/// from the document's folder.
final class DocumentResourceHandler: NSObject, WKURLSchemeHandler {
    nonisolated static let scheme = "document-resource"
    nonisolated static let assetsHost = "assets"
    nonisolated static let documentHost = "document"

    /// Bundled files the page may request from the `assets` host, keyed by URL path.
    private static let assets: [String: (name: String, fileExtension: String, mimeType: String)] = [
        "/LXGWWenKai-Regular.ttf": ("LXGWWenKai-Regular", "ttf", "font/ttf"),
    ]

    var folder: DocumentFolder?

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let payload = url.host == Self.assetsHost ? asset(for: url) : image(for: url) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        task.didReceive(payload.response)
        task.didReceive(payload.data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

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
        guard let file = folder?.file(atPath: url.path),
              let type = UTType(filenameExtension: file.pathExtension), type.conforms(to: .image),
              let data = try? Data(contentsOf: file) else { return nil }
        let response = URLResponse(url: url, mimeType: type.preferredMIMEType,
                                   expectedContentLength: data.count, textEncodingName: nil)
        return (data, response)
    }
}
