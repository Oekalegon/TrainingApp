import Foundation
import TrainingCore

/// The words of the zone dial (WATCH-118): the heart rate's position as "2.3" and the step lines
/// VoiceOver reads.
public enum ZoneDialText {
    /// The heart rate's place along the zones, such as "Z 2.3" (the screens set the "ZONE" apart and use ``positionValue(_:)``; VoiceOver reads this): one decimal, rounded down so it
    /// never shows a zone before the heart rate has reached it, and "Z <1" below zone 1.
    ///
    /// - Parameter position: ``ZoneBands/position(forHeartRate:)``.
    public static func positionText(_ position: Double) -> String {
        "Z " + positionValue(position)
    }

    /// Just the value of ``positionText(_:)``, "2.3" or "<1", for a screen that sets the "Z" apart.
    ///
    /// - Parameter position: ``ZoneBands/position(forHeartRate:)``.
    public static func positionValue(_ position: Double) -> String {
        guard position >= 1 else { return "<1" }
        return String(format: "%.1f", min((position * 10).rounded(.down) / 10, 5.9))
    }

    /// A step as one line for the card, such as "WORK 1:30 in Zone 2": the kind, the goal and the
    /// heart-rate target. A step with no heart-rate target says nothing about one.
    ///
    /// - Parameters:
    ///   - step: The step.
    ///   - locale: Decides whether distances are in kilometres or miles.
    public static func stepLine(_ step: WorkoutStep, locale: Locale = .current) -> String {
        let goal: String
        switch step.goal {
        case .time(let seconds): goal = clock(seconds)
        case .distance, .open: goal = WatchWorkoutSummary.goalText(step.goal, locale: locale)
        }
        var line = "\(kindText(step.kind)) \(goal)"
        if let target = heartRateTargetText(step) { line += " \(target)" }
        return line
    }

    /// Where a step is, for the dial: the interval of a repeated block ("REP 5/12") or, outside a
    /// repeat, the step's place among all the steps ("2/6"), so every step has a number.
    public enum Place: Equatable, Sendable {
        /// The `number`th pass of a block repeated `count` times.
        case interval(_ number: Int, of: Int)
        /// The `number`th of `count` steps, for a step that isn't in a repeat.
        case step(_ number: Int, of: Int)

        /// "5/12" or "2/6".
        public var text: String {
            switch self {
            case .interval(let number, let count), .step(let number, let count): "\(number)/\(count)"
            }
        }

        /// Whether it is an interval of a repeat, which the dial marks with "REP".
        public var isRepeat: Bool {
            if case .interval = self { true } else { false }
        }
    }

    /// Where `step` is, for the dial.
    ///
    /// - Parameters:
    ///   - step: The step.
    ///   - count: How many steps the workout has.
    public static func place(of step: PlannedStep, in count: Int) -> Place {
        step.repetitions > 1 ? .interval(step.repetition, of: step.repetitions) : .step(step.index + 1, of: count)
    }

    /// The line above the step: "INTERVAL 5 of 12" for a repeated block, otherwise "STEP 2 of 6".
    public static func placeLine(_ step: PlannedStep, of count: Int) -> String {
        step.repetitions > 1
            ? "INTERVAL \(step.repetition) of \(step.repetitions)"
            : "STEP \(step.index + 1) of \(count)"
    }

    private static func kindText(_ kind: StepKind) -> String {
        switch kind {
        case .warmup: "WARM-UP"
        case .work: "WORK"
        case .recovery: "RECOVER"
        case .cooldown: "COOL-DOWN"
        }
    }

    /// "in Zone 2", "in Zone 4.0-4.5" or "at 150-160 bpm"; `nil` without a heart-rate target.
    private static func heartRateTargetText(_ step: WorkoutStep) -> String? {
        switch WatchWorkoutSummary.heartRateTarget(of: step) {
        case .heartRateZone(let zone):
            return "in Zone \(zone)"
        case .heartRateZoneRange(let positions):
            let zone = positions.lowerBound.rounded(.down)
            if positions.lowerBound == zone, positions.upperBound == zone + 1 { return "in Zone \(Int(zone))" }
            return String(format: "in Zone %.1f-%.1f", positions.lowerBound, positions.upperBound)
        case .heartRateRange(let low, let high):
            return "at \(Int(low.rounded()))-\(Int(high.rounded())) bpm"
        default:
            return nil
        }
    }

    /// The total workout time for the dial, with the hours: "0:24:15" or "1:24:15".
    ///
    /// - Parameter seconds: The workout time, paused time left out.
    public static func totalTimeText(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// `1:30` or `1:02:00`.
    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
