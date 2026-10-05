import Foundation
import TrainingCore

extension WorkoutTemplateParameter {
    /// `value` written in this parameter's unit, e.g. "30:00", "400 m" or "8" — shared by the
    /// planned-workout sheet's sliders and the Library tab's template detail (MVP2-21).
    /// A `.minutes` parameter's value is in seconds, as the templates store it.
    func formatted(_ value: Double) -> String {
        switch unit {
        case .minutes:
            Duration.seconds(value).formatted(.time(pattern: .minuteSecond))
        case .meters:
            Measurement(value: value, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated))
        case .count:
            value.formatted(.number.precision(.fractionLength(0)))
        }
    }
}
