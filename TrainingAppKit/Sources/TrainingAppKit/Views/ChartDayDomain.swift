import Foundation
import TrainingCore

/// The shared x-axis day domain for the week view's graph panel charts (MVP1-55) — derived only
/// from `metrics`, never from `displayedWeekRange`, so `DailyLoadChartView` and `FitnessChartView`
/// (which both plot the same `metrics`) always agree on the x-axis, and paging between them
/// doesn't visibly shift it.
enum ChartDayDomain {
    static func range(for metrics: [FitnessMetrics]) -> ClosedRange<Date> {
        guard let first = metrics.first?.day, let last = metrics.last?.day else {
            let now = Date()
            return now...now
        }
        return first...last
    }
}
