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

    /// The SF Symbol marking a race of this priority on the calendar: a filled circle holding the
    /// letter A (primary), B (secondary) or C (tertiary).
    var markerSymbolName: String {
        switch self {
        case .primary: "a.circle.fill"
        case .secondary: "b.circle.fill"
        case .tertiary: "c.circle.fill"
        }
    }

    /// Lowercase priority name for accessibility labels.
    var displayName: String {
        switch self {
        case .primary: "Primary"
        case .secondary: "Secondary"
        case .tertiary: "Tertiary"
        }
    }
}
