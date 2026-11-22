import SwiftUI

/// How a document window shows its contents.
/// Raw values are persisted in scene storage, so existing windows restore the right mode.
enum DisplayMode: String, CaseIterable, Identifiable {
    case editing = "编辑"
    case reading = "阅读"

    var id: Self { self }

    /// Label in the toolbar's segmented control.
    var title: LocalizedStringKey {
        switch self {
        case .editing: "编辑"
        case .reading: "阅读"
        }
    }

    /// Item in the View menu.
    var menuTitle: LocalizedStringKey {
        switch self {
        case .editing: "编辑模式"
        case .reading: "阅读模式"
        }
    }

    /// ⌘1 and ⌘2, like the view styles in Finder.
    var shortcut: KeyEquivalent {
        switch self {
        case .editing: "1"
        case .reading: "2"
        }
    }
}
