import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownDocument = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// A Markdown file. Saving writes the text back in the encoding it was read with.
struct MarkdownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdownDocument, .plainText]

    var text: String
    private var encoding: TextEncoding

    init(text: String = "") {
        self.text = text
        encoding = .default
    }

    init(data: Data) throws {
        (text, encoding) = try TextEncoding.decode(data)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadUnknown) }
        try self.init(data: data)
    }

    func data() throws -> Data {
        try encoding.encode(text)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try data())
    }
}
