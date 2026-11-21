import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownDocument = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

struct Note: FileDocument {
    static let readableContentTypes = [UTType.markdownDocument, .plainText]
    var text = ""
    var encoding = String.Encoding.utf8
    var bom = Data()
    init() {}
    init(configuration: ReadConfiguration) throws {
        guard var data = configuration.file.regularFileContents else { throw CocoaError(.fileReadUnknown) }
        for (prefix, format) in [(Data([0xff,0xfe]), String.Encoding.utf16LittleEndian), (Data([0xfe,0xff]), .utf16BigEndian), (Data([0xef,0xbb,0xbf]), .utf8)] where data.starts(with: prefix) {
            bom = prefix
            encoding = format
            data.removeFirst(prefix.count)
            break
        }
        guard let string = String(data: data, encoding: encoding) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        text = string
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = text.data(using: encoding) else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
        return FileWrapper(regularFileWithContents: bom + data)
    }
}

struct SourceEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var offset: Int
    let fontSize: Int
    final class Coordinator: NSObject, NSTextViewDelegate {
        var owner: SourceEditor
        init(_ owner: SourceEditor) { self.owner = owner }
        func textDidChange(_ n: Notification) {
            guard let view = n.object as? NSTextView, !view.hasMarkedText() else { return }
            if owner.text != view.string { owner.text = view.string }
            syncSelection(view)
        }
        func textViewDidChangeSelection(_ n: Notification) {
            guard let view = n.object as? NSTextView, !view.hasMarkedText() else { return }
            syncSelection(view)
        }
        @MainActor private func syncSelection(_ view: NSTextView) {
            let location = view.selectedRange().location
            if location != NSNotFound, owner.offset != location { owner.offset = location }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollablePlainDocumentContentTextView()
        let view = scroll.documentView as! NSTextView
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.font = .monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        view.textContainerInset = NSSize(width: 20, height: 16)
        view.string = text
        let range = NSRange(location: min(offset,text.utf16.count), length: 0)
        view.setSelectedRange(range)
        view.scrollRangeToVisible(range)
        view.delegate = context.coordinator
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.owner = self
        // The input method owns the marked range until the candidate is committed.
        guard let view = scroll.documentView as? NSTextView, !view.hasMarkedText() else { return }
        if view.font?.pointSize != CGFloat(fontSize) {
            view.font = .monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        }
        if view.string != text { view.string = text }
    }
}

import WebKit
final class ImageLoader: NSObject, WKURLSchemeHandler {
    var directory: URL?
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        if let url = task.request.url, url.host == "assets" {
            guard url.path == "/LXGWWenKai-Regular.ttf",
                  let resource = Bundle.main.url(forResource: "LXGWWenKai-Regular", withExtension: "ttf")
                    ?? Bundle.module.url(forResource: "LXGWWenKai-Regular", withExtension: "ttf", subdirectory: "Resources"),
                  let data = try? Data(contentsOf: resource, options: .mappedIfSafe),
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "font/ttf", "Access-Control-Allow-Origin": "*"]) else {
                task.didFailWithError(URLError(.fileDoesNotExist)); return
            }
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
            return
        }
        guard let root = directory?.resolvingSymlinksInPath(), let url = task.request.url else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let file = root.appendingPathComponent(url.path).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path + "/"), let type = UTType(filenameExtension: file.pathExtension),
              type.conforms(to: .image), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        task.didReceive(URLResponse(url: url, mimeType: type.preferredMIMEType, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

struct ReadingStyle: Equatable {
    let size: Int
    let spacingTenths: Int
    var lineHeight: Double { Double(spacingTenths) / 10 }
}

struct Preview: NSViewRepresentable {
    let text: String
    let directory: URL?
    let style: ReadingStyle

    final class Coordinator: NSObject, WKNavigationDelegate {
        let images = ImageLoader()
        var renderedText: String?
        var style: ReadingStyle?

        func applyStyle(to view: WKWebView) {
            guard let style else { return }
            let script = """
            document.documentElement.style.setProperty('--reading-size', '\(style.size)px');
            document.documentElement.style.setProperty('--line-height', '\(style.lineHeight)');
            """
            view.evaluateJavaScript(script)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyStyle(to: webView)
        }

        private func destination(for url: URL) -> URL? {
            switch url.scheme?.lowercased() {
            case "https", "http": return url.host == nil ? nil : url
            case "mailto": return url
            case "document-resource":
                guard url.host == "document", let root = images.directory?.resolvingSymlinksInPath() else { return nil }
                let file = root.appendingPathComponent(url.path).standardizedFileURL.resolvingSymlinksInPath()
                guard file.path.hasPrefix(root.path + "/"), let type = UTType(filenameExtension: file.pathExtension),
                      type == .pdf || type.conforms(to: .plainText) || type.conforms(to: .image),
                      (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
                return file
            default: return nil
            }
        }
        func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated {
                decisionHandler(.cancel)
                if let url = action.request.url, let target = destination(for: url) {
                    NSWorkspace.shared.open(target)
                }
            } else {
                decisionHandler(.allow)
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(context.coordinator.images, forURLScheme: "document-resource")
        for name in ["markdown-it.min", "purify.min", "reading"] {
            let scriptURL = Bundle.main.url(forResource: name, withExtension: "js")
                ?? Bundle.module.url(forResource: name, withExtension: "js", subdirectory: "Resources")
            if let url = scriptURL, let js = try? String(contentsOf: url, encoding: .utf8) {
                config.userContentController.addUserScript(.init(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            }
        }
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        let c = context.coordinator
        let styleChanged = c.style != style
        c.style = style
        guard text != c.renderedText || directory != c.images.directory else {
            if styleChanged { c.applyStyle(to: view) }
            return
        }
        c.renderedText = text
        c.images.directory = directory
        let encoded = Data(text.utf8).base64EncodedString()
        let nonce = UUID().uuidString
        let html = """
        <!doctype html><meta charset="UTF-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; font-src document-resource:; img-src document-resource: data: https: http:; style-src 'nonce-\(nonce)'; script-src 'nonce-\(nonce)'">
        <style nonce="\(nonce)">
        @font-face { font-family: "LXGW WenKai"; src: url("document-resource://assets/LXGWWenKai-Regular.ttf") format("truetype"); font-weight: 400; font-display: swap }
        :root { color-scheme: light dark; --reading-size: \(style.size)px; --line-height: \(style.lineHeight);
                --quote-border: #96969b; --table-border: #b5b5ba }
        @media (prefers-color-scheme: dark) {
           @font-face { font-family: "LXGW WenKai"; src: url("document-resource://assets/LXGWWenKai-Regular.ttf") format("truetype"); font-weight: 400; font-display: swap }
        :root { --quote-border: #aaaab2; --table-border: #777780 }
        }
        body { font: 400 var(--reading-size)/var(--line-height) "LXGW WenKai", "霞鹜文楷", system-ui; max-width: 39em; margin: auto; padding: 4vh 5vw; overflow-wrap: anywhere }
        p { margin-block: 0 .8em }
        blockquote { margin-inline: 0; padding-inline-start: 1em; border-inline-start: .22em solid var(--quote-border) }
        code, kbd, samp { font-family: ui-monospace, monospace; font-size: .91em }
        :not(pre) > code, kbd { background: #8882; border-radius: .25em; padding: .08em .25em }
        li.task-item { list-style: none }
        ul, ol { padding-inline-start: 1.65em }
        .table-scroll { max-width: 100%; overflow-x: auto; margin-block: .8em }
        table { border-collapse: collapse; width: max-content; max-width: 100% }
        th, td { border: 1px solid var(--table-border); padding: .35em .65em; min-width: 4em; max-width: 24em; vertical-align: top }
        th { background: #8882 }
        hr { border: 0; border-top: 1px solid #8886; margin: 1.6em 0 }
        pre { overflow-x: auto; padding: 1em; background: #8882 }
        img { max-width: 100%; height: auto }
        h1, h2 { line-height: 1.3; text-wrap: balance }
        h1 { font-size: clamp(1.5556em, calc(1.25em + 1vw), 1.7778em) }
        h2 { font-size: 1.3333em }
        h3 { font-size: 1.1667em }
        </style>
        <body><main></main><script nonce="\(nonce)">
        const source = new TextDecoder().decode(Uint8Array.from(atob('\(encoded)'), c => c.charCodeAt(0)));
        displayMarkdown(source);
        </script></body>
        """
        view.loadHTMLString(html, baseURL: URL(string:"document-resource://document/"))
    }
}

struct Editor: View {
    @Binding var note: Note
    let url: URL?
    @SceneStorage("documentMode") private var mode = "编辑"
    @SceneStorage("sourceOffset") private var offset = 0

    @AppStorage("editorFontSize") private var editorSize = 16
    @AppStorage("readerFontSize") private var readerSize = 18
    @AppStorage("readerSpacingTenths") private var spacing = 17
    private var showsTypography = State(initialValue: false)

    private var typographyPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("排版设置").font(.headline)
            Stepper(value: $editorSize, in: 12...32) {
                Text("编辑字号　\(editorSize) pt")
            }
            Stepper(value: $readerSize, in: 12...36) {
                Text("阅读字号　\(readerSize) px")
            }
            Stepper(value: $spacing, in: 12...24) {
                Text("阅读行距　\(Double(spacing) / 10, specifier: "%.1f") 倍")
            }
            Divider()
            Button("恢复默认值") {
                editorSize = 16
                readerSize = 18
                spacing = 17
            }
        }
        .monospacedDigit()
        .padding(18)
        .frame(width: 260)
    }

    // Older windows may restore a mode that no longer exists.
    private var reading: Binding<Bool> {
        Binding(get: { mode == "阅读" }, set: { mode = $0 ? "阅读" : "编辑" })
    }

    var body: some View {
        VStack(spacing: 0) {
            if reading.wrappedValue {
                Preview(text: note.text, directory: url?.deletingLastPathComponent(),
                        style: ReadingStyle(size: readerSize, spacingTenths: spacing))
            } else {
                SourceEditor(text: $note.text, offset: $offset, fontSize: editorSize)
                Divider()
                HStack {
                    Spacer()
                    Text("\(note.text.count) 字符")
                }.font(.caption).padding(8)
            }
        }
        .frame(minWidth: 540, minHeight: 360)
        .toolbar {
            Picker("显示模式", selection: reading) {
                Text("编辑").tag(false)
                Text("阅读").tag(true)
            }.pickerStyle(.segmented)
            Button { showsTypography.wrappedValue.toggle() } label: {
                Text(verbatim: "Aa")
            }
            .accessibilityLabel("排版设置")
            .help("排版设置")
            .popover(isPresented: showsTypography.projectedValue) { typographyPanel }
        }
    }
}

@main struct ByeSlides: App {
    var body: some Scene {
        DocumentGroup(newDocument: Note()) { file in Editor(note: file.$document, url: file.fileURL) }
            .defaultSize(width: 960, height: 640)
    }
}
