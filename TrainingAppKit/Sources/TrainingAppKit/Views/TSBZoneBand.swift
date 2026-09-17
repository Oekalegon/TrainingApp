import SwiftUI
import TrainingCore

/// One `TSBZone`'s background band for a Form/TSB chart — shared by `FitnessChartView` (the main
/// week graph's "Form" page) and `FitnessTrendDetailChartView` (the metrics detail view's own Form
/// chart, MVP1-45), so the boundaries/colors/labels can't drift between the two places TSB gets
/// plotted with zone shading.
struct TSBZoneBand {
    let lowerBound: Double
    let upperBound: Double
    let zone: TSBZone

    var color: Color { zone.color }
    var label: String { zone.label }

    /// The visible y-domain, wide enough to show every zone as a full band (including a sliver of
    /// `injuryRisk`/`detraining`, whose own real boundaries are unbounded) rather than clipping
    /// the outermost ones to a zero-height edge.
    static let domain: ClosedRange<Double> = -45...40

    /// The zone boundary values, in ascending order — also where a Form chart's horizontal
    /// gridlines and leading axis labels sit, instead of an arbitrary evenly-spaced stride.
    static let boundaries: [Double] = [-30, -10, 5, 25]

    /// Mirrors `TSBZone`'s own (internal-to-TrainingKit) boundaries with `PlanGuardrails()`'s
    /// defaults (`minTSBOnRaceDay: 5`, `maxTSBOnRaceDay: 25`) — `AthleteProfile` doesn't carry its
    /// own tuned guardrails yet, so those defaults are the only ones any athlete in this app
    /// actually has.
    static let all: [TSBZoneBand] = [
        TSBZoneBand(lowerBound: domain.lowerBound, upperBound: -30, zone: .injuryRisk),
        TSBZoneBand(lowerBound: -30, upperBound: -10, zone: .training),
        TSBZoneBand(lowerBound: -10, upperBound: 5, zone: .recovery),
        TSBZoneBand(lowerBound: 5, upperBound: 25, zone: .race),
        TSBZoneBand(lowerBound: 25, upperBound: domain.upperBound, zone: .detraining),
    ]
}
