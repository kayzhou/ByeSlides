import Foundation
import Testing
@testable import ByeSlides
@testable import ByeSlidesCore

/// Builds a document folder in a temporary directory, with a sibling folder outside it.
private struct Fixture {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var notes: URL { base.appendingPathComponent("notes") }
    var folder: DocumentFolder { DocumentFolder(notes) }

    init() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: notes.appendingPathComponent("img"), withIntermediateDirectories: true)
        try fm.createDirectory(at: notes.appendingPathComponent("sub.pdf"), withIntermediateDirectories: true)
        for path in ["notes/img/a.png", "notes/paper.pdf", "notes/app.zip", "secret.png"] {
            try Data().write(to: base.appendingPathComponent(path))
        }
        try fm.createSymbolicLink(at: notes.appendingPathComponent("link.png"),
                                  withDestinationURL: base.appendingPathComponent("secret.png"))
    }
}

struct DocumentFolderTests {
    @Test func resolvesPathsInsideTheFolder() throws {
        let fixture = try Fixture()
        let file = fixture.folder.file(atPath: "/img/a.png")
        #expect(file?.lastPathComponent == "a.png")
    }

    @Test func worksForAFolderAtTheVolumeRoot() {
        let folder = DocumentFolder(URL(fileURLWithPath: "/"))
        #expect(folder.file(atPath: "/usr")?.path == "/usr")
        #expect(folder.file(atPath: "/") == nil)
    }

    @Test(arguments: ["/../secret.png", "/img/../../secret.png", "/link.png", "/"])
    func rejectsPathsThatEscape(path: String) throws {
        #expect(try Fixture().folder.file(atPath: path) == nil)
    }
}

struct LinkPolicyTests {
    @Test(arguments: [
        ("https://example.com/a", true), ("http://example.com", true), ("https:/no-host", false),
        ("mailto:a@example.com", true), ("javascript:alert(1)", false), ("file:///etc/hosts", false),
    ])
    func externalLinks(link: String, opens: Bool) {
        let url = URL(string: link)!
        #expect((LinkPolicy.destination(for: url, in: nil) != nil) == opens)
    }

    @Test(arguments: [
        ("document-resource://document/paper.pdf", true), ("document-resource://document/PAPER.PDF", true), ("document-resource://document/img/a.png", true),
        ("document-resource://document/app.zip", false), ("document-resource://document/sub.pdf", false),
        ("document-resource://document/link.png", false), ("document-resource://assets/paper.pdf", false),
    ])
    func localFiles(link: String, opens: Bool) throws {
        let fixture = try Fixture()
        let target = LinkPolicy.destination(for: URL(string: link)!, in: fixture.folder)
        #expect((target != nil) == opens)
    }
}
