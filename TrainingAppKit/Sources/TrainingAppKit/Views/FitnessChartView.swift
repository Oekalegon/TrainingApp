import Charts
import SwiftUI
import TrainingCore

/// The week view's graph panel "Form" page (MVP1-55, design doc §2.1) — the 3-week CTL/ATL/TSB
/// trend. Daily load moved to its own page (`DailyLoadChartView`) when the panel became a pager;
/// see `GraphPanelPagerView`.
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
            .chartLegend(.hidden)
            .frame(height: 140)
            .padding(.horizontal)

            HStack(spacing: 12) {
                // Icon/color for each metric come from `TrainingMetricKind`, the same mapping the
                // day list's metric pills (MVP1-40) use — so a metric reads as the same icon
                // whether it's here or beside a weekday row.
                legendEntry("Fitness", .fitness)
                legendEntry("Fatigue", .fatigue)
                legendEntry("Form", .form)
            }
            .font(.caption)
            .padding(.horizontal)
        }
    }

    private func legendEntry(_ title: String, _ kind: TrainingMetricKind) -> some View {
        HStack(spacing: 4) {
            Image(systemName: kind.icon)
                .foregroundStyle(kind.color)
                // The visible Text right after it already carries the meaning — without this,
                // VoiceOver announces the icon's own SF Symbol name first (e.g. "battery 100
                // percent") immediately before "Fitness", which reads as redundant/confusing.
                .accessibilityHidden(true)
            Text(title)
        }
    }
}
