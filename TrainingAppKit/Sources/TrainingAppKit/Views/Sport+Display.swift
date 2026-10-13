import TrainingCore

extension Sport {
    /// A short, human-readable label — `TrainingCore` has no opinion on display strings.
    var displayName: String {
        switch self {
        case .running: "Running"
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

    /// The sports an athlete can choose between, e.g. for their main sport or a performed activity.
    static let selectable: [Sport] = [
        .running, .cycling, .swimming, .strength, .coreStrengthTraining, .walking, .rowing, .hiking
    ]

    /// The label with the venue when there is one, e.g. "Running · Trail".
    func displayName(venue: Venue?) -> String {
        guard let venue else { return displayName }
        return "\(displayName) · \(venue.displayName)"
    }

    /// An SF Symbol standing in for this sport in the week view's day list.
    var symbolName: String { symbolName(venue: nil) }

    /// The symbol for this sport done at `venue`: a treadmill, a track or an indoor bike where
    /// there is one, else ``symbolName``'s.
    func symbolName(venue: Venue?) -> String {
        switch (self, venue) {
        case (.running, .indoor(.treadmill)?): return "figure.run.treadmill"
        case (.running, .indoor(.track)?), (.running, .outdoor(.track)?): return "figure.track.and.field"
        case (.cycling, .indoor?): return "figure.indoor.cycle"
        case (.walking, .indoor(.treadmill)?): return "figure.walk.treadmill"
        case (.rowing, .indoor?): return "figure.indoor.rowing"
        default: break
        }
        return switch self {
        case .running: "figure.run"
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
        case .running, .cycling, .swimming, .walking, .rowing, .hiking: true
        case .strength, .coreStrengthTraining, .other: false
        }
    }

    /// Whether the 80/20 (LIT, "Low Intensity Training") polarized-training split (MVP1-48) is a
    /// meaningful figure for this sport — narrower than ``isEndurance``. This is about a sport
    /// where the athlete deliberately trains a mix of easy and hard sessions, so the split actually
    /// says something; an incidentally low-intensity sport like ``walking``/``hiking`` would
    /// trivially read close to 100% low every week regardless of training discipline, which is
    /// noise rather than a useful signal.
    var supportsLowIntensityTrainingSplit: Bool {
        switch self {
        case .running, .cycling: true
        case .swimming, .strength, .coreStrengthTraining, .walking, .rowing, .hiking, .other: false
        }
    }
}

extension Venue {
    /// A short, human-readable label.
    var displayName: String {
        switch self {
        case .indoor(nil): "Indoors"
        case .indoor(.treadmill): "Treadmill"
        case .indoor(.track): "Indoor Track"
        case .outdoor(nil): "Outdoors"
        case .outdoor(.road): "Road"
        case .outdoor(.track): "Outdoor Track"
        case .outdoor(.trail): "Trail"
        case .outdoor(.offtrail): "Off-Trail"
        }
    }
}

extension WorkoutPurpose {
    /// A short, human-readable label.
    var displayName: String {
        switch self {
        case .general: "Training"
        case .maxHRTest: "Max Heart Rate Test"
        case .lthrTest: "Lactate Threshold Test"
        }
    }

    /// What a field test measures, shown under the picker.
    var explanation: String {
        switch self {
        case .general: ""
        case .maxHRTest: "Done to measure your maximum heart rate, read from the highest rate reached."
        case .lthrTest: "Done to measure your lactate threshold heart rate, read from the last 20 minutes of the effort."
        }
    }
}
