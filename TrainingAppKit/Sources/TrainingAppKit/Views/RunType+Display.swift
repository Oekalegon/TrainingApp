import SwiftUI
import TrainingCore

extension RunType {
    /// The name shown on a run type chip; `TrainingCore` has no opinion on display strings.
    var displayName: String {
        switch self {
        case .recovery: "Recovery"
        case .easy: "Easy"
        case .long: "Long"
        case .threshold: "Threshold"
        case .interval: "Interval"
        }
    }
}

extension RunType {
    /// A one-line description of the kind of run, shown under its name when the athlete picks run types.
    var summary: String {
        switch self {
        case .recovery: "Very easy and short, to recover between harder days."
        case .easy: "A comfortable aerobic run you could hold a conversation on."
        case .long: "The longest run of the micro-cycle, at an easy pace."
        case .threshold: "A sustained effort at threshold pace, such as a tempo run."
        case .interval: "Repeated hard efforts with recoveries in between."
        }
    }
}
