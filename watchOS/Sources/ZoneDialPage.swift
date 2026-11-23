import SwiftUI
import TrainingCore
import TrainingWatchKit

/// The target-zone screen of a planned workout (WATCH-118): the step's countdown with the interval
/// number (5/12, in a repeat) to the right, the heart rate's place in the zones and in bpm, a bar with all the zones on one
/// line, the target three times as wide as the others and bright, and a triangle where the heart rate is, and the total time.
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
                width: proxy.size.width, height: proxy.size.height,
                extraTop: max(Self.minimumClockHeight - proxy.safeAreaInsets.top, 0))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate zone dial")
        .accessibilityValue(spoken(target: target, position: position))
    }

    /// The least room kept free at the top for the watch's clock, which can't be hidden without private
    /// API, when the safe area says less.
    private static let minimumClockHeight = 30.0
    /// The room on each side of the content.
    private static let sidePadding = 8.0
    /// The largest size of the two timers, in points.
    private static let largestTimerSize = 64.0
    /// The room the interval number takes in the countdown's row, with its gap.
    private static let intervalWidth = 64.0
    /// The height of the rows that aren't the timers (the heart rate and zone, the bar and the gaps
    /// between the rows), and a line's height as a multiple of its font size, for sizing the timers.
    private static let otherRowsHeight = 94.0
    private static let lineHeight = 1.2

    /// About how wide a text is in the condensed timer font, in multiples of its font size: a digit
    /// is 0.49 of it, a colon or a point 0.21, anything else 0.47 (measured on the system font, so
    /// "0:24:15" is 2.85). A rough measure, used with some room to spare.
    private static func em(_ text: String) -> Double {
        max(text.reduce(0) { $0 + ($1.isNumber ? 0.49 : ($1 == ":" || $1 == "." ? 0.21 : 0.47)) }, 1)
    }

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
        width: Double, height: Double, extraTop: Double
    ) -> some View {
        let progress = recorder.stepProgress(at: at)
        let color = Self.color(for: status)
        let countdown = progress.flatMap { WatchWorkoutSummary.remainingValue($0) } ?? "Open"
        let total = ZoneDialText.totalTimeText(recorder.elapsed(at: at))
        let interval = ZoneDialText.intervalFraction(current)
        // Both timers have one size, the largest at which the longer of the two fits its row (the
        // countdown's row also holds the interval) and the two rows fit the height under the clock
        // with the other rows: so they match, and neither is squeezed by the other.
        let available = width - 2 * Self.sidePadding
        let timerSize = min(
            Self.largestTimerSize,
            (available - (interval == nil ? 0 : Self.intervalWidth)) / Self.em(countdown),
            available / Self.em(total),
            (height - extraTop - Self.otherRowsHeight) / (2 * Self.lineHeight))
        // Values to the left, the interval to the right.
        return VStack(alignment: .leading, spacing: 6) {
            // The time left in the step, with which interval it is (5/12) to the right of it.
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(countdown)
                    .font(.system(size: timerSize, weight: .semibold).width(.condensed).monospacedDigit())
                    .foregroundStyle(.yellow)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Spacer(minLength: 8)
                // Only in a repeat: a warm-up, a cool-down or a single run has no interval number.
                if let interval {
                    Text(interval)
                        .font(.system(size: 20, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            // The heart rate to the left, its "BPM" in the secondary colour, and the zone to the right,
            // its "Zone" small and in the secondary colour and the value in the state's colour.
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(recorder.heartRate.map { "\(Int($0.rounded()))" } ?? "--")
                        .font(.system(size: 32, weight: .semibold).monospacedDigit())
                        .foregroundStyle(color)
                    Text("BPM").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Zone").font(.system(size: 14)).foregroundStyle(.secondary)
                    Text(position.map(ZoneDialText.positionValue) ?? "--")
                        .font(.system(size: 32, weight: .semibold).monospacedDigit())
                        .foregroundStyle(color)
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
            Text(total)
                .font(.system(size: timerSize, weight: .semibold).width(.condensed).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .padding(.horizontal, Self.sidePadding)
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
