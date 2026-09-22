import TrainingCore

extension RacePriority {
    /// A short, human-readable label — `TrainingCore` has no opinion on display strings, same
    /// reasoning as `Sport+Display.swift`.
    var label: String {
        switch self {
        case .primary: "Primary (A race)"
        case .secondary: "Secondary (B race)"
        case .tertiary: "Tertiary (C race)"
        }
    }
}
