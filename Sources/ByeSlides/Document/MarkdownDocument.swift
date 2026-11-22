import ByeSlidesCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownDocument = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// An immutable snapshot shared by the editor, reader and print commands. SwiftUI
/// can check whether a snapshot changed without repeatedly comparing the whole text.
final class MarkdownSource: Equatable, Sendable {
    let text: String

    init(_ text: String) { self.text = text }

    static func == (lhs: MarkdownSource, rhs: MarkdownSource) -> Bool { lhs === rhs }
}

/// A Markdown file. Saving writes the text back in the encoding it was read with.
struct MarkdownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdownDocument, .plainText]
    static let markdownExtensions: Set<String> = ["md", "markdown"]

    static func dateName(for date: Date = .now, timeZone: TimeZone = .current) -> String {
        Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day().dateSeparator(.dash).format(date)
    }

    var source: MarkdownSource
    var text: String {
        get { source.text }
        set { source = MarkdownSource(newValue) }
    }
    private var encoding: TextEncoding

    init(text: String = "") {
        source = MarkdownSource(text)
        encoding = .default
    }

    init(data: Data) throws {
        let (text, encoding) = try TextEncoding.decode(data)
        source = MarkdownSource(text)
        self.encoding = encoding
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
