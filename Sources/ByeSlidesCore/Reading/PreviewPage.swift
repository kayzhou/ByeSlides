import Foundation

/// Per-window choices that change how the reading page is built.
package struct PreviewOptions: Equatable, Sendable {
    /// Remote images make the page contact other servers, so they load only on request.
    package var allowsRemoteImages: Bool
    /// Zero-based source line to bring to the top once the page has rendered.
    package var sourceLine: Int

    package init(allowsRemoteImages: Bool = false, sourceLine: Int = 0) {
        self.allowsRemoteImages = allowsRemoteImages
        self.sourceLine = sourceLine
    }
}

/// Builds the self-contained HTML page used by reading mode, printing and Quick Look.
package enum PreviewPage {
    package static let baseURL = URL(string: "\(DocumentResourceHandler.scheme)://\(DocumentResourceHandler.documentHost)/")!

    /// Name of the `WKScriptMessageHandler` the page reports scrolling and button clicks to.
    package static let messageHandler = "reading"

    /// Scripts injected before the page loads, in dependency order. `reading.js` defines `displayMarkdown`.
    package static let scripts: [String] = ["markdown-it.min", "purify.min", "reading"].compactMap {
        BundledResource.string($0, "js")
    }

    private static let stylesheet = BundledResource.string("reading", "css") ?? ""

    package static func html(markdown: String, style: ReadingStyle, options: PreviewOptions = PreviewOptions()) -> String {
        let nonce = UUID().uuidString
        // Base64 keeps arbitrary document text from breaking out of the script literal.
        let source = Data(markdown.utf8).base64EncodedString()
        let scheme = DocumentResourceHandler.scheme
        let images = options.allowsRemoteImages ? "\(scheme): data: https: http:" : "\(scheme): data:"
        let policy = "default-src 'none'; font-src \(scheme):; img-src \(images); "
            + "style-src 'nonce-\(nonce)'; script-src 'nonce-\(nonce)'"
        return """
        <!doctype html><meta charset="UTF-8"><meta http-equiv="Content-Security-Policy" content="\(policy)">
        <style nonce="\(nonce)">
        \(stylesheet)
        :root { \(style.cssDeclarations); --emphasis: \(Palette.emphasis) }
        </style>
        <body><main></main><script nonce="\(nonce)">
        const source = new TextDecoder().decode(Uint8Array.from(atob('\(source)'), c => c.charCodeAt(0)));
        displayMarkdown(source, {remoteImages: \(options.allowsRemoteImages), line: \(options.sourceLine)});
        </script></body>
        """
    }
}
