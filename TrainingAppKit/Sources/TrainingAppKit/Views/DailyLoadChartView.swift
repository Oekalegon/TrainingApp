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

    /// Actual (completed) days' load, up to and including `today`.
    ///
    /// Deliberately not `FitnessMetricsSplit.pastAndFuture` — that helper includes `today` in
    /// *both* halves on purpose, so `FitnessChartView`'s solid and dashed line segments connect
    /// with no gap. Bars have no such continuity to preserve, and reusing it here silently drew
    /// two overlapping `BarMark`s (stacked, since Charts groups same-x bars by default) for
    /// today's own day — visibly a too-tall bar overshooting the y-axis.
    private var pastLoads: [DailyLoad] {
        DailyLoad.aggregating(metrics.filter { $0.day <= today })
    }

    /// Projected/planned days' load, strictly after `today` (see `pastLoads`'s own doc comment for
    /// why not `today` too), rendered as muted bars distinct from actual history.
    private var futureLoads: [DailyLoad] {
        DailyLoad.aggregating(metrics.filter { $0.day > today })
    }

    /// `ChartDayDomain.range(for:)` widened by a full day on each end.
    ///
    /// That shared range spans exactly the first day's start through the last day's start, which
    /// is correct for `FitnessChartView`'s `LineMark`s (a single point plotted exactly at each day
    /// has nothing to overflow) but not for this chart's `BarMark`s: a `unit: .day` bar spans the
    /// *whole* following day from its own x-value, not a day centered on it, so the first/last
    /// bars each need a full day of room on their outer side to render completely — half a day
    /// (tried first) still left the last day's bar (a real day, not a rendering bug: e.g. the 7th
    /// day of the *next* window over) half-drawn onto the trailing axis instead of fully inside
    /// the plot.
    private var dayDomain: ClosedRange<Date> {
        let range = ChartDayDomain.range(for: metrics)
        let oneDay: TimeInterval = 24 * 60 * 60
        return range.lowerBound.addingTimeInterval(-oneDay)...range.upperBound.addingTimeInterval(oneDay)
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
