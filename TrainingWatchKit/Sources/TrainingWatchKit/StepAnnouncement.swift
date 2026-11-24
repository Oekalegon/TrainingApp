import Foundation
import TrainingCore

/// The words said in earbuds when a step starts (WATCH-107), such as "Interval 3 of 6, 4 minutes,
/// zone 4". Spelled out for the speech synthesiser, not abbreviated like the screen's lines.
public enum StepAnnouncement {
    /// - Parameters:
    ///   - step: The step that began.
    ///   - locale: Decides whether distances are in kilometres or miles.
    ///   - ahead: Whether it is said before the step starts, as "Next: work for 4 minutes, zone 4".
    public static func text(for step: PlannedStep, locale: Locale = .current, ahead: Bool = false) -> String {
        let name: String
        switch step.step.kind {
        case .warmup: name = "Warm-up"
        case .recovery: name = "Recovery"
        case .cooldown: name = "Cool-down"
        case .work: name = step.repetitions > 1 ? "Interval \(step.repetition) of \(step.repetitions)" : "Run"
        }
        let text = [name, goal(step.step.goal, locale: locale), target(of: step.step)]
            .compactMap { $0 }
            .joined(separator: ", ")
        return ahead ? aheadText(for: step, locale: locale) : text
    }

    /// "Next: work for 4 minutes, zone 4": what is said before a work step starts.
    private static func aheadText(for step: PlannedStep, locale: Locale) -> String {
        let goal = goal(step.step.goal, locale: locale)
        let what = switch step.step.goal {
        case .open: "work, open"
        default: goal.map { "work for \($0)" } ?? "work"
        }
        return (["Next: " + what] + [target(of: step.step)].compactMap { $0 }).joined(separator: ", ")
    }

    /// Whether `next` is to be announced now, ahead of its start: a work step, with the setting on,
    /// when the step before it has a time goal with no more than the lead time left. A step
    /// after an open step or one with a distance goal can't be foreseen, so it is announced as it
    /// starts, like every other kind of step (recovery, warm-up and cool-down).
    ///
    /// - Parameters:
    ///   - next: The step after the current one.
    ///   - progress: How far into the current step the run is.
    ///   - settings: The athlete's choices.
    public static func announcesAhead(next: PlannedStep?, progress: StepProgress?, settings: CueSettings) -> Bool {
        guard settings.announceWorkAhead, let next, next.step.kind == .work,
              let remaining = progress?.remainingTime else { return false }
        return remaining <= Double(settings.aheadSeconds)
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
