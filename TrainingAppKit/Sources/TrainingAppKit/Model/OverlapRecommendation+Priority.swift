import TrainingCore

extension OverlapRecommendation {
    /// Which pairing to surface first when an activity is named by several: real issues before a
    /// join suggestion, and a multisport pairing (never an issue) last.
    var priority: Int {
        switch self {
        case .duplicate: 0
        case .merge: 1
        case .conflict: 2
        case .join: 3
        case .possibleMultisport: 4
        }
    }
}
