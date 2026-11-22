import SwiftUI

/// How a document window shows its contents.
/// Raw values are persisted in scene storage, so existing windows restore the right mode.
enum DisplayMode: String, CaseIterable, Identifiable {
    case editing = "编辑"
    case reading = "阅读"

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .editing: "编辑"
        case .reading: "阅读"
        }
    }
}
