import Foundation
import Testing
@testable import ByeSlides

struct FolderEntryTests {
    @Test func listsADirectoryLevelWithoutFollowingLinksOrShowingAssets() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appending(path: "ByeSlides-\(UUID())", directoryHint: .isDirectory)
        let child = root.appending(path: "笔记", directoryHint: .isDirectory)
        try manager.createDirectory(at: child, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        for name in ["10.md", "2.MD", "草稿.txt", ".hidden.md", "image.png"] {
            try Data().write(to: root.appending(path: name))
        }
        try Data().write(to: child.appending(path: "计划.markdown"))
        try manager.createSymbolicLink(at: root.appending(path: "loop"), withDestinationURL: root)

        let entries = try FolderEntry.contents(of: root)
        #expect(entries.map(\.name) == ["笔记", "2.MD", "10.md", "草稿.txt"])
        #expect(entries.map(\.isFolder) == [true, false, false, false])
        #expect(try FolderEntry.contents(of: child).map(\.name) == ["计划.markdown"])
    }
}
