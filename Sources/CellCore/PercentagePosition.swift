public enum PercentagePosition: String, Sendable, CaseIterable, Identifiable {
    case left, right
    public var id: String { rawValue }
    public var title: String { self == .left ? "Left" : "Right" }
}
