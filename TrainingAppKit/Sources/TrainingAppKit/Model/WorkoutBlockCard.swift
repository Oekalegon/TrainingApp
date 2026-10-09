import Foundation
import TrainingCore

/// One step as the step cards show it (MVP2-143), after how the Fitness app lists a structured
/// workout: a role, what ends the step, and the intensity it aims for.
///
/// Built from resolved values (``WorkoutBlockCard/cards(for:)``), so the template detail, the editor and
/// later the planned-workout views (MVP2-144) all say a step the same way.
public struct WorkoutStepCard: Identifiable, Equatable, Sendable {
    /// What ends a step.
    public enum End: Equatable, Sendable {
        /// A duration.
        case time
        /// A distance.
        case distance
        /// The athlete ends it.
        case open
    }

    /// The step's position among all of the workout's steps.
    public let id: Int
    /// The role the step plays.
    public let kind: StepKind
    /// The role's name, e.g. "Warm-up".
    public let title: String
    /// What ends the step, e.g. "5:00", "400 m" or "Open".
    public let detail: String
    /// The kind of end ``detail`` describes; it decides the icon's colour.
    public let end: End
    /// The intensity the step aims for, e.g. "HR Zone 2"; `nil` without a target.
    public let target: String?
    /// The SF Symbol shown before ``target``: a heart for heart rate, a shoe for pace; `nil` without a
    /// target.
    public let targetSymbol: String?
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
                    detail: goalText(step.goal), end: end(of: step.goal),
                    target: step.target.map(targetText), targetSymbol: step.target.map(targetSymbol)
                )
            }
            return WorkoutBlockCard(id: index, repetitions: block.repetitions, steps: steps)
        }
    }

    /// The kind of end a goal is.
    static func end(of goal: StepGoal) -> WorkoutStepCard.End {
        switch goal {
        case .time: .time
        case .distance: .distance
        case .open: .open
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

    /// The symbol before a target: a heart for heart rate, a shoe for pace, a lightning bolt for
    /// perceived effort and a horizontal bolt for power.
    static func targetSymbol(_ target: IntensityTarget) -> String {
        switch target {
        case .heartRateZone, .heartRateRange: "heart.fill"
        case .pace: paceSymbol
        case .power: "bolt.horizontal.fill"
        case .rpe: "bolt.fill"
        }
    }

    /// The running shoe with its shadow, a symbol new in the 2026 set (iOS 27); `shoe.fill` before that,
    /// where the newer name would draw nothing.
    static var paceSymbol: String {
        if #available(iOS 27, macOS 27, *) { "shoe.running.and.shadow.fill" } else { "shoe.fill" }
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
