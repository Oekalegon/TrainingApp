import SwiftUI
import TrainingCore

/// One data screen of a run (WATCH-109, WATCH-132), drawn from a ``RunScreen``'s items: metrics (a value
/// with its unit, every value aligned to the leading edge, the heart-rate line with its zone at the
/// trailing edge) and widgets (the step's countdown, the zone bar, the battery with its forecast, the
/// zone histogram). The items sit together at the bottom of the screen, which they needn't fill: with
/// fewer, the ones left stay at the bottom. The standard screen and the zone dial of a planned workout
/// (WATCH-118) are two default screens of this kind.
///
/// Units follow the system's region for now; the athlete's own setting comes later (WATCH-115).
public struct RunScreenPage: View {
    let source: any RunScreenSource
    let screen: RunScreen
    /// How many units fit the screen: 6 on the largest watches and 5 on the others, where the first items of a
    /// full screen are left out. See ``fittingUnits(forScreenHeight:)``.
    let fittingUnits: Int
    /// Whether this screen says "Workout done" once the steps are used up: one screen does, not each.
    let showsDoneNote: Bool

    /// - Parameters:
    ///   - source: Where the readings come from: the recorder on the watch, sample values in the editor.
    ///   - screen: The items to draw.
    ///   - fittingUnits: How many units of height fit; the first items of a fuller screen are left out.
    ///   - showsDoneNote: Whether to say "Workout done" when the steps are used up.
    public init(source: any RunScreenSource, screen: RunScreen, fittingUnits: Int = RunScreen.capacity, showsDoneNote: Bool = true) {
        self.source = source
        self.screen = screen
        self.fittingUnits = fittingUnits
        self.showsDoneNote = showsDoneNote
    }

    /// The room kept free at the bottom for the page indicator (a guess to check on a watch).
    static let bottomInset = 22.0
    private static let sidePadding = 8.0
    /// How far the battery line and bar are kept in from each side: the screen's corners are rounded.
    private static let batteryInset = 10.0
    /// How far down the content starts at the least: the clock sits at the top right and can't be hidden
    /// without private API. A guess to check on a watch.
    static let contentTop = 34.0
    /// The height of one unit, a metric's row with the gap under it (a guess to check on a watch).
    static let unitHeight = 28.0
    /// How many units fit a watch whose screen is `height` points tall, under the clock and over the page indicator.
    public static func fittingUnits(forScreenHeight height: Double) -> Int {
        min(max(Int((height - contentTop - bottomInset) / unitHeight), 3), RunScreen.capacity)
    }
    /// True with the wrist down (WATCH-125): redrawn once a minute, with no seconds.
    @Environment(\.isLuminanceReduced) private var dimmed

    public var body: some View {
        TimelineView(.runScreen(dimmed: dimmed)) { context in
            let date = context.date
            VStack(alignment: .leading, spacing: RunMetricStyle.rowSpacing) {
                ForEach(Array(screen.items(fittingUnits: fittingUnits).enumerated()), id: \.offset) { _, item in
                    switch item {
                    case .metric(let metric): row(metric, at: date)
                    case .widget(let widget): widgetView(widget, at: date)
                    case .measure(let quantity, let statistic, let scope): measureRow(quantity, statistic, scope, at: date)
                    case .span(let kind, let scope): spanRow(kind, scope, at: date)
                    }
                }
                if showsDoneNote, source.stepEngine?.isFinished == true {
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
    }

    @ViewBuilder
    private func row(_ metric: RunMetric, at date: Date) -> some View {
        switch metric {
        case .totalTime:
            let elapsed = source.elapsed(at: date)
            // Yellow, as the elapsed time is in the Workout app.
            value(ZoneDialText.totalTimeText(elapsed, showsSeconds: !dimmed)).foregroundStyle(.yellow)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Total time")
                .accessibilityValue(spokenDuration(elapsed) + (source.isPaused ? ", paused" : ""))
        case .distance:
            let amount = PaceText.distanceValue(meters: source.distanceMeters)
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
            paceLine(source.currentSecondsPerMeter(at: date), label: "Current pace", caption: "CURRENT")
        case .averagePace:
            paceLine(source.averageSecondsPerMeter, label: "Average pace", caption: "AVERAGE")
        case .averageHeartRate:
            numberLine(source.stats.averageHeartRate, unit: "AVG BPM", label: "Average heart rate", spokenUnit: "beats per minute")
        case .maxHeartRate:
            numberLine(source.stats.maxHeartRate, unit: "MAX BPM", label: "Highest heart rate", spokenUnit: "beats per minute")
        case .altitude:
            let metric = PaceText.usesKilometres()
            numberLine(source.stats.altitude.map { metric ? $0 : $0 * 3.28084 },
                       unit: metric ? "M" : "FT", caption: "ALTITUDE", label: "Altitude", spokenUnit: metric ? "metres" : "feet")
        case .elevationGain:
            let metric = PaceText.usesKilometres()
            numberLine(source.stats.altitude == nil ? nil : (metric ? source.stats.elevationGain : source.stats.elevationGain * 3.28084),
                       unit: metric ? "M" : "FT", caption: "ASCENT", label: "Elevation gain", spokenUnit: metric ? "metres" : "feet")
        case .grade:
            numberLine(source.stats.grade, unit: "%", caption: "GRADE", label: "Grade", spokenUnit: "percent", decimals: 1)
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
        case .stepNumber:
            if let engine = source.stepEngine, let current = engine.current {
                let place = ZoneDialText.place(of: current, in: engine.steps.count)
                HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
                    value(place.text)
                    unit(place.isRepeat ? "INTERVAL" : "STEP")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step").accessibilityValue(ZoneDialText.placeLine(current, of: engine.steps.count).lowercased())
            }
        case .stepTime:
            if let seconds = source.stepEngine?.stepElapsed(at: source.elapsed(at: date)) {
                HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
                    value(ZoneDialText.totalTimeText(seconds, showsSeconds: !dimmed))
                    RunMetricStyle.caption("STEP", "TIME")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step time").accessibilityValue(spokenDuration(seconds))
            }
        case .stepDistance:
            if let meters = source.stepEngine?.stepDistance(at: source.distanceMeters) {
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
            if let seconds = source.secondsInCurrentZone {
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
        case .timeSinceZoneEntry:
            if let seconds = source.secondsSinceEnteringZone {
                HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
                    value(ZoneDialText.totalTimeText(seconds, showsSeconds: !dimmed))
                    RunMetricStyle.caption("SINCE", "ENTRY")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Time since entering zone").accessibilityValue(spokenDuration(seconds))
            } else {
                numberLine(nil, unit: "IN ZONE", label: "Time since entering zone", spokenUnit: "")
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

    /// A collected reading with one of its statistics: the number, its unit and, for a statistic, "AVG" and so on.
    private func measureRow(_ quantity: RunQuantity, _ statistic: RunStatistic, _ scope: RunScope, at date: Date) -> some View {
        let metric = PaceText.usesKilometres()
        let reading = source.reading(quantity, statistic, scope, at: date)
        let shown = reading.map { quantity.display($0, metric: metric) }
        let unitName = shown?.unit ?? quantity.display(0, metric: metric).unit
        return HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
            value(shown?.number ?? "--").foregroundStyle(reading == nil ? Color.secondary : Color.white)
            if let scopeCaption = scope.caption {
                // A scoped statistic: the unit, then "AVG" over "LAST STEP" and so on.
                unit(unitName)
                RunMetricStyle.caption(statistic.caption(for: quantity), scopeCaption)
            } else {
                unit([statistic.caption(for: quantity), unitName].filter { !$0.isEmpty }.joined(separator: " "))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([statistic.prefix(for: quantity), quantity.title].compactMap { $0 }.joined(separator: " ") + (scope.suffix.map { ", " + $0.lowercased() } ?? ""))
        .accessibilityValue(shown.map { "\($0.number) \(quantity.spokenUnit(metric: metric))" } ?? "no reading")
    }

    /// The time, distance or climb of a step or a split.
    private func spanRow(_ kind: RunSpanKind, _ scope: RunScope, at date: Date) -> some View {
        let reading = source.spans.value(kind, scope, now: source.spanMark(at: date))
        let metric = PaceText.usesKilometres()
        let number: String
        let unitName: String
        let spoken: String
        switch kind {
        case .time:
            number = reading.map { ZoneDialText.totalTimeText($0, showsSeconds: !dimmed) } ?? "--"
            unitName = ""
            spoken = reading.map(spokenDuration) ?? ""
        case .distance:
            number = reading.map { PaceText.distanceValue(meters: $0) } ?? "--"
            unitName = PaceText.distanceUnit()
            spoken = "\(number) \(metric ? "kilometres" : "miles")"
        case .climb:
            let climb = reading.map { metric ? $0 : $0 * 3.28084 }
            number = climb.map { String(format: "%.0f", $0) } ?? "--"
            unitName = metric ? "M" : "FT"
            spoken = "\(number) \(metric ? "metres" : "feet")"
        }
        return HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
            value(number).foregroundStyle(reading == nil ? Color.secondary : Color.white)
            if !unitName.isEmpty { unit(unitName) }
            RunMetricStyle.caption(kind.caption, scope.caption ?? "")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title + ", " + (scope.suffix ?? "").lowercased())
        .accessibilityValue(reading == nil ? "no reading" : spoken)
    }

    /// What is left of the planned workout, counting distances at the pace so far.
    private func remainingEstimate(at date: Date) -> RemainingEstimate? {
        source.stepEngine?.remaining(
            progress: source.stepProgress(at: date),
            secondsPerMeter: RemainingEstimate.estimatePace(
                current: source.currentSecondsPerMeter(at: date), average: source.averageSecondsPerMeter))
    }

    /// A number with its unit in small capitals and, when `caption` is given, a word naming it in the caption size
    /// ("47 M ALTITUDE"), "--" with no reading.
    private func numberLine(_ number: Double?, unit text: String, caption: String? = nil, label: String, spokenUnit: String, decimals: Int = 0) -> some View {
        let shown = number.map { String(format: "%.\(decimals)f", $0) } ?? "--"
        return HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
            value(shown).foregroundStyle(number == nil ? Color.secondary : Color.white)
            unit(text)
            if let caption {
                Text(caption).font(RunMetricStyle.captionFont).foregroundStyle(.secondary).lineLimit(1)
            }
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
        let bands = source.zoneBands
        let bpm = source.heartRate
        // Blue under the step's heart-rate target, red over it, white in it or with no target, as on the dial.
        let target = source.stepEngine?.current.flatMap { StepHeartRateTarget(step: $0.step, bands: bands) }
        let status = bpm.flatMap { bpm in target?.status(forHeartRate: bpm) }
        let color = StepHeartRateTarget.Status.displayColor(status)
        let position = bpm.flatMap { bpm in bands.map { $0.position(forHeartRate: bpm) } }
        return HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
            // The two values keep their size and the small units give way (they shrink to 60 %), so the zone is never
            // cut to an ellipsis on a narrow screen.
            value(bpm.map { "\(Int($0.rounded()))" } ?? "--", shrinks: false).foregroundStyle(bpm == nil ? Color.secondary : color)
                .fixedSize(horizontal: true, vertical: false).layoutPriority(1)
            unit("BPM")
            Spacer(minLength: 2)
            HStack(alignment: .lastTextBaseline, spacing: RunMetricStyle.unitSpacing) {
                // In the small caption size, so the whole word fits beside the zone on a narrow screen.
                Text("ZONE").font(RunMetricStyle.captionFont).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                value(position.map(ZoneDialText.positionValue) ?? "--", shrinks: false).foregroundStyle(color)
                    .fixedSize(horizontal: true, vertical: false).layoutPriority(1)
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
        case .paceBar: paceBar(at: date)
        case .targetBar: targetBar(at: date)
        }
    }

    /// The target of the step being run and where the heart rate is against it.
    private var heartRateTarget: StepHeartRateTarget? {
        source.stepEngine?.current.flatMap { StepHeartRateTarget(step: $0.step, bands: source.zoneBands) }
    }

    /// The step's time or distance left, with the interval or step number to the right. Only in a planned
    /// workout with steps left; for an open step a line above says how to go on.
    @ViewBuilder
    private func stepCountdown(at date: Date) -> some View {
        if let engine = source.stepEngine, let current = engine.current {
            let progress = source.stepProgress(at: date)
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
                    remainingKind: remaining == nil ? nil : (progress?.remainingTime != nil ? "TIME" : "DIST"))
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
        let bands = source.zoneBands
        let target = heartRateTarget
        let position = source.heartRate.flatMap { bpm in bands.map { $0.position(forHeartRate: bpm) } }
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

    /// The bar that fits the step's target: the pace bar for a pace target, the zone bar for a heart-rate target or anything else, so a
    /// screen with this widget shows the right one as the steps change (and the zone bar in a free run).
    @ViewBuilder
    private func targetBar(at date: Date) -> some View {
        if StepPaceTarget.showsPaceBar(for: source.stepEngine?.current?.step) {
            paceBar(at: date)
        } else {
            zoneBar
        }
    }

    /// The pace against the step's pace target (WATCH-135): the target bright in the middle, a triangle at the
    /// pace, the ends of the target written under it. A line saying so while the step has no pace target.
    @ViewBuilder
    private func paceBar(at date: Date) -> some View {
        if let step = source.stepEngine?.current?.step, let target = StepPaceTarget(step: step) {
            let pace = source.currentSecondsPerMeter(at: date)
            let labels = target.labels()
            let status = pace.map { target.position(forSecondsPerMeter: $0) }
            VStack(spacing: 2) {
                PaceTargetBar(
                    target: target.targetFractions, position: pace.map { target.fraction(forSecondsPerMeter: $0) },
                    tint: StepHeartRateTarget.Status.displayColor(status?.asStatus))
                HStack {
                    if target.hasOneLabel() {
                        Spacer()
                        Text("\(labels.fast) \(PaceText.unit())")
                        Spacer()
                    } else {
                        Text(labels.slow)
                        Spacer()
                        Text(PaceText.unit())
                        Spacer()
                        Text(labels.fast)
                    }
                }
                .font(RunMetricStyle.captionFont).foregroundStyle(.secondary).lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pace target")
            .accessibilityValue(target.spoken() + (status.map { ", " + Self.spokenPace($0) } ?? ", no pace yet"))
        } else if source.stepEngine?.current != nil {
            Text("No pace target in this step")
                .font(RunMetricStyle.captionFont).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        }
    }

    private static func spokenPace(_ position: StepPaceTarget.Position) -> String {
        switch position {
        case .tooSlow: "slower than the target"
        case .tooFast: "faster than the target"
        case .inside: "in the target"
        }
    }

    /// The battery's charge and, in a planned workout, the forecast for the end (WATCH-119).
    private func battery(at date: Date) -> some View {
        let battery = source.battery(at: date)
        let projection = source.stepEngine.flatMap { engine in
            BatteryProjection(
                battery: battery, readings: source.batteryReadings,
                remaining: engine.remaining(progress: source.stepProgress(at: date), secondsPerMeter: source.secondsPerMeter))
        }
        return BatteryRow(battery: battery, projection: projection, inset: Self.batteryInset, bottomInset: 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Battery")
            .accessibilityValue([battery.spokenText.lowercased(), projection?.spoken].compactMap { $0 }.joined(separator: ", "))
    }

    /// The time in each zone so far, a bar for each of zones 0 (below zone 1) to 5.
    private var zoneHistogram: some View {
        ZoneHistogram(fractions: source.zoneTimeFractions)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Time in zones")
            .accessibilityValue(ZoneTimeText.spoken(source.zoneTimeFractions))
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
            if let bpm = source.heartRate { parts.append(target.position(forHeartRate: bpm).text.lowercased()) }
        }
        return parts.joined(separator: ", ")
    }
}

/// The time in each zone as six bars, zone 0 (below zone 1) at the left (WATCH-132).
public struct ZoneHistogram: View {
    /// The share of the time in zones 0 to 5, or `nil` before any was measured.
    let fractions: [Double]?
    private static let height = 52.0

    public var body: some View {
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
