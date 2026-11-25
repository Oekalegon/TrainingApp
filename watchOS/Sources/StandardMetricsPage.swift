import SwiftUI
import TrainingCore
import TrainingWatchKit

/// One value of the standard metrics screen.
enum RunMetric: CaseIterable {
    case totalTime, distance, heartRate, currentPace, averagePace
}

/// The standard metrics screen of a run, a list of values with no dial: total time, distance, the
/// heart rate with its zone (in the zone's colour) on the same line, the current pace and the average
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
            line(ZoneDialText.totalTimeText(elapsed), label: "Total time", spoken: spokenDuration(elapsed))
        case .distance:
            let text = runDistanceText(recorder.distanceMeters)
            line(text, label: "Distance", spoken: text)
        case .heartRate:
            heartRateLine
        case .currentPace:
            paceLine(recorder.currentSecondsPerMeter(at: date), label: "Current pace", note: "now")
        case .averagePace:
            paceLine(recorder.averageSecondsPerMeter(at: date), label: "Average pace", note: "avg")
        }
    }

    /// A value at the leading edge, shrunk rather than cut when it is too wide.
    private func line(_ text: String, label: String, spoken: String) -> some View {
        value(text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(spoken)
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Self.valueSize, weight: .semibold).width(.condensed).monospacedDigit())
            .lineLimit(1).minimumScaleFactor(0.5)
    }

    private func paceLine(_ secondsPerMeter: Double?, label: String, note: String) -> some View {
        let text = PaceText.text(secondsPerMeter: secondsPerMeter)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            value(text)
            Text("\(PaceText.unit()) \(note)").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(secondsPerMeter == nil ? "no pace yet" : Self.spokenPace(text))
    }

    /// "5 minutes 32 seconds per kilometre", for "5:32".
    private static func spokenPace(_ text: String) -> String {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return text }
        return "\(parts[0]) minutes \(parts[1]) seconds per \(PaceText.usesKilometres() ? "kilometre" : "mile")"
    }

    /// The heart rate at the leading edge and its place in the zones at the trailing edge, both in the
    /// zone's colour; grey with no reading or no zones.
    private var heartRateLine: some View {
        let bands = zoneStore.bands
        let bpm = recorder.heartRate
        let zone = bpm.flatMap { bpm in bands?.zone(forHeartRate: bpm) }
        let color = zone.flatMap { HeartRateZone(rawValue: $0) }?.zoneColor ?? .secondary
        let position = bpm.flatMap { bpm in bands.map { $0.position(forHeartRate: bpm) } }
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            value(bpm.map { "\(Int($0.rounded()))" } ?? "--").foregroundStyle(bpm == nil ? .secondary : color)
            Text("bpm").font(.system(size: 12)).foregroundStyle(.secondary)
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
