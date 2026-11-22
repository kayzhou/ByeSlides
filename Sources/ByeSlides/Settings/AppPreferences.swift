struct AppPreference<Value: Sendable>: Sendable {
    let key: String
    let defaultValue: Value

    init(_ key: String, _ defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }
}

enum AppPreferences {
    static let launch = AppPreference("launchAction", LaunchAction.dailyNote)
    static let openingMode = AppPreference("openingMode", DisplayMode.editing)
    static let highlightLine = AppPreference("highlightLine", true)
    static let showWordCount = AppPreference("showWordCount", true)
    static let continueLists = AppPreference("continueLists", true)
    static let readerJustifies = AppPreference("readerJustifies", true)
    static let readerSpacedScripts = AppPreference("readerSpacedScripts", true)
    static let readerHangingPunctuation = AppPreference("readerHangingPunctuation", true)
    static let remoteImages = AppPreference("remoteImagePolicy", RemoteImagePolicy.ask)
    static let typingSound = AppPreference("typingSoundEnabled", true)
    static let typingTone = AppPreference("typingSoundTone", TypingTone.crisp)
    static let typingVolume = AppPreference("typingSoundVolume", 0.25)
}

enum LaunchAction: String, CaseIterable, Identifiable, Sendable {
    case dailyNote, blankDocument, noDocument

    var id: Self { self }

    var title: String {
        switch self {
        case .dailyNote: "打开当天文稿"
        case .blankDocument: "新建空白文稿"
        case .noDocument: "只启动应用"
        }
    }
}

enum RemoteImagePolicy: String, CaseIterable, Identifiable, Sendable {
    case ask, block, load

    var id: Self { self }

    var title: String {
        switch self {
        case .ask: "按需载入"
        case .block: "始终阻止"
        case .load: "自动载入"
        }
    }

    func allowsImages(approvedInWindow: Bool) -> Bool {
        self == .load || (self == .ask && approvedInWindow)
    }
}
