import SwiftUI

/// What the athlete did in a step (MVP2-146): time, distance, average heart rate and average pace, as
/// a value over a small caption each. A figure the step didn't record (no distance, or no access to
/// it) is left out rather than shown as zero.
///
/// The figures sit in an adaptive grid, so at large text sizes they wrap onto a second row instead
/// of being cut off.
struct WorkoutStepActualFigures: View {
    let actual: WorkoutStepActual

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), alignment: .leading)], alignment: .leading, spacing: 8) {
            figure(actual.duration, caption: "Time")
            if let distance = actual.distance { figure(distance, caption: "Distance") }
            if let heartRate = actual.averageHeartRate { figure(heartRate, caption: "Avg HR") }
            if let pace = actual.averagePace { figure(pace, caption: "Avg pace") }
        }
        // Read as the one sentence of ``WorkoutStepActual/spokenText`` by the card, not figure by figure.
        .accessibilityHidden(true)
    }

    private func figure(_ value: String, caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

extension WorkoutStepActual {
    /// The figures as VoiceOver reads them, one phrase each, e.g. "recorded 7:52", "1.20 km", "average
    /// heart rate 152", "average pace 6:32 per km".
    var spokenText: [String] {
        var parts = ["recorded \(duration)"]
        if let distance { parts.append(distance) }
        if let averageHeartRate { parts.append("average heart rate \(averageHeartRate)") }
        if let averagePace { parts.append("average pace \(averagePace.replacingOccurrences(of: "/", with: "per "))") }
        return parts
    }
}
