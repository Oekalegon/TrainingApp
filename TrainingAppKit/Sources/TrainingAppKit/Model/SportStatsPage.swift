import Foundation
import TrainingCore

/// One sport's page in the week view's stats pager — see ``WeekViewModel/sportStatsPages(asOf:)``.
///
/// `distanceMeters`/`time` (and their change fractions) are this sport's own *performed* totals,
/// but `load`/`loadChangeFraction` are always the whole week's *performed* total across every
/// sport, identical on every page: training load (TRIMP) isn't meaningfully attributable to one
/// sport the way distance and time are — it's a systemic measure that feeds one CTL/ATL/TSB series
/// regardless of which sport produced it — so slicing it per sport here would suggest a
/// distinction the underlying model doesn't make. `plannedLoad` follows the same
/// whole-week-not-per-sport convention as `load`.
///
/// Performed and planned are independent figures (MVP2-31), not blended into one running total the
/// way `TrainingModel`'s own CTL/ATL feed does for a still-open week — see
/// `StatisticsCalculator.periodStatsSplit(activities:plans:workouts:athlete:range:asOf:)`'s own
/// doc comment for why. Planned has no change-fraction counterpart: it isn't a running total to
/// compare week over week, just what's still on the plan.
public struct SportStatsPage: Identifiable, Hashable {
    public var id: Sport { sport }
    public let sport: Sport
    /// This sport's total performed distance for the displayed week.
    public let distanceMeters: Double
    /// This sport's total performed time for the displayed week.
    public let time: TimeInterval
    /// Relative change in this sport's performed distance vs. the previous week, e.g. `0.12` for
    /// +12%.
    public let distanceChangeFraction: Double
    /// Relative change in this sport's performed time vs. the previous week.
    public let timeChangeFraction: Double
    /// The whole week's total performed load across every sport — the same value on every page.
    public let load: Double
    /// Relative change in the whole week's total performed load vs. the previous week — the same
    /// value on every page.
    public let loadChangeFraction: Double
    /// This sport's own low vs. moderate-to-high intensity time split for the displayed week's
    /// *performed* activity (the 80/20 polarized-training guideline, MVP1-48) — unlike `load`,
    /// this *is* scoped per sport: the guideline is about how a given training discipline's own
    /// sessions are distributed across intensity (Fitzgerald's "80% of your running", not "80% of
    /// everything you did this week"), so blending in an incidental low-intensity sport like
    /// walking would make the figure trivially easy to hit without actually controlling a
    /// training sport's own hard/easy mix.
    public let polarizedSplit: PolarizedIntensitySplit
    /// This sport's total planned distance for the displayed week, from `today` onward.
    public let plannedDistanceMeters: Double
    /// This sport's total planned time for the displayed week, from `today` onward.
    public let plannedTime: TimeInterval
    /// The whole week's total planned load across every sport, from `today` onward — the same
    /// value on every page, matching `load`'s own whole-week convention.
    public let plannedLoad: Double
    /// This sport's own low vs. moderate-to-high intensity time split for the displayed week's
    /// *planned* activity, from `today` onward.
    public let plannedPolarizedSplit: PolarizedIntensitySplit
}
