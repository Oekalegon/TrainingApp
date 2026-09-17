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
    // `HeartRateHistogramChartView` hit, fixed the same way there (see its own comment).
    @ChartContentBuilder
    private var zoneBandMarks: some ChartContent {
        ForEach(TSBZoneBand.all, id: \.label) { band in
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Form")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            chart
        }
    }

    private var chart: some View {
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
        .chartYScale(domain: TSBZoneBand.domain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            // Trailing, alongside the zone names (see .chartOverlay below) — both now read on the
            // right. Only at the zone boundaries, not an arbitrary evenly-spaced stride — the
            // gridlines' job here is to mark where one zone ends and the next begins, not to give
            // a generic numeric scale.
            AxisMarks(position: .trailing, values: TSBZoneBand.boundaries) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let plotArea = geometry[plotFrame]
                    ForEach(TSBZoneBand.all, id: \.label) { band in
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
