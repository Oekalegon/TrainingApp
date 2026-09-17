import Foundation

/// The time range a metric detail chart shows (MVP1-45) — picked via a segmented control in
/// `MetricDetailView`, and retained across metric sheets (`WeekView` owns the single shared
/// selection) so switching from, say, Load to Fitness doesn't reset back to the default.
enum ChartPeriod: String, CaseIterable, Identifiable {
    case week, month, threeMonths, sixMonths, year

    var id: Self { self }

    /// Segmented-control label.
    var shortLabel: String {
        switch self {
        case .week: "W"
        case .month: "M"
        case .threeMonths: "3M"
        case .sixMonths: "6M"
        case .year: "Y"
        }
    }

    /// Days to look back from the window's own end. `.week`'s 21 matches the existing default
    /// 3-week window (the touched day's own week, the one before, and the one after) exactly, so
    /// selecting "W" (or never touching the control) doesn't change today's behavior.
    var lookbackDays: Int {
        switch self {
        case .week: 21
        case .month: 30
        case .threeMonths: 90
        case .sixMonths: 182
        case .year: 365
        }
    }

    /// The date range to show, ending a week after `touchedDay` (matching the existing default
    /// window's own forward extent into the touched day's "next week") and reaching back
    /// `lookbackDays` from there.
    func range(around touchedDay: Date, calendar: Calendar) -> ClosedRange<Date> {
        let end = calendar.date(byAdding: .day, value: 7, to: touchedDay) ?? touchedDay
        let start = calendar.date(byAdding: .day, value: -lookbackDays, to: end) ?? touchedDay
        return start...end
    }

    /// A day-count stride for chart x-axis gridlines, coarser for longer periods so a year's worth
    /// of days doesn't draw a gridline every week.
    var axisStrideDays: Int {
        switch self {
        case .week: 7
        case .month: 7
        case .threeMonths: 14
        case .sixMonths: 30
        case .year: 60
        }
    }
}
