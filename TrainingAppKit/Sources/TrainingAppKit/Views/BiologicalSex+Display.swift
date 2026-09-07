import TrainingCore

extension BiologicalSex {
    /// A short, human-readable label — `TrainingCore` has no opinion on display strings.
    var displayName: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        case .unspecified: "Unspecified"
        }
    }
}
