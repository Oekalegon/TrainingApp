import Foundation

/// What `MetricDetailView` is anchored on (MVP1-45/MVP1-60): a specific day, from tapping a
/// day-list pill, or a whole displayed week, from tapping the week view's own graph panel. Either
/// way the screen reads the same — a big value, a date, a chart with something highlighted, an
/// explanation — but a day shows *that day's own* value/date and highlights just that one day,
/// while a week shows the *week's own average* value and date range and highlights the whole week
/// (the same week-band treatment `FitnessChartView`'s main graph already uses).
enum MetricDetailSubject: Hashable {
    case day(Date)
    case week(ClosedRange<Date>)
}
