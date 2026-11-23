import SwiftUI
import TrainingCore

extension HeartRateZone {
    /// A cool-to-hot ramp from easy (blue) to maximal (red) effort. The one definition both apps
    /// use, so a zone has the same colour on the phone's charts and on the watch.
    public var zoneColor: Color {
        switch self {
        case .recovery: .blue
        case .aerobic: .green
        case .tempo: .yellow
        case .threshold: .orange
        case .anaerobic: .red
        }
    }
}
