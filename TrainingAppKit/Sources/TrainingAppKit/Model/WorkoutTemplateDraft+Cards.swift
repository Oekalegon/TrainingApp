import Foundation
import TrainingCore

extension WorkoutTemplateDraft {
    /// The editor's step card for `step`: what the card list shows, with a value that comes from a
    /// parameter written as the parameter's name and its starting value, e.g. "Effort · 1:00".
    ///
    /// - Parameters:
    ///   - number: The step's position among all steps, used as the card's id.
    ///   - distanceSystem: How distances are written.
    public func card(for step: Step, number: Int, distanceSystem: DistanceSystem = .deviceDefault) -> WorkoutStepCard {
        let detail: String
        let end: WorkoutStepCard.End
        switch step.goal {
        case .time(let source): (detail, end) = (text(source, unit: .minutes, distanceSystem), .time)
        case .distance(let source): (detail, end) = (text(source, unit: .meters, distanceSystem), .distance)
        case .open: (detail, end) = ("Open", .open)
        }
        let target: String? = switch step.target {
        case .none: nil
        case .zone(let zone): WorkoutBlockCard.targetText(.heartRateZone(zone))
        case .preserved(let target): WorkoutBlockCard.targetText(target)
        }
        let targetSymbol: String? = switch step.target {
        case .none: nil
        case .zone: WorkoutBlockCard.targetSymbol(.heartRateZone(1))
        case .preserved(let target): WorkoutBlockCard.targetSymbol(target)
        }
        var card = WorkoutStepCard(
            id: number, kind: step.kind, title: step.kind.displayName, detail: detail, end: end,
            target: target, targetSymbol: targetSymbol
        )
        switch step.goal {
        case .time(let source), .distance(let source): card.parameterName = parameterName(source)
        case .open: break
        }
        return card
    }

    /// The name of the parameter `source` points at, if it does.
    func parameterName(_ source: Source) -> String? {
        guard case .parameter(let id) = source else { return nil }
        return parameters.first { $0.id == id }?.name
    }

    /// How a block's repeat count reads in its "Repeat" header, e.g. "5" or "Repeats · 8".
    public func repetitionsText(_ block: Block) -> String {
        text(block.repetitions, unit: .count, .deviceDefault)
    }

    private func text(_ source: Source, unit: ParameterUnit, _ distanceSystem: DistanceSystem) -> String {
        switch source {
        case .fixed(let value):
            Self.valueText(value, unit: unit, distanceSystem: distanceSystem)
        case .parameter(let id):
            parameters.first { $0.id == id }.map { "\($0.name) · \(Self.valueText($0.defaultValue, unit: unit, distanceSystem: distanceSystem))" } ?? "?"
        }
    }

    /// `value`, in the editor's unit, written as a card does: "10:00", "400 m" or "5".
    static func valueText(_ value: Double, unit: ParameterUnit, distanceSystem: DistanceSystem = .deviceDefault) -> String {
        switch unit {
        case .minutes: WorkoutBlockCard.goalText(.time(value * 60))
        case .meters: WorkoutBlockCard.goalText(.distance(value), distanceSystem: distanceSystem)
        case .count: value.formatted(.number.precision(.fractionLength(0)))
        }
    }
}
