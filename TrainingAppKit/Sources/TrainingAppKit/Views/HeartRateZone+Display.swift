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
}
