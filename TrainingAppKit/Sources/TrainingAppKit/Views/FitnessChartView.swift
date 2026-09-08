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
    /// Defaults to `.now`, but is a stored property (not a default parameter) so a preview or a
    /// future test can pin it.
    let today: Date

    init(metrics: [FitnessMetrics], displayedWeekRange: ClosedRange<Date>, today: Date = .now) {
        self.metrics = metrics
        self.displayedWeekRange = displayedWeekRange
        self.today = today
    }

    /// `metrics`, sorted by day — the split into ``pastPoints`` / ``futurePoints`` below assumes
    /// ascending order.
    private var sortedMetrics: [FitnessMetrics] {
        metrics.sorted { $0.day < $1.day }
    }

    /// Days up to and including `today` — drawn as solid lines. Includes the first future day too
    /// (see ``futurePoints``) so the solid and dashed segments connect with no visual gap.
    private var pastPoints: [FitnessMetrics] {
        let sorted = sortedMetrics
        guard let splitIndex = sorted.lastIndex(where: { $0.day <= today }) else { return [] }
        return Array(sorted[0...splitIndex])
    }

    /// Days from `today` onward — drawn as dashed lines, since a projected/estimated value hasn't
    /// actually happened yet. Starts at the same index as ``pastPoints`` ends, not one past it, so
    /// the dashed segment continues from exactly where the solid one stops.
    private var futurePoints: [FitnessMetrics] {
        let sorted = sortedMetrics
        guard let splitIndex = sorted.lastIndex(where: { $0.day <= today }) else { return sorted }
        return Array(sorted[splitIndex...])
    }

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
                        .foregroundStyle(by: .value("Series", "Fitness (CTL)"))
                        .lineStyle(StrokeStyle(dash: [5, 4]))
                    LineMark(x: .value("Day", point.day), y: .value("ATL", point.atl))
                        .foregroundStyle(by: .value("Series", "Fatigue (ATL)"))
                        .lineStyle(StrokeStyle(dash: [5, 4]))
                    LineMark(x: .value("Day", point.day), y: .value("TSB", point.tsb))
                        .foregroundStyle(by: .value("Series", "Form (TSB)"))
                        .lineStyle(StrokeStyle(dash: [5, 4]))
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
