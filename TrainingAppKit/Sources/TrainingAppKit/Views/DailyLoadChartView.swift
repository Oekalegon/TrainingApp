import Charts
import SwiftUI
import TrainingCore

/// The week view's graph panel "Daily load" page (MVP1-55, design doc §2.1) — each day's total
/// training load (TRIMP) over the same 3-week window `FitnessChartView`'s "Form" page plots, so
/// the same day lines up between pages when paging back and forth.
struct DailyLoadChartView: View {
    let metrics: [FitnessMetrics]
    /// Date range of the week currently visible in the day list, shaded behind the bars — same
    /// role as `FitnessChartView.displayedWeekRange`.
    let displayedWeekRange: ClosedRange<Date>
    let today: Date = .now

    /// Actual (completed) days' load — `FitnessMetricsSplit.pastAndFuture` also includes `today`
    /// in `future`, which would double-draw its bar; `DailyLoad.aggregating` already drops
    /// zero-load days, so there's no separate "did today already load" check needed here.
    private var pastLoads: [DailyLoad] {
        DailyLoad.aggregating(FitnessMetricsSplit.pastAndFuture(metrics, today: today).past)
    }

    /// Projected/planned days' load, rendered as muted bars distinct from actual history.
    private var futureLoads: [DailyLoad] {
        DailyLoad.aggregating(FitnessMetricsSplit.pastAndFuture(metrics, today: today).future)
    }

    private var dayDomain: ClosedRange<Date> {
        ChartDayDomain.range(for: metrics)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Daily Load")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Chart {
                RectangleMark(
                    xStart: .value("Week start", displayedWeekRange.lowerBound),
                    xEnd: .value("Week end", displayedWeekRange.upperBound)
                )
                .foregroundStyle(Color.primary.opacity(0.1))

                ForEach(pastLoads, id: \.day) { point in
                    BarMark(x: .value("Day", point.day, unit: .day), y: .value("TRIMP", point.load))
                        .foregroundStyle(Color.primary)
                }
                ForEach(futureLoads, id: \.day) { point in
                    BarMark(x: .value("Day", point.day, unit: .day), y: .value("TRIMP", point.load))
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartXScale(domain: dayDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 140)
            .padding(.horizontal)
        }
    }
}
