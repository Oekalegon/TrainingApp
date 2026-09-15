import Charts
import SwiftUI
import TrainingCore

/// The Load (TRIMP) metric detail screen's own daily-load chart (MVP1-45/MVP1-60) — the same
/// 3-week Daily Load data `DailyLoadChartView` plots (so paging between the two agrees), but with
/// `subject` highlighted in full `.primary` against every other day muted to `.secondary`, rather
/// than only distinguishing past (actual) from future (projected) bars. A still-projected day
/// still renders from its own estimated TRIMP rather than a blank bar, so a `.day` subject falling
/// on a still-planned day (or a `.week` subject spanning one) isn't left looking empty.
struct LoadDetailChartView: View {
    let metrics: [FitnessMetrics]
    /// The x-axis window to show -- `MetricDetailView`'s own `visibleRange`, which pans as the
    /// athlete drags across the chart (MVP1-45 swipe-to-scrub). `metrics` itself is a wider buffer
    /// than this, so panning can move the visible window without waiting on a refetch; anything
    /// outside `visibleRange` is still loaded, just clipped by `.chartPlotStyle`.
    let visibleRange: ClosedRange<Date>
    /// Which period is picked -- drives where `ChartAxisMarks` puts gridlines (week-start for
    /// Week/Month, month-start for 3M/6M, a fixed quarterly set of months for Year).
    let period: ChartPeriod
    /// A single day's own bar highlighted (MVP1-45), or every bar inside a whole week highlighted
    /// (MVP1-60) — see `MetricDetailSubject`'s own doc comment.
    let subject: MetricDetailSubject
    let calendar: Calendar

    private var loads: [DailyLoad] {
        DailyLoad.aggregating(metrics)
    }

    private var dayDomain: ClosedRange<Date> {
        let oneDay: TimeInterval = 24 * 60 * 60
        return visibleRange.lowerBound.addingTimeInterval(-oneDay)...visibleRange.upperBound.addingTimeInterval(oneDay)
    }

    private func isHighlighted(_ day: Date) -> Bool {
        switch subject {
        case .day(let touchedDay): return calendar.isDate(day, inSameDayAs: touchedDay)
        case .week(let range): return day >= range.lowerBound && day < range.upperBound
        }
    }

    var body: some View {
        Chart {
            ForEach(loads, id: \.day) { point in
                BarMark(x: .value("Day", point.day, unit: .day), y: .value("TRIMP", point.load))
                    .foregroundStyle(isHighlighted(point.day) ? Color.primary : Color.secondary.opacity(0.4))
            }
        }
        .chartXScale(domain: dayDomain)
        .chartXAxis {
            AxisMarks(values: ChartAxisMarks.dates(for: period, in: dayDomain, calendar: calendar)) { value in
                AxisGridLine()
                AxisTick()
                if let date = value.as(Date.self) {
                    AxisValueLabel(ChartAxisMarks.labelText(for: date, period: period, calendar: calendar))
                }
            }
        }
        .frame(height: 160)
    }
}

/// The Fitness/Fatigue/Form metric detail screen's own trend chart (MVP1-45) — the same 3-week
/// CTL/ATL/TSB data `FitnessChartView` plots, but with `emphasized` drawn as a thick `.primary`
/// line (matching that main chart's own smoothed-line treatment) and the other two subdued to a
/// thin line in their own muted color (`TrainingMetricKind.color`, at reduced opacity) — plain
/// `.secondary` for both would leave them indistinguishable from each other, since a legend text
/// label is the only other thing telling them apart. Uses a manual legend, not `.chartLegend`, so
/// that per-series color can be spelled out explicitly the same way.
///
/// `emphasized`'s own value range drives the y-domain — the other two series may run outside it,
/// and are clipped to the plot area (`.chartPlotStyle`) rather than bleeding into the surrounding
/// frame. The one exception is `.form`: since that's also the only case that shows `TSBZoneBand`
/// shading, it keeps that shading's own fixed domain instead (see `yDomain`'s own doc comment).
struct FitnessTrendDetailChartView: View {
    let metrics: [FitnessMetrics]
    /// The x-axis window to show -- `MetricDetailView`'s own `visibleRange`, which pans as the
    /// athlete drags across the chart (MVP1-45 swipe-to-scrub). `metrics` itself is a wider buffer
    /// than this, so panning can move the visible window without waiting on a refetch; anything
    /// outside `visibleRange` is still loaded, just clipped by `.chartPlotStyle`. `yDomain` fits
    /// only the values actually inside this window, not the whole buffer, so panning away from the
    /// touched day re-fits the y-axis to whatever's now on screen.
    let visibleRange: ClosedRange<Date>
    /// Which period is picked -- drives where `ChartAxisMarks` puts gridlines (week-start for
    /// Week/Month, month-start for 3M/6M, a fixed quarterly set of months for Year).
    let period: ChartPeriod
    /// Which of `.fitness`/`.fatigue`/`.form` to emphasize — `.load` never reaches this view (see
    /// `MetricDetailView`'s own dispatch).
    let emphasized: TrainingMetricKind
    /// A single day's own point highlighted (MVP1-45), or the whole displayed week highlighted
    /// (MVP1-60, the same week-band treatment `FitnessChartView`'s main graph already uses) — see
    /// `MetricDetailSubject`'s own doc comment.
    let subject: MetricDetailSubject
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

    private var visibleMetrics: [FitnessMetrics] {
        metrics.filter { visibleRange.contains($0.day) }
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
        let values = visibleMetrics.map { value(for: emphasized, in: $0) }
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

    /// The x-axis span `highlightMark` shades — a single day's own point ± 12 hours for a `.day`
    /// subject (a one-day-wide band centered on the day's own plotted point, rather than sitting at
    /// the left edge of a `day...(day + 1 day)` span), or the whole week's own range as-is for a
    /// `.week` subject. For `.day`, snaps to the real data point's own `day` value if `metrics` has
    /// one, rather than the tapped `Date` as-is -- keeping the mark pixel-aligned with that day's
    /// line points even if the tapped `Date` (built from `WeekViewModel`'s own day list) and
    /// `FitnessMetrics.day` (built inside TrainingKit) aren't bit-identical for the same calendar
    /// day.
    private var highlightRange: ClosedRange<Date> {
        switch subject {
        case .day(let touchedDay):
            let markedDay = metrics.first { calendar.isDate($0.day, inSameDayAs: touchedDay) }?.day ?? touchedDay
            let halfDay: TimeInterval = 12 * 60 * 60
            return markedDay.addingTimeInterval(-halfDay)...markedDay.addingTimeInterval(halfDay)
        case .week(let range):
            return range
        }
    }

    /// A background band marking the subject — one day wide for a `.day` subject, the whole week
    /// wide for a `.week` one — the same treatment (`Color.primary.opacity(0.1)`)
    /// `FitnessChartView`'s own week-highlight band uses, rather than a thin rule line.
    @ChartContentBuilder
    private var dayHighlightMark: some ChartContent {
        RectangleMark(
            xStart: .value("Highlight start", highlightRange.lowerBound),
            xEnd: .value("Highlight end", highlightRange.upperBound)
        )
        .foregroundStyle(Color.primary.opacity(0.1))
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

    /// The emphasized series draws full `.primary`; the other two draw in their own
    /// `TrainingMetricKind.color`, muted, so two subdued series don't collapse into one
    /// indistinguishable gray line — see this type's own doc comment.
    private func lineColor(for kind: TrainingMetricKind) -> Color {
        kind == emphasized ? .primary : kind.color.opacity(0.5)
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
            TrainingMetricKind.fitness.name: lineColor(for: .fitness),
            "\(TrainingMetricKind.fitness.name) (projected)": lineColor(for: .fitness),
            TrainingMetricKind.fatigue.name: lineColor(for: .fatigue),
            "\(TrainingMetricKind.fatigue.name) (projected)": lineColor(for: .fatigue),
            TrainingMetricKind.form.name: lineColor(for: .form),
            "\(TrainingMetricKind.form.name) (projected)": lineColor(for: .form),
        ])
        .chartXScale(domain: visibleRange)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: ChartAxisMarks.dates(for: period, in: visibleRange, calendar: calendar)) { value in
                AxisGridLine()
                AxisTick()
                if let date = value.as(Date.self) {
                    AxisValueLabel(ChartAxisMarks.labelText(for: date, period: period, calendar: calendar))
                }
            }
        }
        .chartYAxis {
            // Form's gridlines/labels sit at the zone boundaries, not an arbitrary evenly-spaced
            // stride -- matching `FitnessChartView`'s own Form chart, since the boundaries are the
            // one thing worth reading off this axis when zone bands are shown at all. Fitness/
            // Fatigue have no such reference, so they keep the default automatic axis.
            if emphasized == .form {
                AxisMarks(position: .trailing, values: TSBZoneBand.boundaries) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            } else {
                AxisMarks(position: .trailing)
            }
        }
        .chartLegend(.hidden)
        // Without this, a subdued series running past `yDomain` (by design -- only `emphasized`'s
        // own range fits it exactly) draws straight into the surrounding frame instead of stopping
        // at the plot area's own edge.
        .chartPlotStyle { plotContent in
            plotContent.clipped()
        }
        .chartOverlay { proxy in
            // The zone names, next to the boundary axis labels -- matching `FitnessChartView`'s
            // own Form chart, so the same zone reads the same way in both places. Only for Form:
            // Fitness/Fatigue show no zone bands, so there's nothing to name here for them.
            if emphasized == .form {
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
        }
        .frame(height: 200)
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
                        .fill(lineColor(for: kind))
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
