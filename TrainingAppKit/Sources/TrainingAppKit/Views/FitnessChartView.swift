import Charts
import SwiftUI
import TrainingCore

/// The week view's graph panel "Form" page (MVP1-55, design doc §2.1) — the 3-week Form (TSB)
/// trend, plotted over muted background bands for each `TSBZone`. Fitness/Fatigue (CTL/ATL) and
/// daily load moved to their own pages when the panel became a pager; see `GraphPanelPagerView`/
/// `DailyLoadChartView`.
struct FitnessChartView: View {
    let metrics: [FitnessMetrics]
    /// Date range of the week currently visible in the day list (`WeekViewModel.displayedWeekRange`),
    /// shaded behind the trend line so the 3-week chart stays visually anchored to whichever week
    /// the athlete has scrolled to.
    let displayedWeekRange: ClosedRange<Date>
    /// Days after this are projected/estimated rather than actual history (see
    /// `FitnessMetrics.isProjected`), so the Form line renders dashed past this point.
    let today: Date = .now

    /// Dash pattern for the projected/future portion of the Form line.
    private static let futureLineStyle = StrokeStyle(dash: [5, 4])

    /// The visible y-domain, wide enough to show every `TSBZone` as a full band (including a
    /// sliver of `injuryRisk`/`detraining`, whose own real boundaries are unbounded) rather than
    /// clipping the outermost ones to a zero-height edge.
    private static let formDomain: ClosedRange<Double> = -35...30

    /// One `TSBZone`'s band — lower/upper bounds and a muted color to shade it. Mirrors `TSBZone`'s
    /// own (internal-to-TrainingKit) boundaries with `PlanGuardrails()`'s defaults
    /// (`minTSBOnRaceDay: 5`, `maxTSBOnRaceDay: 25`) — `AthleteProfile` doesn't carry its own tuned
    /// guardrails yet, so those defaults are the only ones any athlete in this app actually has.
    private struct ZoneBand {
        let lowerBound: Double
        let upperBound: Double
        let color: Color
        let label: String
    }

    private static let zoneBands: [ZoneBand] = [
        ZoneBand(lowerBound: formDomain.lowerBound, upperBound: -30, color: .red, label: "Risk"),
        ZoneBand(lowerBound: -30, upperBound: -10, color: .orange, label: "Training"),
        ZoneBand(lowerBound: -10, upperBound: 5, color: .yellow, label: "Recovery"),
        ZoneBand(lowerBound: 5, upperBound: 25, color: .green, label: "Race"),
        ZoneBand(lowerBound: 25, upperBound: formDomain.upperBound, color: .blue, label: "Rest"),
    ]

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
                ForEach(Self.zoneBands, id: \.label) { band in
                    RectangleMark(
                        yStart: .value("Lower", band.lowerBound),
                        yEnd: .value("Upper", band.upperBound)
                    )
                    .foregroundStyle(band.color.opacity(0.12))
                }

                RectangleMark(
                    xStart: .value("Week start", displayedWeekRange.lowerBound),
                    xEnd: .value("Week end", displayedWeekRange.upperBound)
                )
                .foregroundStyle(Color.primary.opacity(0.1))

                ForEach(pastPoints, id: \.day) { point in
                    LineMark(x: .value("Day", point.day), y: .value("TSB", point.tsb))
                        .foregroundStyle(by: .value("Series", "Form (TSB)"))
                }

                ForEach(futurePoints, id: \.day) { point in
                    LineMark(x: .value("Day", point.day), y: .value("TSB", point.tsb))
                        .foregroundStyle(by: .value("Series", "Form (TSB) (projected)"))
                        .lineStyle(Self.futureLineStyle)
                }
            }
            .chartForegroundStyleScale([
                "Form (TSB)": TrainingMetricKind.form.color,
                // A distinct series key from the solid segment above, mapped to the same color —
                // Swift Charts merges LineMarks sharing the same foregroundStyle(by:) value into
                // one continuous stroked path, so the dashed future segment needs its own key or
                // its .lineStyle() gets silently discarded in favor of the solid segment's style.
                "Form (TSB) (projected)": TrainingMetricKind.form.color,
            ])
            .chartXScale(domain: dayDomain)
            .chartYScale(domain: Self.formDomain)
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

            HStack(spacing: 8) {
                legendEntry("Form", .form)
                Spacer(minLength: 12)
                ForEach(Self.zoneBands, id: \.label) { band in
                    zoneLegendEntry(band)
                }
            }
            .font(.caption2)
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
        .font(.caption)
    }

    private func zoneLegendEntry(_ band: ZoneBand) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(band.color)
                .frame(width: 6, height: 6)
            Text(band.label)
        }
    }
}
