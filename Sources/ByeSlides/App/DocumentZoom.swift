/// Display scale relative to the font sizes in Settings.
struct DocumentZoom: RawRepresentable, Equatable, Sendable {
    static let standard = DocumentZoom(rawValue: 100)
    private static let range = 50...200
    private static let step = 10

    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = min(max(rawValue, Self.range.lowerBound), Self.range.upperBound)
    }

    var larger: Self { Self(rawValue: rawValue + Self.step) }
    var smaller: Self { Self(rawValue: rawValue - Self.step) }

    func fontSize(_ baseSize: Int) -> Int {
        Int((Double(baseSize) * Double(rawValue) / 100).rounded())
    }
}
