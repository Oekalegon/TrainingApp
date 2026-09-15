import Foundation
import TrainingCore

/// What `MetricDetailView` is anchored on (MVP1-45/MVP1-60): a specific day, from tapping a
/// day-list pill, or a whole displayed week, from tapping the week view's own graph panel. Either
/// way the screen reads the same — a big value, a date, a chart with something highlighted, an
/// explanation — but a day shows *that day's own* value/date and highlights just that one day,
/// while a week shows the *week's own average* value and date range and highlights the whole week
/// (the same week-band treatment `FitnessChartView`'s main graph already uses).
///
/// `metrics(in:calendar:)`/`dateText(calendar:)` live here, not as private computed properties on
/// `MetricDetailView` itself, specifically so `MetricDetailSubjectTests` can exercise the
/// day/week-matching logic directly — the same reasoning `ChartPanState`/`ChartAxisMarks` were
/// pulled out of `MetricDetailView`/`MetricDetailChartView` for.
enum MetricDetailSubject: Hashable {
    case day(Date)
    case week(ClosedRange<Date>)

    /// This subject's own points within `all` — the single day's own point for a `.day` subject
    /// (matched via `calendar.isDate(_:inSameDayAs:)`, not `==`, the same reasoning
    /// `WeekViewModel.metrics(on:)` already documents for the same comparison), or every point
    /// inside a `.week` subject's own range for `MetricDetailView` to average.
    ///
    /// A half-open comparison for `.week`, not `range.contains(_:)` — `range` itself
    /// (`WeekViewModel.displayedWeekRange(for:)`) is `weekStart...weekStart+7days`, so a
    /// `ClosedRange`'s inclusive upper bound would wrongly pull in the *next* week's own point for
    /// whichever day happens to land exactly on that boundary.
    func metrics(in all: [FitnessMetrics], calendar: Calendar) -> [FitnessMetrics] {
        switch self {
        case .day(let day):
            return all.filter { calendar.isDate($0.day, inSameDayAs: day) }
        case .week(let range):
            return all.filter { $0.day >= range.lowerBound && $0.day < range.upperBound }
        }
    }

    /// This subject's own date text for `MetricDetailView`'s header: a full "weekday, month day,
    /// year" for a `.day` subject, or a plain "Sep 14 – Sep 20, 2026" range for a `.week` one — a
    /// full "weekday, month day, year" format applied to both ends of a week that doesn't cross a
    /// year boundary would repeat the year twice, which this avoids by only ever appending it once,
    /// to the range's own last actual day.
    func dateText(calendar: Calendar) -> String {
        switch self {
        case .day(let day):
            var format = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day().year()
            format.calendar = calendar
            format.timeZone = calendar.timeZone
            return day.formatted(format)
        case .week(let range):
            var format = Date.FormatStyle.dateTime.month(.abbreviated).day()
            format.calendar = calendar
            format.timeZone = calendar.timeZone
            let yearFormat = format.year()
            // `range.upperBound` is the *next* week's own start (see `metrics(in:calendar:)`'s own
            // doc comment), not a day actually in this week -- back up one day to the week's own
            // last actual day before formatting it.
            let lastDay = calendar.date(byAdding: .day, value: -1, to: range.upperBound) ?? range.lowerBound
            return "\(range.lowerBound.formatted(format)) – \(lastDay.formatted(yearFormat))"
        }
    }
}
