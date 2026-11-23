import SwiftUI
import TrainingCore
import TrainingWatchKit

/// The target-zone screen of a planned workout (WATCH-118): a ring round the screen's edge with the
/// target zone bright on top and a triangle where the heart rate is, the heart rate's place in the
/// zones and in bpm, the step's countdown and the total time. When the target zone changes, the ring turns.
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
        // A step with no heart-rate target has no zone for the top: the ring keeps zone 3 there, so it
        // doesn't re-lay itself at each zone boundary, with no sector bright and only the triangle moving.
        let topZone = target?.zone ?? 3
        let status = recorder.heartRate.flatMap { bpm in target?.status(forHeartRate: bpm) }
        // The reader keeps to the safe area, whose top inset is what the system keeps free for the
        // clock; the ring and the background then reach past it and the ring starts below it.
        GeometryReader { outer in
        let clock = max(outer.safeAreaInsets.top, Self.minimumClockHeight)
        ZStack {
            // Dark blue below the target and dark red above it, black in it, so a glance says
            // whether to speed up or slow down.
            Self.background(for: status)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: status)
            GeometryReader { proxy in
                ZoneDialRing(
                    target: Double(topZone), position: position ?? Double(topZone) + 0.5,
                    showsMarker: position != nil, highlightsTarget: target != nil,
                    targetRange: bands.flatMap { target?.positions(in: $0) },
                    lineWidth: 9, cornerRadius: min(proxy.size.width, proxy.size.height) * 0.26,
                    topInset: clock)
                    .animation(.easeInOut(duration: 0.6), value: topZone)
                    .animation(.easeOut(duration: 0.8), value: position)
            }
            .ignoresSafeArea()
            GeometryReader { proxy in
                content(
                    position: position, timerSize: min(40, proxy.size.width * 0.2),
                    extraTop: max(clock - outer.safeAreaInsets.top, 0))
            }
        }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate zone dial")
        .accessibilityValue(spoken(target: target, position: position))
    }

    /// The least room kept free at the top for the watch's clock, which can't be hidden without private
    /// API, when the safe area says less. The ring and the text stay below the larger of the two.
    private static let minimumClockHeight = 30.0

    /// Black in the target, dark blue under it and dark red over it.
    private static func background(for status: StepHeartRateTarget.Status?) -> Color {
        switch status {
        case .below: Color(red: 0.0, green: 0.04, blue: 0.18)
        case .above: Color(red: 0.14, green: 0.01, blue: 0.01)
        case .inside, nil: .black
        }
    }

    private func content(position: Double?, timerSize: Double, extraTop: Double) -> some View {
        let progress = recorder.stepProgress(at: at)
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(position.map(ZoneDialText.positionText) ?? "Z --")
                    .font(.system(size: 32, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(recorder.heartRate.map { "\(Int($0.rounded()))" } ?? "--")
                        .font(.system(size: 32, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                    Text("BPM").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            Text(progress.flatMap { WatchWorkoutSummary.remainingValue($0) } ?? "Open")
                .font(.system(size: timerSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(.yellow)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(Duration.seconds(recorder.elapsed(at: at)), format: .time(pattern: .hourMinuteSecond))
                .font(.system(size: timerSize, weight: .semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 18)
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
