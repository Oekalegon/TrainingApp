import Charts
import SwiftUI
import TrainingCore

/// The 3-week CTL/ATL/TSB trend chart at the top of the week view (design doc §2.1).
struct FitnessChartView: View {
    let metrics: [FitnessMetrics]
    /// Date range of the calendar week containing "now" (`WeekViewModel.currentWeekRange(asOf:)`),
    /// shaded behind the trend lines so "now" stays visible even when the displayed week (and so
    /// the chart's 3-week window) has been navigated away from it.
    let currentWeekRange: ClosedRange<Date>

    /// Daily TRIMP load is a raw per-day value while CTL/ATL are smoothed moving averages of it,
    /// so a single heavy training day can be several times larger than the smoothed lines. It's
    /// drawn on its own trailing y-axis (rather than sharing the CTL/ATL/TSB domain) so a load
    /// spike doesn't visually flatten the trend lines.
    private var loadDomain: ClosedRange<Double> {
        let maxLoad = metrics.map(\.load).max() ?? 0
        return 0...max(maxLoad * 1.1, 1)
    }

    var body: some View {
        ZStack {
            Chart {
                RectangleMark(
                    xStart: .value("Week start", currentWeekRange.lowerBound),
                    xEnd: .value("Week end", currentWeekRange.upperBound)
                )
                .foregroundStyle(Color.primary.opacity(0.06))

                ForEach(metrics, id: \.day) { point in
                    LineMark(x: .value("Day", point.day), y: .value("CTL", point.ctl))
                        .foregroundStyle(by: .value("Series", "Fitness (CTL)"))
                    LineMark(x: .value("Day", point.day), y: .value("ATL", point.atl))
                        .foregroundStyle(by: .value("Series", "Fatigue (ATL)"))
                    LineMark(x: .value("Day", point.day), y: .value("TSB", point.tsb))
                        .foregroundStyle(by: .value("Series", "Form (TSB)"))
                }
            }
            .chartForegroundStyleScale([
                "Fitness (CTL)": Color.blue,
                "Fatigue (ATL)": Color.orange,
                "Form (TSB)": Color.green,
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartLegend(.hidden)

            Chart(metrics, id: \.day) { point in
                PointMark(x: .value("Day", point.day), y: .value("TRIMP", point.load))
                    .foregroundStyle(by: .value("Series", "Daily load (TRIMP)"))
            }
            .chartForegroundStyleScale(["Daily load (TRIMP)": Color.red])
            .chartYScale(domain: loadDomain)
            .chartYAxis {
                AxisMarks(position: .trailing)
            }
            .chartXAxis(.hidden)
            .chartLegend(.hidden)
        }
        .frame(height: 180)
        .padding(.horizontal)

        HStack(spacing: 12) {
            legendEntry("Fitness (CTL)", .blue)
            legendEntry("Fatigue (ATL)", .orange)
            legendEntry("Form (TSB)", .green)
            legendEntry("Daily load (TRIMP)", .red)
        }
        .font(.caption)
        .padding(.horizontal)
    }

    private func legendEntry(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
        }
    }
}
