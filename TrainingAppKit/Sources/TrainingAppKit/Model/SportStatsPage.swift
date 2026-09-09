import Foundation
import TrainingCore

/// One sport's page in the week view's stats pager — see ``WeekViewModel/sportStatsPages(asOf:)``.
///
/// `distanceMeters`/`time` (and their change fractions) are this sport's own totals, but `load`/
/// `loadChangeFraction` are always the *whole week's* total load across every sport, identical on
/// every page: training load (TRIMP) isn't meaningfully attributable to one sport the way distance
/// and time are — it's a systemic measure that feeds one CTL/ATL/TSB series regardless of which
/// sport produced it — so slicing it per sport here would suggest a distinction the underlying
/// model doesn't make.
public struct SportStatsPage: Identifiable, Hashable {
    public var id: Sport { sport }
    public let sport: Sport
    /// This sport's total distance for the displayed week.
    public let distanceMeters: Double
    /// This sport's total time for the displayed week.
    public let time: TimeInterval
    /// Relative change in this sport's distance vs. the previous week, e.g. `0.12` for +12%.
    public let distanceChangeFraction: Double
    /// Relative change in this sport's time vs. the previous week.
    public let timeChangeFraction: Double
    /// The whole week's total load across every sport — the same value on every page.
    public let load: Double
    /// Relative change in the whole week's total load vs. the previous week — the same value on
    /// every page.
    public let loadChangeFraction: Double
}
