import Foundation
import TrainingCore

/// How a template parameter is tuned on a slider (MVP2-106), shared by the planned-workout sheet and
/// anything else that shows one, so the value always lands on something the athlete would type.
extension WorkoutTemplateParameter {
    /// The slider's bounds: the template's own range, else half to double the default, floored to a
    /// band at least 1 wide so a default of 0 doesn't give a degenerate `0...0` slider.
    var sliderRange: ClosedRange<Double> {
        guard let declaredRange = range else {
            let lower = defaultValue / 2
            let upper = max(defaultValue * 2, lower + 1)
            return lower...upper
        }
        return declaredRange
    }

    /// How far one notch moves the value, so a rest can't land on 94.3 seconds or a repetition count on
    /// 7.6. A `.minutes` parameter holds seconds: short ranges (a sprint, a rest between repetitions)
    /// move by 5 seconds, medium ones by 15 and long ones (an easy run's duration) by a whole minute.
    /// Distances move by 50 m up to a kilometre and by 100 m beyond; counts by one.
    var sliderStep: Double {
        let upper = sliderRange.upperBound
        switch unit {
        case .minutes:
            if upper <= 5 * 60 { return 5 }
            if upper <= 15 * 60 { return 15 }
            return 60
        case .meters:
            return upper <= 1_000 ? 50 : 100
        case .count:
            return 1
        }
    }

    /// `value` moved onto the nearest notch of the slider, counted from the range's lower bound (as
    /// `Slider` does) and kept inside the range.
    ///
    /// - Parameter value: A value, e.g. a stored one from before the slider had steps.
    func snapped(_ value: Double) -> Double {
        let range = sliderRange
        let step = sliderStep
        let notches = ((min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / step).rounded()
        return min(range.lowerBound + notches * step, range.upperBound)
    }
}
