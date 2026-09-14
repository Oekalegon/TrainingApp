import SwiftUI
import TrainingCore

extension TSBZone {
    /// A short, human-readable label — `TrainingCore` has no opinion on display strings. Matches
    /// `FitnessChartView`'s own chart-band labels (MVP1-55).
    var label: String {
        switch self {
        case .injuryRisk: "Risk"
        case .training: "Training"
        case .recovery: "Recovery"
        case .race: "Race"
        case .detraining: "Rest"
        }
    }

    /// Band color for `FitnessChartView`'s chart and the metrics info sheet's own Form chart
    /// (MVP1-45) — a red-to-blue ramp from `injuryRisk` (most fatigued) to `detraining` (most
    /// rested), the opposite direction from `HeartRateZone.color`'s "harder is redder" ramp, since
    /// TSB's own "high" end is rest, not effort.
    var color: Color {
        switch self {
        case .injuryRisk: .red
        case .training: .orange
        case .recovery: .yellow
        case .race: .green
        case .detraining: .blue
        }
    }

    /// Plain-language description of this zone (MVP1-45), condensed from this case's own doc
    /// comment in `TrainingCore` (itself citing Friel's *Training Bible*/TrainingPeaks' PMC
    /// guidance) — explains what a day landing in this zone actually means for the athlete.
    var explanation: String {
        switch self {
        case .injuryRisk:
            return "Fatigue is badly outpacing fitness — the classic overreaching zone, with "
                + "elevated injury/illness risk if sustained."
        case .training:
            return "Sustained hard training, building fitness at a normal, tolerable cost."
        case .recovery:
            return "Roughly balanced — fatigue has largely cleared without meaningful fitness "
                + "loss, a sustainable zone for maintaining."
        case .race:
            return "Fresh with fitness still largely intact — the same taper/race-ready window "
                + "a plan's own race-day check looks for."
        case .detraining:
            return "Rest sustained long enough to start losing fitness, not just fatigue."
        }
    }
}
