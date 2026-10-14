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
    /// 7.6, and so the range's upper end and the default can always be reached.
    ///
    /// A `.minutes` parameter holds seconds: the step is 5 seconds when the range ends within 5 minutes
    /// (a sprint, a rest between repetitions), 15 up to 15 minutes and a whole minute beyond (an easy
    /// run's duration). Distances move by 50 m up to a kilometre and by 100 m beyond; counts by one.
    /// Those are the most the step may be. The athlete's own templates can have any bounds, though
    /// (7.5 to 20 minutes, or 3 to 13 miles in metres), so the step is the coarsest of those, and then
    /// of the finer ones (10 m, 5 s, 1 s, 1 m), that has the upper bound and the default on a notch,
    /// counting from the lower bound as `Slider` does. When none does, the range is divided into as many
    /// of the finest notches as fit, which keeps the upper end on a notch and the default within half
    /// a notch of one.
    var sliderStep: Double {
        let range = sliderRange
        let width = range.upperBound - range.lowerBound
        let candidates: [Double]
        switch unit {
        case .minutes:
            let coarsest: Double = range.upperBound <= 5 * 60 ? 5 : range.upperBound <= 15 * 60 ? 15 : 60
            candidates = [60, 15, 5, 1].filter { $0 <= coarsest }
        case .meters:
            let coarsest: Double = range.upperBound <= 1_000 ? 50 : 100
            candidates = [100, 50, 10, 1].filter { $0 <= coarsest }
        case .count:
            candidates = [1]
        }
        func isOnNotch(_ value: Double, step: Double) -> Bool {
            let notches = (value - range.lowerBound) / step
            return abs(notches - notches.rounded()) < 1e-9
        }
        if let step = candidates.first(where: { isOnNotch(range.upperBound, step: $0) && isOnNotch(defaultValue, step: $0) }) {
            return step
        }
        let finest = candidates.last ?? 1
        let notches = max(1, (width / finest).rounded())
        return width / notches
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
