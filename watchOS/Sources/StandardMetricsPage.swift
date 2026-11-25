import SwiftUI
import TrainingCore
import TrainingWatchKit

/// One value of the standard metrics screen.
enum RunMetric: CaseIterable {
    case totalTime, distance, heartRate, currentPace, averagePace
}

/// The standard metrics screen of a run, a list of values with no dial: total time, distance, the
/// heart rate with its zone (blue under the step's target, red over it, white in it or with no target) on the same line, the current pace and the average
/// pace. Every value is aligned to the leading edge, except the zone, which is at the trailing edge
/// of the heart-rate line. The lines sit together at the bottom of the screen and the screen does not
/// fill up: with fewer ``metrics`` (one day they are the athlete's choice, WATCH-109) the ones left
/// stay at the bottom.
///
/// Units follow the system's region for now; the athlete's own setting comes later (WATCH-115).
struct StandardMetricsPage: View {
    let recorder: RunRecorder
    let zoneStore: WatchZoneStore
    var metrics: [RunMetric] = RunMetric.allCases

    /// The room kept free at the bottom for the page indicator (a guess to check on a watch).
    private static let bottomInset = 22.0
    private static let sidePadding = 8.0
    private static let valueSize = 30.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = context.date
            VStack(alignment: .leading, spacing: 0) {
                ForEach(metrics, id: \.self) { metric in
                    row(metric, at: date)
                }
                if recorder.phase == .paused {
                    Text("Paused").font(.system(size: 12)).foregroundStyle(.yellow)
                }
            }
            .padding(.horizontal, Self.sidePadding)
            .padding(.bottom, Self.bottomInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    @ViewBuilder
    private func row(_ metric: RunMetric, at date: Date) -> some View {
        switch metric {
        case .totalTime:
            let elapsed = recorder.elapsed(at: date)
            // Yellow, as the elapsed time is in the Workout app.
            value(ZoneDialText.totalTimeText(elapsed)).foregroundStyle(.yellow)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Total time")
                .accessibilityValue(spokenDuration(elapsed))
        case .distance:
            let amount = PaceText.distanceValue(meters: recorder.distanceMeters)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                value(amount)
                unit(PaceText.distanceUnit())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Distance")
            .accessibilityValue("\(amount) \(PaceText.usesKilometres() ? "kilometres" : "miles")")
        case .heartRate:
            heartRateLine
        case .currentPace:
            paceLine(recorder.currentSecondsPerMeter(at: date), label: "Current pace", caption: "CURRENT")
        case .averagePace:
            paceLine(recorder.averageSecondsPerMeter, label: "Average pace", caption: "AVERAGE")
        }
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Self.valueSize, weight: .medium, design: .rounded).monospacedDigit())
            .lineLimit(1).minimumScaleFactor(0.5)
            // The digits have no descenders: the row is shorter than the text's own line, so the rows sit
            // close together, as in the Workout app.
            .padding(.vertical, -Self.valueSize * 0.14)
    }

    /// A unit in small capitals beside a value.
    private func unit(_ text: String) -> some View {
        Text(text).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
    }

    /// A pace such as `9'24"`, with its caption in two lines beside it, together no taller than the value: "CURRENT" over "PACE".
    private func paceLine(_ secondsPerMeter: Double?, label: String, caption: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            value(PaceText.markedText(secondsPerMeter: secondsPerMeter))
            VStack(alignment: .leading, spacing: -2) {
                Text(caption)
                Text("PACE")
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(secondsPerMeter == nil ? "no pace yet" : Self.spokenPace(PaceText.text(secondsPerMeter: secondsPerMeter)))
    }

    /// "5 minutes 32 seconds per kilometre", for "5:32".
    private static func spokenPace(_ text: String) -> String {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return text }
        return "\(parts[0]) minutes \(parts[1]) seconds per \(PaceText.usesKilometres() ? "kilometre" : "mile")"
    }

    /// The heart rate at the leading edge and its place in the zones at the trailing edge, both coloured
    /// by the target; the value is grey with no reading.
    private var heartRateLine: some View {
        let bands = zoneStore.bands
        let bpm = recorder.heartRate
        // Blue under the step's heart-rate target, red over it, white in it or with no target, as on the dial.
        let target = recorder.stepEngine?.current.flatMap { StepHeartRateTarget(step: $0.step, bands: bands) }
        let status = bpm.flatMap { bpm in target?.status(forHeartRate: bpm) }
        let color = StepHeartRateTarget.Status.displayColor(status)
        let position = bpm.flatMap { bpm in bands.map { $0.position(forHeartRate: bpm) } }
        return HStack(alignment: .lastTextBaseline, spacing: 3) {
            value(bpm.map { "\(Int($0.rounded()))" } ?? "--").foregroundStyle(bpm == nil ? Color.secondary : color)
            unit("BPM")
            Spacer(minLength: 4)
            Text(position.map(ZoneDialText.positionText) ?? "Z --")
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate")
        .accessibilityValue(spokenHeartRate(bpm: bpm, position: position))
    }

    private func spokenHeartRate(bpm: Double?, position: Double?) -> String {
        guard let bpm else { return "no reading" }
        let rate = "\(Int(bpm.rounded())) beats per minute"
        guard let position else { return rate }
        return rate + ", " + ZoneDialText.positionText(position).replacingOccurrences(of: "Z ", with: "zone ")
    }
}
