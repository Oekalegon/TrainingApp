import SwiftUI
import TrainingCore
import TrainingWatchKit
import WatchKit

/// One data screen of a run (WATCH-109, WATCH-132), drawn from a ``RunScreen``'s items: metrics (a value
/// with its unit, every value aligned to the leading edge, the heart-rate line with its zone at the
/// trailing edge) and widgets (the step's countdown, the zone bar, the battery with its forecast, the
/// zone histogram). The items sit together at the bottom of the screen, which they needn't fill: with
/// fewer, the ones left stay at the bottom. The standard screen and the zone dial of a planned workout
/// (WATCH-118) are two default screens of this kind.
///
/// Units follow the system's region for now; the athlete's own setting comes later (WATCH-115).
struct RunScreenPage: View {
    let recorder: RunRecorder
    let zoneStore: WatchZoneStore
    let screen: RunScreen
    /// Whether this screen says "Workout done" once the steps are used up: one screen does, not each.
    var showsDoneNote = true

    /// The room kept free at the bottom for the page indicator (a guess to check on a watch).
    private static let bottomInset = 22.0
    private static let sidePadding = 8.0
    /// How far the battery line and bar are kept in from each side: the screen's corners are rounded.
    private static let batteryInset = 10.0
    /// How far down the content starts at the least: the clock sits at the top right and can't be hidden
    /// without private API. A guess to check on a watch.
    private static let contentTop = 34.0
    /// The height of one unit, a metric's row with the gap under it (a guess to check on a watch).
    private static let unitHeight = 28.0
    /// How many units fit this watch under the clock and over the page indicator: 6 on the largest
    /// watches and 5 on the others, where the first items of a full screen are left out.
    private static var fittingUnits: Int {
        let height = WKInterfaceDevice.current().screenBounds.height
        return min(max(Int((height - contentTop - bottomInset) / unitHeight), 3), RunScreen.capacity)
    }
    /// True with the wrist down (WATCH-125): redrawn once a minute, with no seconds.
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        TimelineView(.runScreen(dimmed: dimmed)) { context in
            let date = context.date
            VStack(alignment: .leading, spacing: RunMetricStyle.rowSpacing) {
                ForEach(Array(screen.items(fittingUnits: Self.fittingUnits).enumerated()), id: \.offset) { _, item in
                    switch item {
                    case .metric(let metric): row(metric, at: date)
                    case .widget(let widget): widgetView(widget, at: date)
                    }
                }
                if showsDoneNote, recorder.stepEngine?.isFinished == true {
                    // The steps are used up and the run goes on as a free run.
                    Text("Workout done").font(RunMetricStyle.captionFont).foregroundStyle(.green)
                }
            }
            .opacity(dimmed ? RunMetricStyle.dimmedOpacity : 1)
            .padding(.horizontal, Self.sidePadding)
            .padding(.top, Self.contentTop)
            .padding(.bottom, Self.bottomInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        // The battery level can only be read once monitoring is on; once is enough.
        .onAppear { WKInterfaceDevice.current().isBatteryMonitoringEnabled = true }
    }

    @ViewBuilder
    private func row(_ metric: RunMetric, at date: Date) -> some View {
        switch metric {
        case .totalTime:
            let elapsed = recorder.elapsed(at: date)
            // Yellow, as the elapsed time is in the Workout app.
            value(ZoneDialText.totalTimeText(elapsed, showsSeconds: !dimmed)).foregroundStyle(.yellow)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Total time")
                .accessibilityValue(spokenDuration(elapsed) + (recorder.phase == .paused ? ", paused" : ""))
        case .distance:
            let amount = PaceText.distanceValue(meters: recorder.distanceMeters)
            HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
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
        case .averageHeartRate:
            numberLine(recorder.stats.averageHeartRate, unit: "AVG BPM", label: "Average heart rate", spokenUnit: "beats per minute")
        case .maxHeartRate:
            numberLine(recorder.stats.maxHeartRate, unit: "MAX BPM", label: "Highest heart rate", spokenUnit: "beats per minute")
        case .altitude:
            let metric = PaceText.usesKilometres()
            numberLine(recorder.stats.altitude.map { metric ? $0 : $0 * 3.28084 },
                       unit: metric ? "M ALT" : "FT ALT", label: "Altitude", spokenUnit: metric ? "metres" : "feet")
        case .elevationGain:
            let metric = PaceText.usesKilometres()
            numberLine(recorder.stats.altitude == nil ? nil : (metric ? recorder.stats.elevationGain : recorder.stats.elevationGain * 3.28084),
                       unit: metric ? "M UP" : "FT UP", label: "Elevation gain", spokenUnit: metric ? "metres" : "feet")
        case .grade:
            numberLine(recorder.stats.grade, unit: "% GRADE", label: "Grade", spokenUnit: "percent", decimals: 1)
        case .timeRemaining:
            if let estimate = remainingEstimate(at: date) {
                let text = ZoneDialText.totalTimeText(estimate.seconds, showsSeconds: !dimmed)
                HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
                    value(estimate.isComplete ? text : "≥" + text)
                    RunMetricStyle.caption("TIME", "LEFT")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Time left")
                .accessibilityValue((estimate.isComplete ? "" : "at least ") + spokenDuration(estimate.seconds))
            }
        case .stepTime:
            if let seconds = recorder.stepEngine?.stepElapsed(at: recorder.elapsed(at: date)) {
                HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
                    value(ZoneDialText.totalTimeText(seconds, showsSeconds: !dimmed))
                    RunMetricStyle.caption("STEP", "TIME")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step time").accessibilityValue(spokenDuration(seconds))
            }
        case .stepDistance:
            if let meters = recorder.stepEngine?.stepDistance(at: recorder.distanceMeters) {
                let amount = PaceText.distanceValue(meters: meters)
                HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
                    value(amount)
                    unit(PaceText.distanceUnit())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step distance")
                .accessibilityValue("\(amount) \(PaceText.usesKilometres() ? "kilometres" : "miles")")
            }
        case .timeInZone:
            if let seconds = recorder.secondsInCurrentZone {
                HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
                    value(ZoneDialText.totalTimeText(seconds, showsSeconds: !dimmed))
                    RunMetricStyle.caption("IN", "ZONE")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Time in current zone").accessibilityValue(spokenDuration(seconds))
            } else {
                numberLine(nil, unit: "IN ZONE", label: "Time in current zone", spokenUnit: "")
            }
        case .finishTime:
            if let estimate = remainingEstimate(at: date) {
                let text = date.addingTimeInterval(estimate.seconds).formatted(date: .omitted, time: .shortened)
                HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
                    value(estimate.isComplete ? text : "≥" + text)
                    RunMetricStyle.caption("FINISH", "AT")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Finish time").accessibilityValue((estimate.isComplete ? "" : "at least ") + text)
            }
        }
    }

    /// What is left of the planned workout, counting distances at the pace so far.
    private func remainingEstimate(at date: Date) -> RemainingEstimate? {
        recorder.stepEngine?.remaining(
            progress: recorder.stepProgress(at: date),
            secondsPerMeter: RemainingEstimate.estimatePace(
                current: recorder.currentSecondsPerMeter(at: date), average: recorder.averageSecondsPerMeter))
    }

    /// A number with its unit in small capitals, "--" with no reading.
    private func numberLine(_ number: Double?, unit text: String, label: String, spokenUnit: String, decimals: Int = 0) -> some View {
        let shown = number.map { $0.formatted(.number.precision(.fractionLength(decimals))) } ?? "--"
        return HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
            value(shown).foregroundStyle(number == nil ? Color.secondary : Color.white)
            unit(text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(number == nil ? "no reading" : "\(shown) \(spokenUnit)")
    }

    /// A value in the shared font. It shrinks only when it can't fit and `shrinks` allows it; the heart-rate
    /// line gives it `false`, so the zone's value and the heart rate are always the size of the other metrics.
    private func value(_ text: String, shrinks: Bool = true) -> some View {
        Text(text)
            .font(RunMetricStyle.valueFont)
            .lineLimit(1).minimumScaleFactor(shrinks ? 0.5 : 1)
            // The digits have no descenders: the row is shorter than the text's own line, so the rows sit
            // close together, as in the Workout app.
            .padding(.vertical, -RunMetricStyle.valueSize * 0.14)
    }

    /// A unit in small capitals beside a value.
    private func unit(_ text: String) -> some View {
        Text(text).font(RunMetricStyle.unitFont).foregroundStyle(.secondary)
            .lineLimit(1).minimumScaleFactor(0.6)
    }

    /// A pace such as `9'24"`, with its caption in two lines beside it, together no taller than the value: "CURRENT" over "PACE".
    private func paceLine(_ secondsPerMeter: Double?, label: String, caption: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
            value(PaceText.markedText(secondsPerMeter: secondsPerMeter))
            RunMetricStyle.caption(caption, "PACE")
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
        return HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
            value(bpm.map { "\(Int($0.rounded()))" } ?? "--", shrinks: false).foregroundStyle(bpm == nil ? Color.secondary : color)
            unit("BPM")
            Spacer(minLength: 2)
            HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
                unit("ZONE")
                value(position.map(ZoneDialText.positionValue) ?? "--", shrinks: false).foregroundStyle(color)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate")
        .accessibilityValue(spokenHeartRate(bpm: bpm, position: position, target: target))
    }

    /// "152 beats per minute, zone 2.3, 8 bpm below the target": the colour says the last part to the eye.
    private func spokenHeartRate(bpm: Double?, position: Double?, target: StepHeartRateTarget?) -> String {
        guard let bpm else { return "no reading" }
        var parts = ["\(Int(bpm.rounded())) beats per minute"]
        if let position {
            parts.append(ZoneDialText.positionText(position).replacingOccurrences(of: "Z ", with: "zone "))
        }
        if let target { parts.append(target.position(forHeartRate: bpm).text.lowercased()) }
        return parts.joined(separator: ", ")
    }

    // MARK: Widgets

    @ViewBuilder
    private func widgetView(_ widget: RunWidget, at date: Date) -> some View {
        switch widget {
        case .stepCountdown: stepCountdown(at: date)
        case .zoneBar: zoneBar
        case .battery: battery(at: date)
        case .zoneHistogram: zoneHistogram
        }
    }

    /// The target of the step being run and where the heart rate is against it.
    private var heartRateTarget: StepHeartRateTarget? {
        recorder.stepEngine?.current.flatMap { StepHeartRateTarget(step: $0.step, bands: zoneStore.bands) }
    }

    /// The step's time or distance left, with the interval or step number to the right. Only in a planned
    /// workout with steps left; for an open step a line above says how to go on.
    @ViewBuilder
    private func stepCountdown(at date: Date) -> some View {
        if let engine = recorder.stepEngine, let current = engine.current {
            let progress = recorder.stepProgress(at: date)
            let remaining = progress.flatMap { WatchWorkoutSummary.remainingValue($0, showsSeconds: !dimmed) }
            VStack(alignment: .leading, spacing: RunMetricStyle.rowSpacing) {
                if remaining == nil {
                    Text("Press Next step to move on")
                        .font(RunMetricStyle.captionFont).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                StepCountdownRow(
                    remaining: remaining ?? "Open",
                    place: ZoneDialText.place(of: current, in: engine.steps.count),
                    remainingKind: remaining == nil ? nil : (progress?.remainingTime != nil ? "STEP TIME" : "STEP DISTANCE"))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step")
            .accessibilityValue(spokenStep(current, of: engine.steps.count, progress: progress, isOpen: remaining == nil))
        }
    }

    /// All the zones on one line with the target bright and a triangle at the heart rate. Without a
    /// heart-rate target (a free run, or a step with a pace or power target) it keeps zone 3 in the middle, with no
    /// zone bright and only the triangle moving, so it doesn't re-lay itself at each zone boundary.
    private var zoneBar: some View {
        let bands = zoneStore.bands
        let target = heartRateTarget
        let position = recorder.heartRate.flatMap { bpm in bands.map { $0.position(forHeartRate: bpm) } }
        let topZone = target?.zone ?? 3
        return ZoneDialBar(
            target: Double(topZone), position: position ?? Double(topZone) + 0.5,
            showsMarker: position != nil, highlightsTarget: target != nil,
            targetRange: bands.flatMap { target?.positions(in: $0) })
            .animation(dimmed ? nil : .easeInOut(duration: 0.6), value: topZone)
            .animation(dimmed ? nil : .easeOut(duration: 0.8), value: position)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Heart rate zones")
            .accessibilityValue(spokenZoneBar(target: target, position: position))
    }

    /// The battery's charge and, in a planned workout, the forecast for the end (WATCH-119).
    private func battery(at date: Date) -> some View {
        let battery = BatteryReader.current(elapsed: recorder.elapsed(at: date))
        let projection = recorder.stepEngine.flatMap { engine in
            BatteryProjection(
                battery: battery, readings: recorder.batteryReadings,
                remaining: engine.remaining(progress: recorder.stepProgress(at: date), secondsPerMeter: recorder.secondsPerMeter))
        }
        return BatteryRow(battery: battery, projection: projection, inset: Self.batteryInset, bottomInset: 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Battery")
            .accessibilityValue([battery.spokenText.lowercased(), projection?.spoken].compactMap { $0 }.joined(separator: ", "))
    }

    /// The time in each zone so far, a bar for each of zones 0 (below zone 1) to 5.
    private var zoneHistogram: some View {
        ZoneHistogram(fractions: recorder.zoneTimeFractions)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Time in zones")
            .accessibilityValue(ZoneTimeText.spoken(recorder.zoneTimeFractions))
    }

    private func spokenStep(_ current: PlannedStep, of count: Int, progress: StepProgress?, isOpen: Bool) -> String {
        var parts: [String] = []
        if let progress {
            if let seconds = progress.remainingTime {
                parts.append(Duration.seconds(seconds.rounded(.up)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)) + " left")
            } else if let text = WatchWorkoutSummary.remainingText(progress) {
                parts.append(text)
            }
        }
        parts.append(ZoneDialText.placeLine(current, of: count).lowercased())
        parts.append(ZoneDialText.stepLine(current.step).lowercased())
        if isOpen { parts.append("press Next step to move on") }
        return parts.joined(separator: ", ")
    }

    private func spokenZoneBar(target: StepHeartRateTarget?, position: Double?) -> String {
        var parts: [String] = []
        if let position { parts.append(ZoneDialText.positionText(position).replacingOccurrences(of: "Z ", with: "zone ")) }
        else { parts.append("no heart rate reading") }
        if let target {
            parts.append("target \(target.label)")
            if let bpm = recorder.heartRate { parts.append(target.position(forHeartRate: bpm).text.lowercased()) }
        }
        return parts.joined(separator: ", ")
    }
}

/// The time in each zone as six bars, zone 0 (below zone 1) at the left (WATCH-132).
struct ZoneHistogram: View {
    /// The share of the time in zones 0 to 5, or `nil` before any was measured.
    let fractions: [Double]?
    private static let height = 52.0

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<6, id: \.self) { zone in
                let fraction = fractions?[zone] ?? 0
                VStack(spacing: 1) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.color(zone: zone))
                        .frame(height: max(fraction * (Self.height - 14), 2))
                    Text(zone == 0 ? "0" : "\(zone)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
        .frame(height: Self.height, alignment: .bottom)
    }

    private static func color(zone: Int) -> Color {
        HeartRateZone(rawValue: zone)?.zoneColor ?? .gray
    }
}

/// A time as VoiceOver should say it ("1 hour, 2 minutes, 5 seconds"), so a label can name the
/// value without replacing it.
private func spokenDuration(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds.rounded(.down)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
}
