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
    /// Days after this are projected/estimated rather than actual history (see
    /// `FitnessMetrics.isProjected`), so the CTL/ATL/TSB lines render dashed past this point.
    let today: Date = .now

    /// Dash pattern for the projected/future portion of each CTL/ATL/TSB line.
    private static let futureLineStyle = StrokeStyle(dash: [5, 4])

    private var pastPoints: [FitnessMetrics] {
        FitnessMetricsSplit.pastAndFuture(metrics, today: today).past
    }

    private var futurePoints: [FitnessMetrics] {
        FitnessMetricsSplit.pastAndFuture(metrics, today: today).future
    }

    private var dailyLoads: [DailyLoad] {
        DailyLoad.aggregating(metrics)
    }

    /// Daily TRIMP load is a raw per-day value while CTL/ATL are smoothed moving averages of it,
    /// so a single heavy training day can be several times larger than the smoothed lines. It's
    /// drawn on its own trailing y-axis (rather than sharing the CTL/ATL/TSB domain) so a load
    /// spike doesn't visually flatten the trend lines.
    private var loadDomain: ClosedRange<Double> {
        let maxLoad = dailyLoads.map(\.load).max() ?? 0
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

                ForEach(pastPoints, id: \.day) { point in
                    LineMark(x: .value("Day", point.day), y: .value("CTL", point.ctl))
                        .foregroundStyle(by: .value("Series", "Fitness (CTL)"))
                    LineMark(x: .value("Day", point.day), y: .value("ATL", point.atl))
                        .foregroundStyle(by: .value("Series", "Fatigue (ATL)"))
                    LineMark(x: .value("Day", point.day), y: .value("TSB", point.tsb))
                        .foregroundStyle(by: .value("Series", "Form (TSB)"))
                }

                ForEach(futurePoints, id: \.day) { point in
                    LineMark(x: .value("Day", point.day), y: .value("CTL", point.ctl))
                        .foregroundStyle(by: .value("Series", "Fitness (CTL) (projected)"))
                        .lineStyle(Self.futureLineStyle)
                    LineMark(x: .value("Day", point.day), y: .value("ATL", point.atl))
                        .foregroundStyle(by: .value("Series", "Fatigue (ATL) (projected)"))
                        .lineStyle(Self.futureLineStyle)
                    LineMark(x: .value("Day", point.day), y: .value("TSB", point.tsb))
                        .foregroundStyle(by: .value("Series", "Form (TSB) (projected)"))
                        .lineStyle(Self.futureLineStyle)
                }
            }
            .chartForegroundStyleScale([
                "Fitness (CTL)": Color.blue,
                "Fatigue (ATL)": Color.orange,
                "Form (TSB)": Color.green,
                // Distinct series keys from the solid segments above — Swift Charts merges
                // LineMarks sharing the same foregroundStyle(by:) value into one continuous
                // stroked path, so the dashed future segment needs its own key (mapped to the
                // same color here) or its .lineStyle() gets silently discarded in favor of the
                // solid segment's style.
                "Fitness (CTL) (projected)": Color.blue,
                "Fatigue (ATL) (projected)": Color.orange,
                "Form (TSB) (projected)": Color.green,
            ])
            .chartXScale(domain: dayDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            // The load chart below is the only one with a labeled y-axis. Left unhidden, Charts'
            // own default leading axis for this chart would sit at the same position as the load
            // axis (both charts share this frame) — invisible right now only because CTL/ATL/TSB
            // are all reading 0 (MVP1-21), coincidentally matching the load axis's own domain.
            .chartYAxis(.hidden)
            .chartLegend(.hidden)

            Chart(dailyLoads, id: \.day) { point in
                PointMark(x: .value("Day", point.day), y: .value("TRIMP", point.load))
                    .foregroundStyle(by: .value("Series", "Daily load (TRIMP)"))
                    .symbolSize(20)
            }
            .chartForegroundStyleScale(["Daily load (TRIMP)": Color.red])
            .chartXScale(domain: dayDomain)
            .chartYScale(domain: loadDomain)
            .chartYAxis {
                // Leading (not trailing/right), since the CTL/ATL/TSB lines' rightmost points sit
                // right at the plot's trailing edge — a trailing axis collided with them there,
                // most visibly with the TSB line.
                AxisMarks(position: .leading)
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
