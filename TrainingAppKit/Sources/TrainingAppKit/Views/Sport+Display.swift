import TrainingCore

extension Sport {
    /// A short, human-readable label — `TrainingCore` has no opinion on display strings.
    var displayName: String {
        switch self {
        case .running: "Running"
        case .indoorRunning: "Indoor Running"
        case .outdoorRunning: "Outdoor Running"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .strength: "Strength"
        case .coreStrengthTraining: "Core Strength Training"
        case .walking: "Walking"
        case .rowing: "Rowing"
        case .hiking: "Hiking"
        case .other(let name): name
        }
    }

    /// An SF Symbol standing in for this sport in the week view's day list.
    var symbolName: String {
        switch self {
        case .running, .indoorRunning, .outdoorRunning: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .strength: "figure.strengthtraining.traditional"
        case .coreStrengthTraining: "figure.core.training"
        case .walking: "figure.walk"
        case .rowing: "figure.rower"
        case .hiking: "figure.hiking"
        case .other: "figure.mixed.cardio"
        }
    }

    /// Whether duration/distance/elevation are meaningful stats for this sport — used by the day
    /// list's activity cards (MVP1-41) to decide whether to show a second stats line at all.
    /// `.strength`/`.other` have no reliable distance, so they show just the headline line.
    var isEndurance: Bool {
        switch self {
        case .running, .indoorRunning, .outdoorRunning, .cycling, .swimming, .walking, .rowing, .hiking: true
        case .strength, .coreStrengthTraining, .other: false
        }
    }
}
