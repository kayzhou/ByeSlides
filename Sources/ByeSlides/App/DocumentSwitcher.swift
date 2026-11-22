import AppKit

/// Keeps the native document lifecycle while routing each open action to a single document.
@MainActor
final class DocumentSwitcher: NSObject, NSMenuDelegate {
    static let shared = DocumentSwitcher()

    private var isSwitching = false
    private var closeDecision: ((Bool) -> Void)?
    private var menuUpdateScheduled = false
    private var documents: NSDocumentController { .shared }
    private var current: NSDocument? { documents.currentDocument ?? documents.documents.first }
    private weak var recentMenu: NSMenu?

    func observeFileMenu() {
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification, NSWindow.didBecomeKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(scheduleMenuUpdate), name: name, object: nil)
        }
        scheduleMenuUpdate()
    }

    @objc private func scheduleMenuUpdate() {
        guard !menuUpdateScheduled else { return }
        menuUpdateScheduled = true
        DispatchQueue.main.async {
            self.configureFileMenu()
            self.menuUpdateScheduled = false
        }
    }

    private func configureFileMenu() {
        let menus = NSApp.mainMenu?.items.compactMap(\.submenu) ?? []
        guard let menu = menus.first(where: { menu in
            menu.items.contains { $0.keyEquivalent.lowercased() == "n" && $0.keyEquivalentModifierMask == .command }
        }) else { return }
        // Preserve DocumentGroup's native File menu installation and reroute its open actions.
        for item in menu.items {
            let key = item.keyEquivalent.lowercased()
            if item.keyEquivalentModifierMask == .command {
                if key == "n", item.target !== self { setAction(#selector(newFromMenu(_:)), on: item) }
                if key == "o", item.target !== self { setAction(#selector(openFromMenu(_:)), on: item) }
            }
            if item.action == #selector(NSDocument.duplicate(_:)), !item.isHidden {
                item.isHidden = true
            }
            if let submenu = item.submenu, submenu.delegate !== self,
               submenu.items.contains(where: { $0.action == #selector(NSDocumentController.clearRecentDocuments(_:)) }) {
                recentMenu = submenu
                submenu.delegate = self
                menuNeedsUpdate(submenu)
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = documents.recentDocumentURLs
        for url in urls {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.toolTip = url.path
            item.representedObject = url
            item.target = self
            menu.addItem(item)
        }
        if !urls.isEmpty { menu.addItem(.separator()) }
        let clear = NSMenuItem(title: "清除菜单", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        clear.target = documents
        menu.addItem(clear)
    }

    private func setAction(_ action: Selector, on item: NSMenuItem) {
        item.target = self
        item.action = action
    }

    @objc private func newFromMenu(_ sender: NSMenuItem) { newDocument() }
    @objc private func openFromMenu(_ sender: NSMenuItem) { chooseFile() }
    @objc private func openRecent(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { open(url) }
    }

    func chooseFile() {
        guard canSwitch else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MarkdownDocument.readableContentTypes
        panel.directoryURL = current?.fileURL?.deletingLastPathComponent()
        let didChoose: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async { self.open(url) }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: didChoose)
        } else {
            panel.begin(completionHandler: didChoose)
        }
    }

    func open(_ url: URL) {
        guard canSwitch else { return }
        let previous = current
        if let previous, documents.document(for: url) === previous {
            previous.showWindows()
            previous.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
            return
        }
        isSwitching = true
        documents.openDocument(withContentsOf: url, display: false) { document, _, error in
            guard let document else {
                self.isSwitching = false
                if let error { self.documents.presentError(error) }
                return
            }
            // Keep the current document open if the destination cannot be read or switching is cancelled.
            self.confirmClose(previous) { allowed in
                defer { self.isSwitching = false }
                if allowed { self.show(document, replacing: previous) } else { document.close() }
            }
        }
    }

    func newDocument() {
        guard canSwitch else { return }
        isSwitching = true
        let previous = current
        confirmClose(previous) { allowed in
            defer { self.isSwitching = false }
            guard allowed else { return }
            do {
                let document = try self.documents.openUntitledDocumentAndDisplay(false)
                document.displayName = MarkdownDocument.dateName()
                self.show(document, replacing: previous)
            } catch {
                self.documents.presentError(error)
            }
        }
    }

    private var canSwitch: Bool {
        !isSwitching && NSApp.modalWindow == nil && NSApp.keyWindow?.attachedSheet == nil
    }

    private func confirmClose(_ document: NSDocument?, completion: @escaping (Bool) -> Void) {
        guard let document, documents.documents.contains(where: { $0 === document }) else { completion(true); return }
        closeDecision = completion
        document.canClose(withDelegate: self, shouldClose: #selector(didAskToClose(_:allowed:context:)), contextInfo: nil)
    }

    @objc private func didAskToClose(_ document: NSDocument, allowed: Bool, context: UnsafeMutableRawPointer?) {
        let completion = closeDecision
        closeDecision = nil
        completion?(allowed)
    }

    private func show(_ document: NSDocument, replacing previous: NSDocument?) {
        let previousWindow = previous?.windowControllers.first?.window
        if document.windowControllers.isEmpty { document.makeWindowControllers() }
        if let window = document.windowControllers.first?.window {
            window.tabbingMode = .disallowed
            window.isRestorable = false
            if let previousWindow { window.setFrame(previousWindow.frame, display: false) }
        }
        if let previous, previous !== document, documents.documents.contains(where: { $0 === previous }) {
            previous.close()
        }
        document.showWindows()
        document.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
        scheduleMenuUpdate()
        if let recentMenu, document.fileURL != nil { menuNeedsUpdate(recentMenu) }
    }
}
