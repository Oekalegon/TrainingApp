import Foundation
import TrainingCore

/// A step's pace target, with the run screen's questions about it (WATCH-135): where a pace sits against it and
/// where to draw it on the pace bar. A heart-rate step that the plan resolved to a pace (the companion target) has
/// one too. The target is in seconds per kilometre in the plan; here it is kept in seconds per metre, like the
/// recorder's paces.
public struct StepPaceTarget: Sendable, Hashable {
    /// The fastest and the slowest pace of the target, in seconds per metre.
    public let fastest: Double
    public let slowest: Double

    /// Where a pace is against the target.
    public enum Position: Sendable, Hashable { case tooSlow, inside, tooFast }

    /// The pace target of `step`: its own, or its companion's, or `nil` with none (or a nonsensical one).
    public init?(step: WorkoutStep) {
        for target in [step.target, step.companionTarget] {
            if case .pace(let range)? = target, range.lowerBound > 0, range.upperBound.isFinite {
                self.init(fastestSecondsPerKilometre: range.lowerBound, slowestSecondsPerKilometre: range.upperBound)
                return
            }
        }
        return nil
    }

    public init(fastestSecondsPerKilometre fast: Double, slowestSecondsPerKilometre slow: Double) {
        fastest = min(fast, slow) / 1000
        slowest = max(fast, slow) / 1000
    }

    /// The label of the ends of the target, for the bar: "5:00" and "5:30".
    public func labels(locale: Locale = .current) -> (fast: String, slow: String) {
        (PaceText.text(secondsPerMeter: fastest, locale: locale), PaceText.text(secondsPerMeter: slowest, locale: locale))
    }

    /// The pace written as a range for VoiceOver and the editor, such as "5:00 to 5:30 per kilometre".
    public func spoken(locale: Locale = .current) -> String {
        let (fast, slow) = labels(locale: locale)
        return "\(fast) to \(slow) per \(PaceText.usesKilometres(locale) ? "kilometre" : "mile")"
    }

    /// The part of the bar's scale the target takes: its width again on each side, at least 5 % of the pace.
    private var margin: Double { max(slowest - fastest, fastest * 0.05) }

    /// Where `secondsPerMeter` is on the bar, 0 (the slow end, at the left) to 1 (the fast end, at the right),
    /// clamped; the target is the middle part.
    public func fraction(forSecondsPerMeter pace: Double) -> Double {
        let slowEnd = slowest + margin, fastEnd = fastest - margin
        return min(max((slowEnd - pace) / (slowEnd - fastEnd), 0), 1)
    }

    /// The target's own stretch of the bar, as fractions.
    public var targetFractions: ClosedRange<Double> {
        fraction(forSecondsPerMeter: slowest)...fraction(forSecondsPerMeter: fastest)
    }

    public func position(forSecondsPerMeter pace: Double) -> Position {
        if pace > slowest { .tooSlow } else if pace < fastest { .tooFast } else { .inside }
    }
}
