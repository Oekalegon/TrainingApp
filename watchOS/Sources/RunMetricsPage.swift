import SwiftUI
import TrainingCore
import TrainingWatchKit

/// The metrics page of a run (WATCH-105). In a planned workout it is built around the step: its
/// place and name, what is left of it as the big number, a bar for how far through it the run is,
/// its heart-rate target with a gauge of where the heart rate is against it, and the heart rate
/// itself. Total time, distance and what comes next sit small at the bottom. A free run, or the
/// time after the last step, has the total time as the big number and the zone the heart rate is in.
///
/// Units follow the system's region for now; the athlete's own setting comes later (WATCH-115).
struct RunMetricsPage: View {
    let recorder: RunRecorder
    let zoneStore: WatchZoneStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = context.date
            if let engine = recorder.stepEngine, let current = engine.current {
                StepMetrics(
                    recorder: recorder, bands: zoneStore.bands, engine: engine, current: current, at: date)
            } else {
                FreeRunMetrics(recorder: recorder, zoneStore: zoneStore, at: date)
            }
        }
    }
}

/// A distance for the run screen, in the system's road units.
private func runDistanceText(_ meters: Double) -> String {
    Measurement(value: meters, unit: UnitLength.meters)
        .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(2))))
}

/// A time as VoiceOver should say it ("1 hour, 2 minutes, 5 seconds"), so a label can name the
/// value without replacing it.
private func spokenDuration(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds.rounded(.down)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
}

/// The page while a step of a planned workout is running.
private struct StepMetrics: View {
    let recorder: RunRecorder
    let bands: ZoneBands?
    let engine: WorkoutStepEngine
    let current: PlannedStep
    let at: Date

    var body: some View {
        let progress = recorder.stepProgress(at: at)
        let target = StepHeartRateTarget(step: current.step, bands: bands)
        VStack(spacing: 3) {
            Text("\(current.index + 1)/\(engine.steps.count)  \(WatchWorkoutSummary.stepText(current.step))")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            remaining(progress)
            if let fraction = progress?.fraction {
                ProgressView(value: fraction).tint(.blue).accessibilityHidden(true)
            }
            if let target {
                TargetGauge(target: target, heartRate: recorder.heartRate)
            } else {
                // A pace, power or RPE step, or no zones yet: the zone the heart rate is in, as in a free run.
                ZoneBadge(bands: bands, hasZones: bands != nil, heartRate: recorder.heartRate)
            }
            footer
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(stepAccessibilityLabel(progress: progress))
    }

    @ViewBuilder
    private func remaining(_ progress: StepProgress?) -> some View {
        if let progress, let value = WatchWorkoutSummary.remainingValue(progress) {
            Text(value)
                .font(.system(size: 38, weight: .semibold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityLabel(progress.remainingTime != nil ? "Time left" : "Distance left")
                .accessibilityValue(remainingSpoken(progress))
        } else {
            Text("Open").font(.system(size: 30, weight: .semibold))
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(Duration.seconds(recorder.elapsed(at: at)), format: .time(pattern: .hourMinuteSecond))
                    .accessibilityLabel("Total time")
                    .accessibilityValue(spokenDuration(recorder.elapsed(at: at)))
                Text(distanceText)
                    .accessibilityLabel("Distance")
                    .accessibilityValue(distanceText)
            }
            .font(.system(size: 13).monospacedDigit())
            if recorder.phase == .paused {
                Text("Paused").font(.system(size: 12)).foregroundStyle(.yellow)
            } else if let next = WatchWorkoutSummary.nextText(engine) {
                Text(next).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private var distanceText: String { runDistanceText(recorder.distanceMeters) }

    /// What is left of the step, spelled out for VoiceOver: "1 minute, 23 seconds" or "0.4 km".
    private func remainingSpoken(_ progress: StepProgress) -> String {
        if let seconds = progress.remainingTime {
            return Duration.seconds(seconds.rounded(.up)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
        }
        return WatchWorkoutSummary.remainingValue(progress) ?? ""
    }

    /// "Step 3 of 6, recovery 20 s Z2": the step's place and goal, spelled out. What is left of it
    /// is its own element, so this label doesn't go stale as the clock runs.
    private func stepAccessibilityLabel(progress: StepProgress?) -> String {
        var parts = ["Step \(current.index + 1) of \(engine.steps.count)", WatchWorkoutSummary.stepText(current.step)]
        if progress == nil || WatchWorkoutSummary.remainingValue(progress!) == nil {
            parts.append("Press Next step to move on")
        }
        return parts.joined(separator: ", ")
    }
}

/// The step's heart-rate target with the current heart rate against it: the target's name and bpm
/// range, a gauge with the target band and a marker for the heart rate, and the heart rate in a
/// colour for below (blue), in (green) or above (red) the target. The words ("8 bpm below") say it
/// too, so the colour isn't the only signal.
private struct TargetGauge: View {
    let target: StepHeartRateTarget
    let heartRate: Double?

    var body: some View {
        let position = heartRate.map { target.position(forHeartRate: $0) }
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Text(target.label).font(.system(size: 13, weight: .semibold))
                Text("\(Int(target.bpm.lowerBound.rounded()))-\(Int(target.bpm.upperBound.rounded()))")
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
            }
            gauge
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(heartRate.map { "\(Int($0.rounded()))" } ?? "--")
                    .font(.system(size: 30, weight: .semibold).monospacedDigit())
                    .foregroundStyle(position.map(Self.color) ?? .secondary)
                Text(position?.text ?? "no reading").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate target \(target.label), \(Int(target.bpm.lowerBound.rounded())) to \(Int(target.bpm.upperBound.rounded())) beats per minute")
        .accessibilityValue(heartRate.map { "\(Int($0.rounded())) beats per minute, \(position?.text ?? "")" } ?? "no reading")
    }

    private var gauge: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.gray.opacity(0.35))
                Capsule().fill(.green.opacity(0.7))
                    .frame(width: width / 2).offset(x: width / 4)
                if let heartRate {
                    Circle().fill(.white).frame(width: 10, height: 10)
                        .offset(x: target.gaugePosition(forHeartRate: heartRate) * (width - 10))
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private static func color(_ position: StepHeartRateTarget.Position) -> Color {
        switch position {
        case .below: .blue
        case .inside: .green
        case .above: .red
        }
    }
}

/// The page with no step to follow: a free run, or what is left after the last step.
private struct FreeRunMetrics: View {
    let recorder: RunRecorder
    let zoneStore: WatchZoneStore
    let at: Date

    private var distanceText: String { runDistanceText(recorder.distanceMeters) }

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 2) {
                Text(Duration.seconds(recorder.elapsed(at: at)), format: .time(pattern: .hourMinuteSecond))
                    .font(.title2.monospacedDigit())
                    .accessibilityLabel("Elapsed time")
                    .accessibilityValue(spokenDuration(recorder.elapsed(at: at)))
                if recorder.stepEngine?.isFinished == true {
                    Text("Workout done").font(.system(size: 12)).foregroundStyle(.green)
                }
            }
            ZoneBadge(bands: zoneStore.bands, hasZones: zoneStore.zones != nil, heartRate: recorder.heartRate)
            Text(recorder.heartRate.map { "\(Int($0.rounded())) bpm" } ?? "-- bpm")
                .font(.title.monospacedDigit())
                .accessibilityLabel("Heart rate")
                .accessibilityValue(recorder.heartRate.map { "\(Int($0.rounded())) beats per minute" } ?? "no reading")
            Text(distanceText)
                .font(.footnote.monospacedDigit())
                .accessibilityLabel("Distance")
                .accessibilityValue(distanceText)
            if recorder.phase == .paused {
                Text("Paused").font(.footnote).foregroundStyle(.yellow)
            }
        }
    }
}

/// The zone the current heart rate is in, from the athlete's zones sent by the iPhone (WATCH-102):
/// a coloured "Z3" with its bpm range. Says so when no zones have arrived yet, so a run without
/// them isn't mistaken for one in no zone, and when they can't be worked out.
struct ZoneBadge: View {
    let bands: ZoneBands?
    let hasZones: Bool
    let heartRate: Double?

    var body: some View {
        if let bands {
            content(bands: bands)
        } else {
            Text(hasZones ? "Zones not set up: check TrainingApp" : "No zones yet: open TrainingApp on your iPhone")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func content(bands: ZoneBands) -> some View {
        let zone = heartRate.map { bands.zone(forHeartRate: $0) }
        let named = zone.flatMap { HeartRateZone(rawValue: $0) }
        let range = zone.flatMap { bands.range(of: $0) }
        VStack(spacing: 0) {
            Text(label(zone: zone))
                .font(.headline)
                .foregroundStyle(named?.zoneColor ?? .secondary)
            if let range {
                Text("\(Int(range.lowerBound.rounded()))-\(Int(range.upperBound.rounded()))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(zone: zone, range: range))
    }

    private func label(zone: Int?) -> String {
        switch zone {
        case nil: "Z-"
        case 0: "<Z1"
        case let zone?: "Z\(zone)"
        }
    }

    private func accessibilityLabel(zone: Int?, range: ClosedRange<Double>?) -> String {
        guard let zone else { return "No zone" }
        guard zone > 0 else { return "Below zone 1" }
        guard let range else { return "Zone \(zone)" }
        return "Zone \(zone), \(Int(range.lowerBound.rounded())) to \(Int(range.upperBound.rounded())) beats per minute"
    }
}
