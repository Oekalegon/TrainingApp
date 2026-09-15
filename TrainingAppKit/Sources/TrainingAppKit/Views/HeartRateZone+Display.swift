import SwiftUI
import TrainingCore

extension HeartRateZone {
    /// A short, human-readable label — `TrainingCore` has no opinion on display strings.
    var displayName: String {
        switch self {
        case .recovery: "Recovery"
        case .aerobic: "Aerobic"
        case .tempo: "Tempo"
        case .threshold: "Threshold"
        case .anaerobic: "Anaerobic"
        }
    }

    /// A cool-to-hot ramp from easy (blue) to maximal (red) effort, for shading this zone's band
    /// in charts (e.g. `HeartRateHistogramChartView`) — `TrainingCore` has no opinion on colors either.
    var color: Color {
        switch self {
        case .recovery: .blue
        case .aerobic: .green
        case .tempo: .yellow
        case .threshold: .orange
        case .anaerobic: .red
        }
    }

    /// Plain-language description of this zone (MVP1-60), condensed from this case's own doc
    /// comment in `TrainingCore` — explains what training in this zone actually feels like/is for.
    var explanation: String {
        switch self {
        case .recovery:
            return "Very light effort, easily sustained — active recovery between hard sessions."
        case .aerobic:
            return "Comfortable, conversational effort — the bulk of aerobic base-building volume."
        case .tempo:
            return "Moderately hard, \"comfortably hard\" effort — sustainable for a long interval "
                + "but not a full conversation."
        case .threshold:
            return "Hard effort at or just below lactate threshold — sustainable for tens of "
                + "minutes at most."
        case .anaerobic:
            return "Maximal or near-maximal effort — short, hard intervals near VO2 max."
        }
    }
}
