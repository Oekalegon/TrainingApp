import Foundation
import TrainingCore

/// Drives the activity detail screen (design doc §2.2): a completed activity's stats, computed
/// once via `StatisticsCalculator` rather than re-derived by hand — sport, distance, duration,
/// average heart rate, time-in-zone breakdown, and load/TRIMP all come straight from
/// `ActivitySummary`.
///
/// Immutable after creation — there's nothing here that changes over the screen's lifetime, so
/// this is a plain struct rather than an `@Observable` class.
public struct ActivityDetailViewModel {
    public let activity: Activity
    public let summary: ActivitySummary
    /// The athlete's timezone — the view formats every date with this, not the device's default.
    public let timeZone: TimeZone
    /// This activity's overlap issue, if any (MVP1-63) — see `WeekViewModel.overlapContext(for:)`.
    /// The detail screen shows an "Overlap" section with resolution actions when non-`nil`.
    public let overlapContext: OverlapContext?

    /// Creates a detail view model for `activity`.
    ///
    /// - Parameters:
    ///   - activity: The completed activity to summarize.
    ///   - athlete: Supplies the heart-rate zone settings effective on `activity.start`.
    ///   - overlapContext: This activity's overlap issue, if any (MVP1-63).
    ///   - calculator: Computes the summary; defaults to `StatisticsCalculator()`'s standard
    ///     calculators (the same ones `TrainingModel` uses for the fitness series), so the load
    ///     shown here always agrees with what fed the week view's chart.
    public init(
        activity: Activity,
        athlete: AthleteProfile,
        overlapContext: OverlapContext? = nil,
        calculator: StatisticsCalculator = StatisticsCalculator()
    ) {
        self.activity = activity
        self.summary = calculator.summary(for: activity, athlete: athlete)
        self.timeZone = athlete.timeZone
        self.overlapContext = overlapContext
    }
}
