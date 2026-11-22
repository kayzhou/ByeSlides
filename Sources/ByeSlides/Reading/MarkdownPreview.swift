import ByeSlidesCore
import SwiftUI
import WebKit

/// Reading mode: renders the document's Markdown in a `WKWebView`.
struct MarkdownPreview: NSViewRepresentable {
    let source: MarkdownSource
    /// Folder of the saved document, used to resolve relative images and links.
    let directory: URL?
    let style: ReadingStyle
    let allowsRemoteImages: Bool
    let offersRemoteImages: Bool
    let anchor: ScrollAnchor
    let finder: ReadingFinder
    /// Called when the reader clicks “载入” in the remote image notice.
    let loadRemoteImages: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ReadingWebView {
        let coordinator = context.coordinator
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(coordinator.resources, forURLScheme: DocumentResourceHandler.scheme)
        for script in PreviewPage.scripts {
            config.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        config.userContentController.add(coordinator, name: PreviewPage.messageHandler)
        let view = ReadingWebView(frame: .zero, configuration: config)
        view.navigationDelegate = coordinator
        view.onFind = { [weak finder] action in finder?.perform(action) }
        finder.webView = view
        // Lets ⌘F and the arrow keys reach the page without clicking it first.
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: ReadingWebView, context: Context) {
        context.coordinator.owner = self
        context.coordinator.update(view)
    }

    static func dismantleNSView(_ view: ReadingWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: PreviewPage.messageHandler)
    }
}

/// The reading view's web view. It answers the Find menu, which `WKWebView` alone does not.
final class ReadingWebView: WKWebView {
    var onFind: ((NSTextFinder.Action) -> Void)?

    private static let findActions: [NSTextFinder.Action] = [.showFindInterface, .nextMatch, .previousMatch, .setSearchString]

    @objc func performFindPanelAction(_ sender: Any?) {
        guard let tag = (sender as? NSValidatedUserInterfaceItem)?.tag,
              let action = NSTextFinder.Action(rawValue: tag), Self.findActions.contains(action) else { return }
        onFind?(action)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(performFindPanelAction(_:)) {
            return NSTextFinder.Action(rawValue: item.tag).map(Self.findActions.contains) ?? false
        }
        return super.validateUserInterfaceItem(item)
    }
}
