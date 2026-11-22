import Foundation
import UniformTypeIdentifiers

/// Puts pasted or dropped images next to the document and builds the Markdown that shows them.
enum ImageImporter {
    /// Folder beside the document that receives copied images.
    static let folderName = "assets"

    /// An image file. One already inside the document's folder is referenced where it is;
    /// any other is copied into `assets`.
    static func importFile(_ file: URL, into folder: URL) throws -> String {
        let alt = file.deletingPathExtension().lastPathComponent
        if let path = relativePath(of: file, in: folder) { return markdown(alt: alt, path: path) }
        let target = try uniqueURL(named: file.lastPathComponent, in: folder)
        try FileManager.default.copyItem(at: file, to: target)
        return markdown(alt: alt, path: "\(folderName)/\(target.lastPathComponent)")
    }

    /// Image data from the pasteboard, such as a screenshot.
    static func importData(_ data: Data, type: UTType, into folder: URL, date: Date = Date()) throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: date)
        let target = try uniqueURL(named: "image-\(stamp).\(type.preferredFilenameExtension ?? "png")", in: folder)
        try data.write(to: target, options: .withoutOverwriting)
        return markdown(alt: "", path: "\(folderName)/\(target.lastPathComponent)")
    }

    static func markdown(alt: String, path: String) -> String {
        let escapedAlt = alt.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        return "![\(escapedAlt)](\(encode(path)))"
    }

    /// Escapes the characters that would end or break a link destination. Other characters,
    /// Chinese included, stay readable.
    static func encode(_ path: String) -> String {
        var result = path.replacingOccurrences(of: "%", with: "%25")
        for (character, escape) in [(" ", "%20"), ("(", "%28"), (")", "%29"), ("<", "%3C"), (">", "%3E")] {
            result = result.replacingOccurrences(of: character, with: escape)
        }
        return result
    }

    private static func uniqueURL(named name: String, in folder: URL) throws -> URL {
        let directory = folder.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = (name as NSString).deletingPathExtension
        let fileExtension = (name as NSString).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(number)").appendingPathExtension(fileExtension)
            number += 1
        }
        return candidate
    }
}

/// The path of a file relative to the document's folder, if it is inside it.
private func relativePath(of file: URL, in folder: URL) -> String? {
    let fileParts = file.standardizedFileURL.resolvingSymlinksInPath().pathComponents
    let folderParts = folder.standardizedFileURL.resolvingSymlinksInPath().pathComponents
    guard fileParts.count > folderParts.count, fileParts.starts(with: folderParts) else { return nil }
    return fileParts.dropFirst(folderParts.count).joined(separator: "/")
}
