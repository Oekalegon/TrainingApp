import TrainingCore

extension HeartRateZoneMethod {
    /// A short, human-readable label — `TrainingCore` has no opinion on display strings.
    var displayName: String {
        switch self {
        case .percentageOfMaxHeartRate: "% of Max HR"
        case .karvonen: "Karvonen (HR Reserve)"
        case .lactateThreshold: "% of Lactate Threshold"
        }
    }
}
