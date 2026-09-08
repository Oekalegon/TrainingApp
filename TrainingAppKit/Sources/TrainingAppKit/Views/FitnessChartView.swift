import Charts
import SwiftUI
import TrainingCore

/// The 3-week CTL/ATL/TSB trend chart at the top of the week view (design doc §2.1).
struct FitnessChartView: View {
    let metrics: [FitnessMetrics]
    /// Date range of the week currently visible in the day list (`WeekViewModel.displayedWeekRange`),
    /// shaded behind the trend lines so the 3-week chart stays visually anchored to whichever week
    /// the athlete has scrolled to.
    let displayedWeekRange: ClosedRange<Date>

    /// Daily TRIMP load is a raw per-day value while CTL/ATL are smoothed moving averages of it,
    /// so a single heavy training day can be several times larger than the smoothed lines. It's
    /// drawn on its own trailing y-axis (rather than sharing the CTL/ATL/TSB domain) so a load
    /// spike doesn't visually flatten the trend lines.
    private var loadDomain: ClosedRange<Double> {
        let maxLoad = metrics.map(\.load).max() ?? 0
        return 0...max(maxLoad * 1.1, 1)
    }

    /// Explicit x-domain shared by both overlaid charts, derived only from `metrics` — never from
    /// `displayedWeekRange`. Without this, the line chart's auto-inferred domain could stretch to
    /// include the RectangleMark's dates while the point chart's domain (which has no
    /// RectangleMark) would not, misaligning the TRIMP dots against the CTL/ATL/TSB lines they're
    /// meant to sit on. In practice `displayedWeekRange` is always the middle third of `metrics`'
    /// own range, so this is a safety net rather than something normally exercised.
    private var dayDomain: ClosedRange<Date> {
        guard let first = metrics.first?.day, let last = metrics.last?.day else {
            let now = Date()
            return now...now
        }
        return first...last
    }

    var body: some View {
        ZStack {
            Chart {
                RectangleMark(
                    xStart: .value("Week start", displayedWeekRange.lowerBound),
                    xEnd: .value("Week end", displayedWeekRange.upperBound)
                )
                .foregroundStyle(Color.primary.opacity(0.1))

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
            .chartXScale(domain: dayDomain)
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
            .chartXScale(domain: dayDomain)
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
