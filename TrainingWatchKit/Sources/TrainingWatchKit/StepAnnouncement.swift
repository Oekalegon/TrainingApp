import Foundation
import TrainingCore

/// The words said in earbuds when a step starts (WATCH-107), such as "Interval 3 of 6, 4 minutes,
/// zone 4". Spelled out for the speech synthesiser, not abbreviated like the screen's lines.
public enum StepAnnouncement {
    /// - Parameters:
    ///   - step: The step that began.
    ///   - locale: Decides whether distances are in kilometres or miles.
    public static func text(for step: PlannedStep, locale: Locale = .current) -> String {
        let name: String
        switch step.step.kind {
        case .warmup: name = "Warm-up"
        case .recovery: name = "Recovery"
        case .cooldown: name = "Cool-down"
        case .work: name = step.repetitions > 1 ? "Interval \(step.repetition) of \(step.repetitions)" : "Run"
        }
        return [name, goal(step.step.goal, locale: locale), target(of: step.step)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    static func goal(_ goal: StepGoal, locale: Locale) -> String? {
        switch goal {
        case .open: return "open"
        case .time(let seconds):
            let total = Int(seconds.rounded())
            let parts = [(total / 3600, "hour"), ((total % 3600) / 60, "minute"), (total % 60, "second")]
                .filter { $0.0 > 0 }
                .map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        case .distance(let meters):
            switch locale.measurementSystem {
            case .us, .uk: return amount(meters / 1609.344, "mile")
            default: return meters < 1000 ? amount(meters, "metre") : amount(meters / 1000, "kilometre")
            }
        }
    }

    private static func amount(_ value: Double, _ unit: String) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return "\(text) \(unit)\(text == "1" ? "" : "s")"
    }

    private static func target(of step: WorkoutStep) -> String? {
        switch WatchWorkoutSummary.heartRateTarget(of: step) {
        case .heartRateZone(let zone): "zone \(zone)"
        case .heartRateZoneRange(let positions):
            "zone \(number(positions.lowerBound)) to \(number(positions.upperBound))"
        case .heartRateRange(let low, let high):
            "\(Int(low.rounded())) to \(Int(high.rounded())) beats per minute"
        default: nil
        }
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
