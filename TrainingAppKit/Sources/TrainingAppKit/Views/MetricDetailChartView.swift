import Charts
import SwiftUI
import TrainingCore

/// The Load (TRIMP) metric info sheet's own daily-load chart (MVP1-45) — the same 3-week Daily
/// Load data `DailyLoadChartView` plots (so paging between the two agrees), but with `touchedDay`
/// highlighted in full `.primary` against every other day muted to `.secondary`, rather than only
/// distinguishing past (actual) from future (projected) bars. `touchedDay` renders from whichever
/// half it actually falls in — including a still-projected day's own estimated TRIMP — so tapping
/// a planned day's Load pill doesn't show a blank bar. Marks that one day only, not the week it
/// falls in — the bar's own full-`.primary` fill already is that mark, so there's no separate week
/// band the way the main week graph draws one.
struct LoadDetailChartView: View {
    let metrics: [FitnessMetrics]
    let touchedDay: Date
    let calendar: Calendar

    private var loads: [DailyLoad] {
        DailyLoad.aggregating(metrics)
    }

    private var dayDomain: ClosedRange<Date> {
        let range = ChartDayDomain.range(for: metrics)
        let oneDay: TimeInterval = 24 * 60 * 60
        return range.lowerBound.addingTimeInterval(-oneDay)...range.upperBound.addingTimeInterval(oneDay)
    }

    private func isTouched(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: touchedDay)
    }

    var body: some View {
        Chart {
            ForEach(loads, id: \.day) { point in
                BarMark(x: .value("Day", point.day, unit: .day), y: .value("TRIMP", point.load))
                    .foregroundStyle(isTouched(point.day) ? Color.primary : Color.secondary.opacity(0.4))
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
        .frame(height: 160)
    }
}

/// The Fitness/Fatigue/Form metric info sheet's own trend chart (MVP1-45) — the same 3-week
/// CTL/ATL/TSB data `FitnessChartView` plots, but with `emphasized` drawn as a thick `.primary`
/// line (matching that main chart's own smoothed-line treatment) and the other two subdued to a
/// thin `.secondary` line, plus a manual legend naming all three (`.chartLegend` isn't used here —
/// two subdued series sharing the exact same muted color would otherwise render as two
/// indistinguishable swatches).
///
/// `emphasized`'s own value range drives the y-domain — the other two series may run outside it
/// and simply clip, rather than a shared auto-fit range picked by whichever series happens to be
/// widest. The one exception is `.form`: since that's also the only case that shows `TSBZoneBand`
/// shading, it keeps that shading's own fixed domain instead (see `yDomain`'s own doc comment).
struct FitnessTrendDetailChartView: View {
    let metrics: [FitnessMetrics]
    /// Which of `.fitness`/`.fatigue`/`.form` to emphasize — `.load` never reaches this view (see
    /// `FitnessMetricsInfoView`'s own dispatch).
    let emphasized: TrainingMetricKind
    /// The day whose pill was tapped — marked with a vertical rule, not the whole week it falls
    /// in (unlike the main week graph, which shades a full week band).
    let touchedDay: Date
    let calendar: Calendar
    let today: Date = .now

    private static let emphasizedLineWidth: CGFloat = 3
    private static let subduedLineWidth: CGFloat = 1
    private static let futureLineStyle = StrokeStyle(dash: [5, 4])
    private static let seriesOrder: [TrainingMetricKind] = [.fitness, .fatigue, .form]

    private var pastPoints: [FitnessMetrics] {
        FitnessMetricsSplit.pastAndFuture(metrics, today: today).past
    }

    private var futurePoints: [FitnessMetrics] {
        FitnessMetricsSplit.pastAndFuture(metrics, today: today).future
    }

    private var dayDomain: ClosedRange<Date> {
        ChartDayDomain.range(for: metrics)
    }

    private func value(for kind: TrainingMetricKind, in point: FitnessMetrics) -> Double {
        switch kind {
        case .fitness: point.ctl
        case .fatigue: point.atl
        case .form: point.tsb
        case .load: point.load
        }
    }

    /// See this type's own doc comment for why `.form` is the one case that doesn't compute a
    /// fitted range: `TSBZoneBand.domain` is already sized around TSB's own realistic range (real
    /// athletes' TSB rarely nears its ±45 edges), so it satisfies "fit the emphasized metric" in
    /// spirit while also giving every zone band room to render as a full-height rectangle instead
    /// of clipping the outermost ones.
    private var yDomain: ClosedRange<Double> {
        guard emphasized != .form else { return TSBZoneBand.domain }
        let values = metrics.map { value(for: emphasized, in: $0) }
        guard let lower = values.min(), let upper = values.max(), lower < upper else {
            return TSBZoneBand.domain
        }
        let padding = max((upper - lower) * 0.1, 1)
        return (lower - padding)...(upper + padding)
    }

    @ChartContentBuilder
    private var zoneBandMarks: some ChartContent {
        if emphasized == .form {
            ForEach(TSBZoneBand.all, id: \.label) { band in
                RectangleMark(yStart: .value("Lower", band.lowerBound), yEnd: .value("Upper", band.upperBound))
                    .foregroundStyle(band.color.opacity(0.12))
            }
        }
    }

    /// `touchedDay` itself when `metrics` actually has a point for it, otherwise `touchedDay`
    /// as-is — snapping to the real data point's own `day` value keeps the rule pixel-aligned with
    /// that day's line points rather than landing a hair off if `touchedDay` (built from
    /// `WeekViewModel`'s own day list) and `FitnessMetrics.day` (built inside TrainingKit) don't
    /// happen to be bit-identical `Date`s for the same calendar day.
    private var markedDay: Date {
        metrics.first { calendar.isDate($0.day, inSameDayAs: touchedDay) }?.day ?? touchedDay
    }

    @ChartContentBuilder
    private var dayHighlightMark: some ChartContent {
        RuleMark(x: .value("Day", markedDay))
            .foregroundStyle(Color.primary.opacity(0.15))
            .lineStyle(StrokeStyle(lineWidth: 1))
    }

    /// One metric's line, past (solid) and future (dashed) — a distinct series key per
    /// past/future/kind combination, same reasoning `FitnessChartView` documents for its own raw
    /// vs. smoothed lines: Swift Charts merges same-key `LineMark`s into one continuous stroked
    /// path, silently discarding a later segment's own `.lineStyle()` (its dash pattern) in favor
    /// of the first's.
    @ChartContentBuilder
    private func lineMarks(for kind: TrainingMetricKind) -> some ChartContent {
        let width = kind == emphasized ? Self.emphasizedLineWidth : Self.subduedLineWidth
        ForEach(pastPoints, id: \.day) { point in
            LineMark(x: .value("Day", point.day), y: .value(kind.name, value(for: kind, in: point)))
                .foregroundStyle(by: .value("Series", kind.name))
                .lineStyle(StrokeStyle(lineWidth: width))
                .interpolationMethod(.catmullRom)
        }
        ForEach(futurePoints, id: \.day) { point in
            LineMark(x: .value("Day", point.day), y: .value(kind.name, value(for: kind, in: point)))
                .foregroundStyle(by: .value("Series", "\(kind.name) (projected)"))
                .lineStyle(StrokeStyle(lineWidth: width, dash: Self.futureLineStyle.dash))
                .interpolationMethod(.catmullRom)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            chart
            legend
        }
    }

    private var chart: some View {
        Chart {
            zoneBandMarks
            dayHighlightMark
            lineMarks(for: .fitness)
            lineMarks(for: .fatigue)
            lineMarks(for: .form)
        }
        // A literal `KeyValuePairs` built inline, not a stored `[String: Color]` passed in --
        // `chartForegroundStyleScale` only accepts the former, even though a dictionary *literal*
        // at the call site satisfies it via `ExpressibleByDictionaryLiteral`. The color per entry
        // is still a live expression against `emphasized`, so this stays a single place to update
        // if a series' naming ever changes.
        .chartForegroundStyleScale([
            TrainingMetricKind.fitness.name: emphasized == .fitness ? Color.primary : Color.secondary,
            "\(TrainingMetricKind.fitness.name) (projected)": emphasized == .fitness ? Color.primary : Color.secondary,
            TrainingMetricKind.fatigue.name: emphasized == .fatigue ? Color.primary : Color.secondary,
            "\(TrainingMetricKind.fatigue.name) (projected)": emphasized == .fatigue ? Color.primary : Color.secondary,
            TrainingMetricKind.form.name: emphasized == .form ? Color.primary : Color.secondary,
            "\(TrainingMetricKind.form.name) (projected)": emphasized == .form ? Color.primary : Color.secondary,
        ])
        .chartXScale(domain: dayDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartLegend(.hidden)
        .frame(height: 160)
    }

    /// A manual legend, not `.chartLegend` — see this type's own doc comment for why: with two
    /// subdued series sharing the exact `.secondary` swatch, the built-in legend would render two
    /// visually identical entries, distinguishable only by their text label sitting right next to
    /// an equally-gray line sample. Naming each with its own thickness (matching the chart's own
    /// emphasized/subdued line widths) reads more clearly than color alone here.
    private var legend: some View {
        HStack(spacing: 16) {
            ForEach(Self.seriesOrder, id: \.self) { kind in
                let isEmphasized = kind == emphasized
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(isEmphasized ? Color.primary : Color.secondary)
                        .frame(width: isEmphasized ? 16 : 10, height: isEmphasized ? 3 : 1)
                    Text(kind.name)
                        .font(.caption2)
                        .foregroundStyle(isEmphasized ? .primary : .secondary)
                }
            }
            Spacer()
        }
    }
}
