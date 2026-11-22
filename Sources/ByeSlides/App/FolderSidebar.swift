import AppKit
import ByeSlidesCore
import SwiftUI

private struct FolderSidebarKey: FocusedValueKey { typealias Value = Binding<Bool> }
private struct OpenFolderKey: FocusedValueKey { typealias Value = () -> Void }

extension FocusedValues {
    var folderSidebar: Binding<Bool>? {
        get { self[FolderSidebarKey.self] }
        set { self[FolderSidebarKey.self] = newValue }
    }

    var openFolder: (() -> Void)? {
        get { self[OpenFolderKey.self] }
        set { self[OpenFolderKey.self] = newValue }
    }
}

struct FolderBrowserCommands: Commands {
    @FocusedBinding(\.folderSidebar) private var sidebar
    @FocusedValue(\.openFolder) private var openFolder

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("打开文件夹…") { openFolder?() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(openFolder == nil)
        }
        CommandGroup(before: .toolbar) {
            Button(sidebar == true ? "隐藏文件夹侧栏" : "显示文件夹侧栏") { sidebar?.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(sidebar == nil)
        }
    }
}

@MainActor
final class FolderBrowser: ObservableObject {
    @Published private(set) var folder: URL?
    @Published private(set) var revision = 0
    @Published private var expandedFolders: Set<URL> = []
    private var cachedEntries: [URL: [FolderEntry]] = [:]

    private static let folderKey = "sidebarFolderPath"

    init() {
        folder = UserDefaults.standard.string(forKey: Self.folderKey)
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    func chooseFolder(startingAt directory: URL?) {
        guard let window = NSApp.keyWindow, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.prompt = "打开"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = folder ?? directory
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url?.standardizedFileURL, let self else { return }
            if self.folder != url { self.expandedFolders.removeAll() }
            self.folder = url
            UserDefaults.standard.set(url.path, forKey: Self.folderKey)
            self.reload()
        }
    }

    func reload() {
        cachedEntries.removeAll()
        revision += 1
    }

    func entries(at folder: URL) -> [FolderEntry]? { cachedEntries[folder] }

    func rememberEntries(_ entries: [FolderEntry], at folder: URL, for revision: Int) {
        if revision == self.revision { cachedEntries[folder] = entries }
    }

    func expansion(of url: URL) -> Binding<Bool> {
        Binding(get: { self.expandedFolders.contains(url) }, set: { expanded in
            if expanded { self.expandedFolders.insert(url) } else { self.expandedFolders.remove(url) }
        })
    }
}

struct FolderEntry: Identifiable, Sendable {
    let url: URL
    let isFolder: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }

    static func contents(of folder: URL) throws -> [FolderEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey]
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys),
                                                            options: .skipsHiddenFiles)
            .compactMap { url -> FolderEntry? in
                guard let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink != true else { return nil }
                if values.isDirectory == true, values.isPackage != true {
                    return FolderEntry(url: url, isFolder: true)
                }
                guard values.isRegularFile == true, ["md", "markdown", "txt"].contains(url.pathExtension.lowercased())
                else { return nil }
                return FolderEntry(url: url, isFolder: false)
            }
            .sorted { left, right in
                if left.isFolder != right.isFolder { return left.isFolder }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }
}

struct FolderSidebar: View {
    @ObservedObject var browser: FolderBrowser
    let currentFile: URL?

    private func chooseFolder() { browser.chooseFolder(startingAt: currentFile?.deletingLastPathComponent()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(browser.folder?.lastPathComponent ?? "文件夹")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .help(browser.folder?.path ?? "文件夹")
                Spacer(minLength: 0)
                if browser.folder != nil {
                    Button("刷新文件列表", systemImage: "arrow.clockwise", action: browser.reload)
                        .labelStyle(.iconOnly)
                        .help("刷新文件列表")
                }
                if browser.folder != nil {
                    Button("打开文件夹…", systemImage: "folder.badge.plus", action: chooseFolder)
                        .labelStyle(.iconOnly)
                        .help("打开文件夹…")
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .frame(height: 36)

            if let folder = browser.folder {
                ScrollView {
                    FolderContents(folder: folder, browser: browser, currentFile: currentFile?.standardizedFileURL)
                        .id(folder)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
            } else {
                Button("打开文件夹…", action: chooseFolder)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(Color(nsColor: EditorStyle.ink))
        .background(Color(nsColor: NSColor(hex: Palette.chrome)))
    }
}

private struct FolderContents: View {
    let folder: URL
    @ObservedObject var browser: FolderBrowser
    let currentFile: URL?
    private var result = State<Result<[FolderEntry], Error>?>(initialValue: nil)
    private static let rowSpacing: CGFloat = 2

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Self.rowSpacing) {
            switch result.wrappedValue ?? browser.entries(at: folder).map(Result.success) {
            case .success(let entries) where entries.isEmpty:
                status("没有 Markdown 或文本文件")
            case .success(let entries):
                ForEach(entries) { entry in
                    if entry.isFolder {
                        let expansion = browser.expansion(of: entry.url)
                        VStack(alignment: .leading, spacing: Self.rowSpacing) {
                            Button { expansion.wrappedValue.toggle() } label: {
                                row(entry, expanded: expansion.wrappedValue)
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(expansion.wrappedValue ? Text("已展开") : Text("已折叠"))
                            if expansion.wrappedValue {
                                FolderContents(folder: entry.url, browser: browser, currentFile: currentFile)
                                    .padding(.leading, 14)
                            }
                        }
                    } else {
                        let isCurrent = entry.url.standardizedFileURL == currentFile
                        Button { DocumentSwitcher.shared.open(entry.url) } label: {
                            row(entry)
                                .background {
                                    if isCurrent {
                                        RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: NSColor(hex: Palette.selection)))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    }
                }
            case .failure:
                status("无法读取此文件夹")
            case nil:
                ProgressView().controlSize(.small).padding(6)
            }
        }
        .task(id: browser.revision) {
            let url = folder
            let revision = browser.revision
            let contents = await Task.detached(priority: .utility) { Result { try FolderEntry.contents(of: url) } }.value
            guard !Task.isCancelled else { return }
            if case .success(let entries) = contents { browser.rememberEntries(entries, at: url, for: revision) }
            result.wrappedValue = contents
        }
    }

    private func row(_ entry: FolderEntry, expanded: Bool = false) -> some View {
        HStack(spacing: 7) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 10)
                .opacity(entry.isFolder ? 1 : 0)
                .foregroundStyle(Color(nsColor: EditorStyle.muted))
                .accessibilityHidden(true)
            Image(systemName: entry.isFolder ? "folder" : "doc.text")
                .frame(width: 15)
                .foregroundStyle(Color(nsColor: EditorStyle.muted))
                .accessibilityHidden(true)
            Text(entry.name).lineLimit(1)
        }
        .font(.callout)
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 24)
        .contentShape(Rectangle())
        .help(entry.name)
    }

    private func status(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(Color(nsColor: EditorStyle.muted))
            .padding(6)
    }
}
