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

    private var dailyLoads: [DailyLoad] {
        DailyLoad.aggregating(metrics)
    }

    private var dayDomain: ClosedRange<Date> {
        ChartDayDomain.range(for: metrics)
    }

    var body: some View {
        VStack(spacing: 8) {
            Chart {
                RectangleMark(
                    xStart: .value("Week start", displayedWeekRange.lowerBound),
                    xEnd: .value("Week end", displayedWeekRange.upperBound)
                )
                .foregroundStyle(Color.primary.opacity(0.1))

                ForEach(dailyLoads, id: \.day) { point in
                    BarMark(x: .value("Day", point.day, unit: .day), y: .value("TRIMP", point.load))
                        .foregroundStyle(TrainingMetricKind.load.color)
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

            HStack(spacing: 4) {
                Image(systemName: TrainingMetricKind.load.icon)
                    .foregroundStyle(TrainingMetricKind.load.color)
                    .accessibilityHidden(true)
                Text("Daily load")
            }
            .font(.caption)
            .padding(.horizontal)
        }
    }
}
