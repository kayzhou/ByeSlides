import AppKit
import SwiftUI
import WebKit

/// Find in reading mode, driven by the Edit > Find menu and the find bar.
@MainActor
final class ReadingFinder: ObservableObject {
    @Published var isVisible = false
    @Published var query = ""
    @Published private(set) var notFound = false
    weak var webView: WKWebView?

    func perform(_ action: NSTextFinder.Action) {
        switch action {
        case .showFindInterface: isVisible = true
        case .nextMatch: find()
        case .previousMatch: find(backwards: true)
        case .setSearchString: useSelection()
        default: break
        }
    }

    func find(backwards: Bool = false) {
        guard let webView, !query.isEmpty else {
            notFound = false
            return
        }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        webView.find(query, configuration: configuration) { [weak self] result in
            self?.notFound = !result.matchFound
        }
    }

    func close() {
        isVisible = false
        notFound = false
        webView?.window?.makeFirstResponder(webView)
    }

    private func useSelection() {
        webView?.evaluateJavaScript("getSelection().toString()") { [weak self] value, _ in
            guard let self, let text = value as? String, !text.isEmpty else { return }
            self.query = text
        }
    }
}

/// A slim bar above the reading page, like Safari's.
struct ReadingFindBar: View {
    @ObservedObject var finder: ReadingFinder
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            if finder.notFound {
                Text("未找到").font(.callout).foregroundStyle(.secondary)
            }
            TextField("查找", text: $finder.query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .focused($fieldFocused)
                .onKeyPress(.return, phases: .down) { press in
                    finder.find(backwards: press.modifiers.contains(.shift))
                    return .handled
                }
                .onChange(of: finder.query) { finder.find() }
            ControlGroup {
                Button { finder.find(backwards: true) } label: { Image(systemName: "chevron.left") }
                    .help("上一个")
                Button { finder.find() } label: { Image(systemName: "chevron.right") }
                    .help("下一个")
            }
            .fixedSize()
            Button("完成") { finder.close() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .onExitCommand { finder.close() }
        .onAppear { fieldFocused = true }
    }
}
