import Foundation

/// Builds the self-contained HTML page that reading mode loads.
enum PreviewPage {
    static let baseURL = URL(string: "\(DocumentResourceHandler.scheme)://\(DocumentResourceHandler.documentHost)/")!

    /// Scripts injected before the page loads, in dependency order. `reading.js` defines `displayMarkdown`.
    static let scripts: [String] = ["markdown-it.min", "purify.min", "reading"].compactMap {
        BundledResource.string($0, "js")
    }

    private static let stylesheet = BundledResource.string("reading", "css") ?? ""

    static func html(markdown: String, style: ReadingStyle) -> String {
        let nonce = UUID().uuidString
        // Base64 keeps arbitrary document text from breaking out of the script literal.
        let source = Data(markdown.utf8).base64EncodedString()
        let policy = "default-src 'none'; font-src \(DocumentResourceHandler.scheme):; "
            + "img-src \(DocumentResourceHandler.scheme): data: https: http:; "
            + "style-src 'nonce-\(nonce)'; script-src 'nonce-\(nonce)'"
        return """
        <!doctype html><meta charset="UTF-8"><meta http-equiv="Content-Security-Policy" content="\(policy)">
        <style nonce="\(nonce)">
        \(stylesheet)
        :root { \(style.cssDeclarations) }
        </style>
        <body><main></main><script nonce="\(nonce)">
        const source = new TextDecoder().decode(Uint8Array.from(atob('\(source)'), c => c.charCodeAt(0)));
        displayMarkdown(source);
        </script></body>
        """
    }
}
