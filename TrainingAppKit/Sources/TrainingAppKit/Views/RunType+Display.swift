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

    /// The intensity colour of the run type, so a type reads like the same intensity elsewhere in the app.
    var color: Color { intensityCategory.color }
}
