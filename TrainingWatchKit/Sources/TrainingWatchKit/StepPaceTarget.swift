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

    /// Whether the target is one pace (a race-pace step the plan resolved to a single value), so its two ends read alike.
    public func hasOneLabel(locale: Locale = .current) -> Bool {
        let (fast, slow) = labels(locale: locale)
        return fast == slow
    }

    /// The pace written as a range for VoiceOver and the editor, such as "5:00 to 5:30 per kilometre", or "5:00 per
    /// kilometre" for one pace.
    public func spoken(locale: Locale = .current) -> String {
        let (fast, slow) = labels(locale: locale)
        let unit = PaceText.usesKilometres(locale) ? "kilometre" : "mile"
        return fast == slow ? "\(fast) per \(unit)" : "\(fast) to \(slow) per \(unit)"
    }

    /// The target as drawn and judged: at least 3 % of the pace wide, so a single pace, or a very narrow range, has a
    /// band to run in. The labels keep the target's own ends.
    private var band: (fast: Double, slow: Double) {
        let middle = (fastest + slowest) / 2
        let half = max((slowest - fastest) / 2, middle * Self.minimumHalfWidth)
        return (middle - half, middle + half)
    }

    /// Half the narrowest band, as a share of the pace.
    private static let minimumHalfWidth = 0.03

    /// The part of the bar's scale beside the band: the band's width again on each side.
    private var margin: Double { band.slow - band.fast }

    /// Where `secondsPerMeter` is on the bar, 0 (the slow end, at the left) to 1 (the fast end, at the right),
    /// clamped; the band is the middle part.
    public func fraction(forSecondsPerMeter pace: Double) -> Double {
        let slowEnd = band.slow + margin, fastEnd = band.fast - margin
        return min(max((slowEnd - pace) / (slowEnd - fastEnd), 0), 1)
    }

    /// The band's stretch of the bar, as fractions.
    public var targetFractions: ClosedRange<Double> {
        fraction(forSecondsPerMeter: band.slow)...fraction(forSecondsPerMeter: band.fast)
    }

    public func position(forSecondsPerMeter pace: Double) -> Position {
        if pace > band.slow { .tooSlow } else if pace < band.fast { .tooFast } else { .inside }
    }
}
