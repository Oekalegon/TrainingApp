import Foundation
import TrainingCore

/// One calendar day's heart-rate time-in-zone breakdown, for the week view's graph panel's "Time
/// in zone" page (MVP1-55) — see `WeekViewModel.timeInZoneByDay()`.
public struct DayTimeInZone: Identifiable, Hashable {
    public var id: Date { day }
    public let day: Date
    /// Every completed activity's `TimeInZone` on `day`, summed via `TimeInZone.+` — empty (all
    /// zeros) on a day with no activities, or none with heart-rate samples.
    public let timeInZone: TimeInZone
}
