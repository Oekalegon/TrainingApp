import Charts
import SwiftUI
import TrainingCore

/// The week view's graph panel "Daily load" page (MVP1-55, design doc §2.1) — each day's training
/// load (TRIMP) over the same 3-week window `FitnessChartView`'s "Form" page plots, so the same
/// day lines up between pages when paging back and forth.
///
/// Planned and performed are drawn as two independent bars (MVP2-30), not one bar colored by
/// past-vs-future: a full-width, muted `planned` bar (what the day's `PlannedActivity`s project),
/// with a narrower `actual` bar (what really happened, from completed `Activity`s) layered on top
/// of it. A day with only a plan not yet performed shows just the muted bar; a day with only a
/// completed activity and no plan shows just the narrow one; a day with both shows both, even if
/// they disagree — see `WeekViewModel.dailyLoadSplit(for:)`'s own doc comment for why these two
/// figures are computed independently rather than merged the way `FitnessMetrics.load` is.
struct DailyLoadChartView: View {
    let actualLoads: [DailyLoad]
    let plannedLoads: [DailyLoad]
    /// Only used for ``dayDomain``'s shared x-axis range (`ChartDayDomain.range(for:)`) — every day
    /// in the displayed window has a `FitnessMetrics` entry regardless of whether it has any
    /// load, which `actualLoads`/`plannedLoads` alone (sparse: zero-load days are dropped) can't
    /// reliably provide the window's true first/last day from.
    let metrics: [FitnessMetrics]
    /// Date range of the week currently visible in the day list, shaded behind the bars — same
    /// role as `FitnessChartView.displayedWeekRange`.
    let displayedWeekRange: ClosedRange<Date>

    /// The planned bar is full width; the actual bar is narrower so it visibly nests inside it
    /// rather than the two reading as unrelated, same-width bars sitting side by side.
    private static let actualBarWidth: MarkDimension = .ratio(0.45)

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

                // Planned drawn first (full width, muted), so the narrower actual bar layers
                // visibly on top of it. `stacking: .unstacked` on both is required -- without it,
                // Charts sums same-x-day BarMarks (adding their heights) rather than overlaying
                // them, the same behavior this view's old past/future split had to work around by
                // keeping its two bar series on mutually exclusive days.
                ForEach(plannedLoads, id: \.day) { point in
                    BarMark(
                        x: .value("Day", point.day, unit: .day), y: .value("Planned TRIMP", point.load),
                        stacking: .unstacked
                    )
                    .foregroundStyle(Color.secondary)
                }
                ForEach(actualLoads, id: \.day) { point in
                    BarMark(
                        x: .value("Day", point.day, unit: .day), y: .value("Performed TRIMP", point.load),
                        width: Self.actualBarWidth, stacking: .unstacked
                    )
                    .foregroundStyle(Color.primary)
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
            .frame(height: 172)
            .padding(.horizontal)
        }
    }
}
