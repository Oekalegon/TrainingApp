import SwiftUI
import WatchKit
import TrainingCore
import TrainingWatchKit

/// The target-zone screen of a planned workout (WATCH-118): the step's countdown with the interval
/// number (5/12, in a repeat) to the right, the heart rate in bpm and its place in the zones, a bar
/// with all the zones on one line (the target three times as wide as the others and bright, and a
/// triangle where the heart rate is), the total time, and the watch's battery at the bottom. The rows sit together at the
/// bottom of the screen, with the room above them left empty.
struct ZoneDialPage: View {
    let recorder: RunRecorder
    let zoneStore: WatchZoneStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let engine = recorder.stepEngine, let current = engine.current {
                Dial(recorder: recorder, bands: zoneStore.bands, engine: engine, current: current, at: context.date)
            }
        }
        // The battery level can only be read once monitoring is on; once is enough.
        .onAppear { WKInterfaceDevice.current().isBatteryMonitoringEnabled = true }
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
        // The reader gives the content the whole screen to fill (the room left over goes between the bar
        // and the total time). The page's own safe area keeps the bottom 40 pt or so free for the page
        // indicator, which left a gap under the battery bar, so the content ignores it, and keeps its own
        // room for the indicator; the top is a fixed way down, whatever the safe area says.
        GeometryReader { _ in
            content(target: target, topZone: topZone, position: position, status: status)
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate zone dial")
        .accessibilityValue(spoken(target: target, position: position))
    }

    /// How far down the content starts: the clock can't be hidden without private API and sits at the
    /// top right, so the countdown starts level with its lower edge. A guess to check on a watch.
    private static let contentTop = 34.0
    /// How far the battery bar is kept in from each side, on top of the content's own padding: the
    /// screen's corners are rounded, so a bar right across the bottom would lose its ends.
    private static let batteryInset = 10.0
    /// The room kept free at the bottom for the page indicator (a guess to check on a watch).
    private static let pageIndicatorHeight = 22.0
    /// The gap between the dial's rows.
    private static let rowSpacing = 6.0
    /// The room on each side of the content.
    private static let sidePadding = 8.0

    private func content(
        target: StepHeartRateTarget?, topZone: Int, position: Double?, status: StepHeartRateTarget.Status?
    ) -> some View {
        let progress = recorder.stepProgress(at: at)
        let remaining = progress.flatMap { WatchWorkoutSummary.remainingValue($0) }
        let battery = BatteryReader.current(elapsed: recorder.elapsed(at: at))
        // Values to the left, the interval to the right.
        return VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ZoneDialCountdown(
                remaining: remaining ?? "Open",
                interval: ZoneDialText.intervalFraction(current),
                remainingKind: remaining == nil ? nil : (progress?.remainingTime != nil ? "TIME" : "DISTANCE"))
            ZoneDialHeartRate(
                heartRate: recorder.heartRate, zoneValue: position.map(ZoneDialText.positionValue),
                color: StepHeartRateTarget.Status.displayColor(status))
                .animation(.easeInOut(duration: 0.4), value: status)
            ZoneDialBar(
                target: Double(topZone), position: position ?? Double(topZone) + 0.5,
                showsMarker: position != nil, highlightsTarget: target != nil,
                targetRange: bands.flatMap { target?.positions(in: $0) })
                .animation(.easeInOut(duration: 0.6), value: topZone)
                .animation(.easeOut(duration: 0.8), value: position)
            ZoneDialTotalTime(text: ZoneDialText.totalTimeText(recorder.elapsed(at: at)))
            ZoneDialBattery(
                battery: battery, projection: projection(for: battery, progress: progress),
                inset: Self.batteryInset, bottomInset: Self.pageIndicatorHeight)
        }
        .padding(.horizontal, Self.sidePadding)
        // At the bottom of the screen, like the standard screen: it needn't fill it up to the top, and
        // the room above the countdown is left empty (`contentTop` is the least it keeps for the clock).
        .padding(.top, Self.contentTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// What the battery will be at the end of the workout (WATCH-119), or `nil` when that isn't known.
    private func projection(for battery: BatteryDisplay, progress: StepProgress?) -> BatteryProjection? {
        BatteryProjection(
            battery: battery, readings: recorder.batteryReadings,
            remaining: engine.remaining(progress: progress, secondsPerMeter: recorder.secondsPerMeter))
    }

    /// Everything on the screen as one sentence, since the bar and the colours say nothing to VoiceOver.
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
        let battery = BatteryReader.current(elapsed: recorder.elapsed(at: at))
        parts.append(battery.spokenText.lowercased())
        if let projection = projection(for: battery, progress: recorder.stepProgress(at: at)) {
            parts.append(projection.spoken)
        }
        return parts.joined(separator: ", ")
    }
}

extension StepHeartRateTarget.Status {
    /// The colour of the heart rate and its zone against the step's target: blue under it, red over it,
    /// white in it (and without a target), so a glance says whether to speed up or slow down. Shared
    /// by the zone dial and the standard metrics screen.
    static func displayColor(_ status: StepHeartRateTarget.Status?) -> Color {
        switch status {
        case .below: Color(red: 0.35, green: 0.65, blue: 1.0)
        case .above: Color(red: 1.0, green: 0.4, blue: 0.4)
        case .inside, nil: .white
        }
    }
}
