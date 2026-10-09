import Foundation
import TrainingCore

/// One step as the step cards show it (MVP2-143), after how the Fitness app lists a structured
/// workout: a role, what ends the step, and the intensity it aims for.
///
/// Built from resolved values (``WorkoutBlockCard/cards(for:)``), so the template detail, the editor and
/// later the planned-workout views (MVP2-144) all say a step the same way.
public struct WorkoutStepCard: Identifiable, Equatable, Sendable {
    /// The step's position among all of the workout's steps.
    public let id: Int
    /// The role the step plays.
    public let kind: StepKind
    /// The role's name, e.g. "Warm-up".
    public let title: String
    /// What ends the step, e.g. "5:00", "400 m" or "Open".
    public let detail: String
    /// The intensity the step aims for, e.g. "HR Zone 2"; `nil` without a target.
    public let target: String?
}

/// Steps that repeat together, as one card in the step list. A block that runs once shows its steps as
/// separate cards; one that repeats is a "Repeat N" card holding them.
public struct WorkoutBlockCard: Identifiable, Equatable, Sendable {
    /// The block's position in the workout.
    public let id: Int
    /// How many times the steps repeat.
    public let repetitions: Int
    /// The steps of one repetition.
    public let steps: [WorkoutStepCard]

    /// Whether the block is drawn as a "Repeat" card: it repeats, or holds several steps that belong
    /// together. A single step run once is a plain step card.
    public var isGroup: Bool { repetitions > 1 || steps.count > 1 }

    /// The cards for `blocks`, numbering steps across the whole workout.
    ///
    /// - Parameter blocks: A workout's blocks, e.g. from ``WorkoutTemplate/instantiate(name:values:)``.
    public static func cards(for blocks: [WorkoutBlock]) -> [WorkoutBlockCard] {
        var stepNumber = 0
        return blocks.enumerated().map { index, block in
            let steps = block.steps.map { step in
                defer { stepNumber += 1 }
                return WorkoutStepCard(
                    id: stepNumber, kind: step.kind, title: step.kind.displayName,
                    detail: goalText(step.goal), target: step.target.map(targetText)
                )
            }
            return WorkoutBlockCard(id: index, repetitions: block.repetitions, steps: steps)
        }
    }

    /// What ends a step, as the cards write it.
    static func goalText(_ goal: StepGoal) -> String {
        switch goal {
        case .time(let seconds):
            Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
        case .distance(let meters):
            Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated))
        case .open:
            "Open"
        }
    }

    /// The intensity a step aims for, as the cards write it.
    static func targetText(_ target: IntensityTarget) -> String {
        switch target {
        case .heartRateZone(let zone): "HR Zone \(zone)"
        case .heartRateRange(let low, let high): "\(Int(low))–\(Int(high)) bpm"
        case .pace: "Pace target"
        case .power(let range): "\(Int(range.lowerBound))–\(Int(range.upperBound)) W"
        case .rpe(let value): "RPE \(value)"
        }
    }
}

extension StepKind {
    /// The role's name; "Warm-up" and "Cool-down" as elsewhere in the app.
    var displayName: String {
        switch self {
        case .warmup: "Warm-up"
        case .work: "Work"
        case .recovery: "Recovery"
        case .cooldown: "Cool-down"
        }
    }
}
