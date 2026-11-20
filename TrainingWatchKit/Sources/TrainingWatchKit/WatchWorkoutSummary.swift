import Foundation
import TrainingCore

/// A workout as short lines of text for the watch's screen (WATCH-103): one line per step, or one
/// per repeated block, such as "Warm-up 10 min Z1" or "4 × (3 min Z4, Recovery 2 min Z2)".
public enum WatchWorkoutSummary {
    /// The lines describing a workout's steps.
    ///
    /// - Parameters:
    ///   - blocks: The workout's blocks.
    ///   - locale: Decides whether distances are in kilometres or miles.
    public static func lines(for blocks: [WorkoutBlock], locale: Locale = .current) -> [String] {
        blocks.flatMap { block -> [String] in
            let steps = block.steps.map { stepText($0, locale: locale) }
            guard block.repetitions > 1 else { return steps }
            return ["\(block.repetitions) × " + (steps.count == 1 ? steps[0] : "(" + steps.joined(separator: ", ") + ")")]
        }
    }

    /// The heart-rate target the watch aims a step at: the step's own when it is heart-rate based,
    /// otherwise its companion's. `nil` for a step with none (pace, power or no target).
    public static func heartRateTarget(of step: WorkoutStep) -> IntensityTarget? {
        [step.target, step.companionTarget].compactMap { $0 }.first { isHeartRate($0) }
    }

    private static func isHeartRate(_ target: IntensityTarget) -> Bool {
        switch target {
        case .heartRateZone, .heartRateZoneRange, .heartRateRange: true
        case .phaseIntensity, .pace, .power, .rpe: false
        }
    }

    static func stepText(_ step: WorkoutStep, locale: Locale) -> String {
        [kindText(step.kind), goalText(step.goal, locale: locale), targetText(of: step)]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private static func kindText(_ kind: StepKind) -> String? {
        switch kind {
        case .warmup: "Warm-up"
        case .work: nil
        case .recovery: "Recovery"
        case .cooldown: "Cool-down"
        }
    }

    static func goalText(_ goal: StepGoal, locale: Locale) -> String {
        switch goal {
        case .time(let seconds): durationText(seconds)
        case .distance(let meters): distanceText(meters, locale: locale)
        case .open: "Open"
        }
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let parts = [(total / 3600, "h"), ((total % 3600) / 60, "min"), (total % 60, "s")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1)" }
        return parts.isEmpty ? "0 s" : parts.joined(separator: " ")
    }

    private static func distanceText(_ meters: Double, locale: Locale) -> String {
        switch locale.measurementSystem {
        case .us, .uk:
            return trimmed(meters / 1609.344) + " mi"
        default:
            return meters < 1000 ? "\(Int(meters.rounded())) m" : trimmed(meters / 1000) + " km"
        }
    }

    /// `1.5`, `2` or `0.25`: two decimals at most, without trailing zeros.
    private static func trimmed(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    private static func targetText(of step: WorkoutStep) -> String? {
        if let target = heartRateTarget(of: step) {
            switch target {
            case .heartRateZone(let zone):
                return "Z\(zone)"
            case .heartRateZoneRange(let positions):
                // A whole zone, such as 3.0 to 4.0, reads as "Z3".
                let zone = positions.lowerBound.rounded(.down)
                if positions.lowerBound == zone, positions.upperBound == zone + 1 { return "Z\(Int(zone))" }
                return String(format: "Z%.1f-%.1f", positions.lowerBound, positions.upperBound)
            case .heartRateRange(let low, let high):
                return "\(Int(low.rounded()))-\(Int(high.rounded())) bpm"
            default:
                return nil
            }
        }
        if case .rpe(let rpe) = step.target { return "RPE \(rpe)" }
        return nil
    }
}
