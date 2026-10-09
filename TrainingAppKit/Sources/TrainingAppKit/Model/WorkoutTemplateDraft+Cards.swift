import Foundation
import TrainingCore

extension WorkoutTemplateDraft {
    /// The editor's step card for `step`: what the card list shows, with a value that comes from a
    /// parameter written as the parameter's name and its starting value, e.g. "Effort · 1:00".
    ///
    /// - Parameter number: The step's position among all steps, used as the card's id.
    public func card(for step: Step, number: Int) -> WorkoutStepCard {
        let detail: String
        switch step.goal {
        case .time(let source): detail = text(source, unit: .minutes)
        case .distance(let source): detail = text(source, unit: .meters)
        case .open: detail = "Open"
        }
        let target: String? = switch step.target {
        case .none: nil
        case .zone(let zone): WorkoutBlockCard.targetText(.heartRateZone(zone))
        case .preserved(let target): WorkoutBlockCard.targetText(target)
        }
        return WorkoutStepCard(id: number, kind: step.kind, title: step.kind.displayName, detail: detail, target: target)
    }

    /// How a block's repeat count reads in its "Repeat" header, e.g. "5" or "Repeats · 8".
    public func repetitionsText(_ block: Block) -> String {
        text(block.repetitions, unit: .count)
    }

    private func text(_ source: Source, unit: ParameterUnit) -> String {
        switch source {
        case .fixed(let value):
            Self.valueText(value, unit: unit)
        case .parameter(let id):
            parameters.first { $0.id == id }.map { "\($0.name) · \(Self.valueText($0.defaultValue, unit: unit))" } ?? "?"
        }
    }

    /// `value`, in the editor's unit, written as a card does: "10:00", "400 m" or "5".
    static func valueText(_ value: Double, unit: ParameterUnit) -> String {
        switch unit {
        case .minutes: WorkoutBlockCard.goalText(.time(value * 60))
        case .meters: WorkoutBlockCard.goalText(.distance(value))
        case .count: value.formatted(.number.precision(.fractionLength(0)))
        }
    }
}
