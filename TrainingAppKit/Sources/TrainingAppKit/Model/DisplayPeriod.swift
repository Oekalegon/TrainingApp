import Foundation

/// A run of consecutive days the week view shows at once: a calendar week today, and a 7-, 10- or
/// 14-day micro-cycle once plans use those (MVP5-106).
///
/// Everything in ``MicroCycleViewModel`` that used to assume 7 days (the date range, the chart window, the
/// load range, the cache keys) is derived from a period's ``lengthInDays`` instead. Dates are
/// computed with the athlete's calendar, so day arithmetic stays correct across daylight-saving
/// changes.
///
/// The same-length helpers (``next(calendar:)``, ``previous(calendar:)``, ``chartRange(calendar:)``,
/// ``loadRange(calendar:)``) are exact for calendar weeks only. ``MicroCycleViewModel`` doesn't use them: it
/// takes the neighbors from the plan (MVP5-107), where a micro-cycle can be followed or preceded by a
/// period of another length.
public struct DisplayPeriod: Hashable, Sendable {
    /// The number of days in a calendar week.
    public static let calendarWeekLength = 7

    /// The first day of the period, at the start of a day in the athlete's calendar.
    public let start: Date
    /// The number of days the period spans; at least 1.
    public let lengthInDays: Int

    /// - Parameters:
    ///   - start: The first day of the period.
    ///   - lengthInDays: The number of days the period spans; values below 1 are raised to 1.
    public init(start: Date, lengthInDays: Int) {
        self.start = start
        self.lengthInDays = max(1, lengthInDays)
    }

    /// The calendar week containing `date`, starting on the first weekday of `calendar`.
    public static func calendarWeek(containing date: Date, calendar: Calendar) -> DisplayPeriod {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return DisplayPeriod(start: start, lengthInDays: calendarWeekLength)
    }

    /// The period of the same length that starts `days` days after this one (negative for earlier).
    public func shifted(byDays days: Int, calendar: Calendar) -> DisplayPeriod {
        DisplayPeriod(start: calendar.date(byAdding: .day, value: days, to: start) ?? start, lengthInDays: lengthInDays)
    }

    /// The period of the same length that follows this one.
    public func next(calendar: Calendar) -> DisplayPeriod {
        shifted(byDays: lengthInDays, calendar: calendar)
    }

    /// The period of the same length that precedes this one.
    public func previous(calendar: Calendar) -> DisplayPeriod {
        shifted(byDays: -lengthInDays, calendar: calendar)
    }

    /// The period's days in order, starting at ``start``.
    public func days(calendar: Calendar) -> [Date] {
        (0..<lengthInDays).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// The last day of the period.
    public func lastDay(calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: lengthInDays - 1, to: start) ?? start
    }

    /// The span the chart shows: the period before, this period and the period after, so
    /// `start - lengthInDays ... start + 2 × lengthInDays - 1` (3 weeks for a calendar week).
    public func chartRange(calendar: Calendar) -> ClosedRange<Date> {
        let first = calendar.date(byAdding: .day, value: -lengthInDays, to: start) ?? start
        let last = calendar.date(byAdding: .day, value: 2 * lengthInDays - 1, to: start) ?? start
        return first...last
    }

    /// The span fetched from the stores: wide enough to cover the ``chartRange(calendar:)`` of both
    /// neighboring periods, so paging to either needs no further load.
    public func loadRange(calendar: Calendar) -> ClosedRange<Date> {
        previous(calendar: calendar).chartRange(calendar: calendar).lowerBound...next(calendar: calendar)
            .chartRange(calendar: calendar).upperBound
    }

    /// The span highlighted on the chart: from ``start`` to the start of the following period.
    public func highlightRange(calendar: Calendar) -> ClosedRange<Date> {
        start...(calendar.date(byAdding: .day, value: lengthInDays, to: start) ?? start)
    }
}
