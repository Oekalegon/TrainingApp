import TrainingCore

extension Sport {
    /// A short, human-readable label — `TrainingCore` has no opinion on display strings.
    var displayName: String {
        switch self {
        case .running: "Running"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .strength: "Strength"
        case .walking: "Walking"
        case .rowing: "Rowing"
        case .other(let name): name
        }
    }

    /// An SF Symbol standing in for this sport in the week view's day list.
    var symbolName: String {
        switch self {
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .strength: "figure.strengthtraining.traditional"
        case .walking: "figure.walk"
        case .rowing: "figure.rower"
        case .other: "figure.mixed.cardio"
        }
    }
}
