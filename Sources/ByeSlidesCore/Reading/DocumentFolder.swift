import Foundation

/// The folder holding the open document. Reading mode may only load or open files inside it.
package struct DocumentFolder: Equatable, Sendable {
    package let root: URL

    package init(_ url: URL) {
        root = url.resolvingSymlinksInPath()
    }

    /// The file a URL path points to, or nil if the path escapes the folder,
    /// including through `..` or a symbolic link.
    package func file(atPath path: String) -> URL? {
        let file = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        // Compare components, not strings, so a folder at "/" also works.
        let inside = file.pathComponents.count > root.pathComponents.count
            && file.pathComponents.starts(with: root.pathComponents)
        return inside ? file : nil
    }
}
