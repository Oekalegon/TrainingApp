import SwiftUI
import TrainingCore
import TrainingWatchKit

/// The target-zone screen of a planned workout (WATCH-118): a ring round the screen's edge with the
/// target zone bright on top and a triangle where the heart rate is, the heart rate's place in the
/// zones and in bpm, the step's countdown, a card with the step and the next one, and the total
/// time. When the target zone changes, the ring turns.
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
        // A step with no heart-rate target has no zone for the top: the ring then centres on the
        // zone the heart rate is in, and no sector is bright.
        let topZone = target?.zone ?? position.map { min(max(Int($0), 1), 5) } ?? 2
        let accent = Color.zone(topZone)
        ZStack {
            GeometryReader { proxy in
                ZoneDialRing(
                    target: Double(topZone), position: position ?? Double(topZone) + 0.5,
                    showsMarker: position != nil, highlightsTarget: target != nil,
                    lineWidth: 9, cornerRadius: min(proxy.size.width, proxy.size.height) * 0.26)
                    .animation(.easeInOut(duration: 0.6), value: topZone)
                    .animation(.easeOut(duration: 0.8), value: position)
            }
            .ignoresSafeArea()
            content(accent: accent, position: position)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate zone dial")
        .accessibilityValue(spoken(target: target, position: position))
    }

    private func content(accent: Color, position: Double?) -> some View {
        let progress = recorder.stepProgress(at: at)
        let hrColor = position.map { Color.zone(Int($0)) } ?? .secondary
        return VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(position.map(ZoneDialText.positionText) ?? "Z --")
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(hrColor)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(recorder.heartRate.map { "\(Int($0.rounded()))" } ?? "--")
                        .font(.system(size: 20, weight: .semibold).monospacedDigit())
                        .foregroundStyle(hrColor)
                    Text("BPM").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            Text(progress.flatMap { WatchWorkoutSummary.remainingValue($0) } ?? "Open")
                .font(.system(size: 36, weight: .semibold).monospacedDigit())
                .foregroundStyle(.yellow)
                .lineLimit(1).minimumScaleFactor(0.6)
            card(accent: accent)
            Text(Duration.seconds(recorder.elapsed(at: at)), format: .time(pattern: .hourMinuteSecond))
                .font(.system(size: 28, weight: .semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 16)
    }

    /// The step's place, the step and the next one, on a tint of the target zone's colour.
    private func card(accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(ZoneDialText.placeLine(current, of: engine.steps.count))
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(accent)
            Text(ZoneDialText.stepLine(current.step)).font(.system(size: 11, weight: .semibold))
            if let next = ZoneDialText.nextLine(engine) {
                Text(next).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(accent.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
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
        if let target { parts.append("target \(target.label)") }
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

private extension Color {
    /// A zone's colour: the shared zone ramp, and grey below zone 1.
    static func zone(_ zone: Int) -> Color {
        HeartRateZone(rawValue: zone)?.zoneColor ?? .gray
    }
}
