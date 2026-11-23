import SwiftUI
import TrainingCore
import TrainingWatchKit

/// The target-zone screen of a planned workout (WATCH-118): the step's countdown with the interval
/// number (5/12, in a repeat) to the right, the heart rate's place in the zones and in bpm, a bar with all the zones on one
/// line, the target twice as wide as the others and bright, and a triangle where the heart rate is, and the total time.
struct ZoneDialPage: View {
    let recorder: RunRecorder
    let zoneStore: WatchZoneStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let engine = recorder.stepEngine, let current = engine.current {
                Dial(recorder: recorder, bands: zoneStore.bands, engine: engine, current: current, at: context.date)
            }
        }
    }
}

private struct Dial: View {
    let recorder: RunRecorder
    let bands: ZoneBands?
    let engine: WorkoutStepEngine
    let current: PlannedStep
    let at: Date

    var body: some View {
        let target = StepHeartRateTarget(step: current.step, bands: bands)
        let position = recorder.heartRate.flatMap { bpm in bands.map { $0.position(forHeartRate: bpm) } }
        // A step with no heart-rate target has no zone for the middle: the bar keeps zone 3 there, so it
        // doesn't re-lay itself at each zone boundary, with no zone bright and only the triangle moving.
        let topZone = target?.zone ?? 3
        let status = recorder.heartRate.flatMap { bpm in target?.status(forHeartRate: bpm) }
        // The reader keeps to the safe area, whose top inset is what the system keeps free for the
        // clock; the content starts below the larger of that and the least room for the clock.
        GeometryReader { proxy in
            content(
                target: target, topZone: topZone, position: position, status: status,
                timerSize: min(40, proxy.size.width * 0.2),
                extraTop: max(Self.minimumClockHeight - proxy.safeAreaInsets.top, 0))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate zone dial")
        .accessibilityValue(spoken(target: target, position: position))
    }

    /// The least room kept free at the top for the watch's clock, which can't be hidden without private
    /// API, when the safe area says less.
    private static let minimumClockHeight = 30.0

    /// The colour of the zone and the heart rate: blue under the target, red over it, white in it
    /// (and without a target), so a glance says whether to speed up or slow down.
    private static func color(for status: StepHeartRateTarget.Status?) -> Color {
        switch status {
        case .below: Color(red: 0.35, green: 0.65, blue: 1.0)
        case .above: Color(red: 1.0, green: 0.4, blue: 0.4)
        case .inside, nil: .white
        }
    }

    private func content(
        target: StepHeartRateTarget?, topZone: Int, position: Double?, status: StepHeartRateTarget.Status?,
        timerSize: Double, extraTop: Double
    ) -> some View {
        let progress = recorder.stepProgress(at: at)
        let color = Self.color(for: status)
        // Values to the left, the interval to the right.
        return VStack(alignment: .leading, spacing: 6) {
            // The time left in the step, with which interval it is (5/12) to the right of it.
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(progress.flatMap { WatchWorkoutSummary.remainingValue($0) } ?? "Open")
                    .font(.system(size: timerSize, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.yellow)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                // Only in a repeat: a warm-up, a cool-down or a single run has no interval number.
                if let interval = ZoneDialText.intervalFraction(current) {
                    Text(interval)
                        .font(.system(size: 20, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            // The zone to the left, with its "Z" in the secondary colour and the value in the state's
            // colour, and the heart rate to the right, its "BPM" in the secondary colour.
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Z").foregroundStyle(.secondary)
                    Text(position.map(ZoneDialText.positionValue) ?? "--").foregroundStyle(color)
                }
                .font(.system(size: 32, weight: .semibold).monospacedDigit())
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(recorder.heartRate.map { "\(Int($0.rounded()))" } ?? "--")
                        .font(.system(size: 32, weight: .semibold).monospacedDigit())
                        .foregroundStyle(color)
                    Text("BPM").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: status)
            .lineLimit(1).minimumScaleFactor(0.7)
            ZoneDialBar(
                target: Double(topZone), position: position ?? Double(topZone) + 0.5,
                showsMarker: position != nil, highlightsTarget: target != nil,
                targetRange: bands.flatMap { target?.positions(in: $0) })
                .animation(.easeInOut(duration: 0.6), value: topZone)
                .animation(.easeOut(duration: 0.8), value: position)
            Text(Duration.seconds(recorder.elapsed(at: at)), format: .time(pattern: .hourMinuteSecond))
                .font(.system(size: timerSize, weight: .semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.top, extraTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Everything on the screen as one sentence, since the ring and the colours say nothing to VoiceOver.
    private func spoken(target: StepHeartRateTarget?, position: Double?) -> String {
        var parts: [String] = []
        if let bpm = recorder.heartRate {
            parts.append("Heart rate \(Int(bpm.rounded())) beats per minute")
            if let position { parts.append(ZoneDialText.positionText(position).replacingOccurrences(of: "Z ", with: "zone ")) }
        } else {
            parts.append("No heart rate reading")
        }
        if let target {
            parts.append("target \(target.label)")
            if let bpm = recorder.heartRate { parts.append(target.position(forHeartRate: bpm).text.lowercased()) }
        }
        if let progress = recorder.stepProgress(at: at) {
            if let seconds = progress.remainingTime {
                parts.append(Duration.seconds(seconds.rounded(.up)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)) + " left")
            } else if let text = WatchWorkoutSummary.remainingText(progress) {
                parts.append(text)
            }
        }
        parts.append(ZoneDialText.placeLine(current, of: engine.steps.count).lowercased())
        parts.append(ZoneDialText.stepLine(current.step).lowercased())
        return parts.joined(separator: ", ")
    }
}
