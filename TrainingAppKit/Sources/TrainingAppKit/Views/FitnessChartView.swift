import Charts
import SwiftUI
import TrainingCore

/// The week view's graph panel "Form" page (MVP1-55, design doc §2.1) — the 3-week Form (TSB)
/// trend, plotted over muted background bands for each `TSBZone`, zone names annotated on the
/// chart itself rather than in a separate legend. Fitness/Fatigue (CTL/ATL) and daily load moved
/// to their own pages when the panel became a pager; see `GraphPanelPagerView`/
/// `DailyLoadChartView`.
struct FitnessChartView: View {
    let metrics: [FitnessMetrics]
    /// Date range of the week currently visible in the day list (`WeekViewModel.displayedWeekRange`),
    /// shaded behind the trend line so the 3-week chart stays visually anchored to whichever week
    /// the athlete has scrolled to.
    let displayedWeekRange: ClosedRange<Date>
    /// Days after this are projected/estimated rather than actual history (see
    /// `FitnessMetrics.isProjected`), so the Form lines render dashed past this point.
    let today: Date = .now

    /// Dash pattern for the projected/future portion of both Form lines.
    private static let futureLineStyle = StrokeStyle(dash: [5, 4])
    private static let rawLineWidth: CGFloat = 1
    private static let smoothedLineWidth: CGFloat = 3

    /// The visible y-domain, wide enough to show every `TSBZone` as a full band (including a
    /// sliver of `injuryRisk`/`detraining`, whose own real boundaries are unbounded) rather than
    /// clipping the outermost ones to a zero-height edge.
    private static let formDomain: ClosedRange<Double> = -45...40

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

    /// The zone boundary values, in ascending order — also where the chart's horizontal gridlines
    /// and leading axis labels sit, instead of an arbitrary evenly-spaced stride.
    private static let zoneBoundaries: [Double] = [-30, -10, 5, 25]

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

    // Split out of `body` (each as its own `@ChartContentBuilder` property) rather than inlined
    // directly in one `Chart { ... }` block: with every zone band, the week-highlight rectangle,
    // and four `LineMark` series (raw/smoothed × past/future) all in one expression, the compiler
    // was unable to type-check `body` in reasonable time — the same class of timeout
    // `TimeInZoneChartView` hit, fixed the same way there (see its own comment).
    @ChartContentBuilder
    private var zoneBandMarks: some ChartContent {
        ForEach(Self.zoneBands, id: \.label) { band in
            RectangleMark(
                yStart: .value("Lower", band.lowerBound),
                yEnd: .value("Upper", band.upperBound)
            )
            .foregroundStyle(band.color.opacity(0.12))
        }
    }

    @ChartContentBuilder
    private var weekHighlightMark: some ChartContent {
        RectangleMark(
            xStart: .value("Week start", displayedWeekRange.lowerBound),
            xEnd: .value("Week end", displayedWeekRange.upperBound)
        )
        .foregroundStyle(Color.primary.opacity(0.1))
    }

    /// The thin grey line follows the exact TSB values (linear interpolation, one segment per
    /// day); the thick white line (`smoothedLineMarks`) traces the same values through a smoothed
    /// (Catmull-Rom) spline — two views onto one series, not two different metrics.
    @ChartContentBuilder
    private var rawLineMarks: some ChartContent {
        ForEach(pastPoints, id: \.day) { point in
            LineMark(x: .value("Day", point.day), y: .value("TSB", point.tsb))
                .foregroundStyle(by: .value("Series", "Form (raw)"))
                .lineStyle(StrokeStyle(lineWidth: Self.rawLineWidth))
                .interpolationMethod(.linear)
        }
        ForEach(futurePoints, id: \.day) { point in
            LineMark(x: .value("Day", point.day), y: .value("TSB", point.tsb))
                .foregroundStyle(by: .value("Series", "Form (raw) (projected)"))
                .lineStyle(StrokeStyle(lineWidth: Self.rawLineWidth, dash: Self.futureLineStyle.dash))
                .interpolationMethod(.linear)
        }
    }

    @ChartContentBuilder
    private var smoothedLineMarks: some ChartContent {
        ForEach(pastPoints, id: \.day) { point in
            LineMark(x: .value("Day", point.day), y: .value("TSB", point.tsb))
                .foregroundStyle(by: .value("Series", "Form (smoothed)"))
                .lineStyle(StrokeStyle(lineWidth: Self.smoothedLineWidth))
                .interpolationMethod(.catmullRom)
        }
        ForEach(futurePoints, id: \.day) { point in
            LineMark(x: .value("Day", point.day), y: .value("TSB", point.tsb))
                .foregroundStyle(by: .value("Series", "Form (smoothed) (projected)"))
                .lineStyle(StrokeStyle(lineWidth: Self.smoothedLineWidth, dash: Self.futureLineStyle.dash))
                .interpolationMethod(.catmullRom)
        }
    }

    var body: some View {
        Chart {
            zoneBandMarks
            weekHighlightMark
            rawLineMarks
            smoothedLineMarks
        }
        // `.primary`/`.secondary`, not literal `.white`/`.gray`: those didn't adapt to the color
        // scheme, so the "white" smoothed line disappeared against this chart's own white
        // background in light mode instead of reading as black there.
        .chartForegroundStyleScale([
            "Form (raw)": Color.secondary,
            "Form (smoothed)": Color.primary,
            // Distinct series keys from the solid segments above, mapped to the same colors —
            // Swift Charts merges LineMarks sharing the same foregroundStyle(by:) value into one
            // continuous stroked path, so each dashed future segment needs its own key or its
            // .lineStyle() gets silently discarded in favor of the solid segment's style.
            "Form (raw) (projected)": Color.secondary,
            "Form (smoothed) (projected)": Color.primary,
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
        .chartYAxis {
            // Leading, not the default trailing: the zone names sit on the trailing edge (see
            // .chartOverlay below), so the numeric labels need the other side. Only at the zone
            // boundaries, not an arbitrary evenly-spaced stride — the gridlines' job here is to
            // mark where one zone ends and the next begins, not to give a generic numeric scale.
            AxisMarks(position: .leading, values: Self.zoneBoundaries) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let plotArea = geometry[plotFrame]
                    ForEach(Self.zoneBands, id: \.label) { band in
                        let midValue = (band.lowerBound + band.upperBound) / 2
                        if let y = proxy.position(forY: midValue) {
                            Text(band.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .trailing)
                                .position(x: plotArea.maxX - 38, y: plotArea.minY + y)
                        }
                    }
                }
            }
        }
        .frame(height: 172)
        .padding(.horizontal)
    }
}
