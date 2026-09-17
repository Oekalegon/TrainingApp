import Foundation

/// Explicit x-axis gridline dates for a metric detail chart (MVP1-45), aligned to a calendar
/// boundary that matches how the athlete actually thinks about the picked period, rather than an
/// arbitrary evenly-spaced day stride from the domain's own edge. Shared by `LoadDetailChartView`
/// and `FitnessTrendDetailChartView` so the two never pick this differently.
enum ChartAxisMarks {
    /// - `.week`/`.month`: each visible week's own start (the athlete's own `calendar.firstWeekday`,
    ///   Monday by default) -- daily bars/points read most naturally against week boundaries at
    ///   this span.
    /// - `.threeMonths`/`.sixMonths`: each visible month's own first day.
    /// - `.year`: only the four evenly-spaced calendar-quarter starts (January, April, July,
    ///   October) of each visible year -- a fixed set of four gridlines per year rather than one
    ///   per month, which would be unreadable at this span.
    static func dates(for period: ChartPeriod, in domain: ClosedRange<Date>, calendar: Calendar) -> [Date] {
        switch period {
        case .week, .month:
            return boundaries(in: domain, calendar: calendar, component: .weekOfYear)
        case .threeMonths, .sixMonths:
            return boundaries(in: domain, calendar: calendar, component: .month)
        case .year:
            return yearMonthMarks(in: domain, calendar: calendar, months: [1, 4, 7, 10])
        }
    }

    /// Every `component`-start (week or month) that falls inside `domain`, found by stepping
    /// forward one `component` at a time from `domain`'s own first boundary rather than guessing a
    /// fixed day-count stride that would drift out of calendar alignment over a wide domain.
    private static func boundaries(in domain: ClosedRange<Date>, calendar: Calendar, component: Calendar.Component) -> [Date] {
        guard var current = calendar.dateInterval(of: component, for: domain.lowerBound)?.start else { return [] }
        var dates: [Date] = []
        while current <= domain.upperBound {
            if current >= domain.lowerBound {
                dates.append(current)
            }
            guard let next = calendar.date(byAdding: component, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }

    /// The first day of each `months` (1-based) in every year `domain` touches, restricted to
    /// dates actually inside `domain`.
    private static func yearMonthMarks(in domain: ClosedRange<Date>, calendar: Calendar, months: [Int]) -> [Date] {
        let startYear = calendar.component(.year, from: domain.lowerBound)
        let endYear = calendar.component(.year, from: domain.upperBound)
        guard startYear <= endYear else { return [] }
        var dates: [Date] = []
        for year in startYear...endYear {
            for month in months {
                var components = DateComponents()
                components.year = year
                components.month = month
                components.day = 1
                if let date = calendar.date(from: components), domain.contains(date) {
                    dates.append(date)
                }
            }
        }
        return dates.sorted()
    }

    /// Pinned rather than left to the device's own locale (unlike `MetricDetailView.subjectDateText`,
    /// which does follow it): the "MMM d" vs. "d MMM" ordering (and even the bare month+year
    /// ordering `labelText` itself already works around below) turns out to depend not just on
    /// locale but on the `Calendar`'s own identifier/locale too, which made this label's exact
    /// wording effectively untestable without pinning something. Reasonable for a compact axis
    /// label in an app with no localized strings anywhere else yet.
    private static let labelLocale = Locale(identifier: "en_US")

    /// The text for one gridline's own label — `dates(for:in:calendar:)`'s own dates, formatted to
    /// match what each period's gridlines actually mean:
    /// - `.week`/`.month`: "Sep 14" — a week-start is a specific day, so the day number still
    ///   matters.
    /// - `.threeMonths`/`.sixMonths`/`.year`: "Sep" — every gridline here is already a month's own
    ///   first day, so a day number would just repeat "1" on every label. The year is appended only
    ///   for a gridline that's January (the first month of a year), so a chart spanning a year
    ///   boundary shows it exactly once, at the point the year actually changes.
    static func labelText(for date: Date, period: ChartPeriod, calendar: Calendar) -> String {
        switch period {
        case .week, .month:
            var format = Date.FormatStyle.dateTime.month(.abbreviated).day()
            format.calendar = calendar
            format.timeZone = calendar.timeZone
            format.locale = labelLocale
            return date.formatted(format)
        case .threeMonths, .sixMonths, .year:
            var monthFormat = Date.FormatStyle.dateTime.month(.abbreviated)
            monthFormat.calendar = calendar
            monthFormat.timeZone = calendar.timeZone
            monthFormat.locale = labelLocale
            let monthText = date.formatted(monthFormat)
            guard calendar.component(.month, from: date) == 1 else { return monthText }
            // Appended as a plain number, not composed into one `Date.FormatStyle` alongside the
            // month -- a bare month+year skeleton (no day) doesn't reliably order "MMM y" the way a
            // full date does, so this pins "Jan 2026" rather than risking "2026 Jan".
            return "\(monthText) \(calendar.component(.year, from: date))"
        }
    }
}
