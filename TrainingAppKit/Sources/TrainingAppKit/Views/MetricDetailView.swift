import SwiftUI
import TrainingCore

/// What `MetricDetailView`/`FitnessMetricsInfoView` need to draw one metric's own chart and read
/// its touched day's value (MVP1-45).
struct MetricChartContext {
    /// The 3-week window `WeekViewModel.chartMetrics(for:)` returns for the week containing
    /// `touchedDay` — the same data `FitnessChartView`/`DailyLoadChartView` plot for the main week
    /// graph, so the numbers agree between the two places they're shown.
    let metrics: [FitnessMetrics]
    /// The specific day whose pill was tapped — marked in the chart, and whose own value the big
    /// number header (and, for Form, the "current zone" explanation) reads from.
    let touchedDay: Date
    /// The athlete's own calendar — matching `touchedDay` against `metrics` needs
    /// `calendar.isDate(_:inSameDayAs:)`, not `==`, the same reasoning `WeekViewModel.metrics(on:)`
    /// already documents for the same comparison. Also supplies `calendar.timeZone` for formatting
    /// `touchedDay`.
    let calendar: Calendar
}

#if os(iOS)
private let metricDetailBackground = Color(.systemGroupedBackground)
private let metricDetailChartCardBackground = Color(.systemBackground)
private let metricDetailAboutCardBackground = Color(.secondarySystemGroupedBackground)
#else
// This view only ever ships on iOS; the fallback exists purely so TrainingAppKit (built for both
// iOS and macOS, per Package.swift) still compiles on macOS, e.g. for host-side tooling/tests.
private let metricDetailBackground = Color(white: 0.93)
private let metricDetailChartCardBackground = Color.white
private let metricDetailAboutCardBackground = Color(white: 0.97)
#endif

/// One metric's own detail screen (MVP1-45), Apple Health-style: the touched day's own value in a
/// large bold number (with unit, if the metric has one) and the day's own date underneath, then
/// that metric's own trend chart in a plain white band stretching the full width (not a rounded
/// card — the chart itself keeps its own inset), then an "About `name`" card in a rounded,
/// grouped-list-style rectangle. All in one `ScrollView`, no `List` — a `List`'s per-row insets and
/// separators don't fit this full-bleed-chart layout, and a plain `ScrollView` is what a future
/// dashboard screen embedding this same content (this view takes no sheet-specific dependencies —
/// no dismiss action, no navigation title) will want anyway.
///
/// A later "Options" section (e.g. jumping to the athlete's own zone settings) would be a further
/// sibling appended after `aboutCard` in `body`'s `VStack`, below this same scroll content.
struct MetricDetailView: View {
    let kind: TrainingMetricKind
    let chartContext: MetricChartContext

    private static let unsignedValueFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
    private static let signedValueFormat = FloatingPointFormatStyle<Double>.number
        .sign(strategy: .always()).precision(.fractionLength(0))

    /// `chartContext.touchedDay`'s own metrics point — `nil` if that day isn't in
    /// `chartContext.metrics` yet (not loaded).
    private var touchedMetrics: FitnessMetrics? {
        chartContext.metrics.first {
            chartContext.calendar.isDate($0.day, inSameDayAs: chartContext.touchedDay)
        }
    }

    private func value(for kind: TrainingMetricKind, in metrics: FitnessMetrics) -> Double {
        switch kind {
        case .load: metrics.load
        case .fitness: metrics.ctl
        case .fatigue: metrics.atl
        case .form: metrics.tsb
        }
    }

    private var touchedValueText: String {
        guard let touchedMetrics else { return "–" }
        let format = kind == .form ? Self.signedValueFormat : Self.unsignedValueFormat
        return value(for: kind, in: touchedMetrics).formatted(format)
    }

    private var touchedDayText: String {
        var format = Date.FormatStyle.dateTime.weekday(.wide).month(.abbreviated).day()
        format.calendar = chartContext.calendar
        format.timeZone = chartContext.calendar.timeZone
        return chartContext.touchedDay.formatted(format)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                valueHeader
                    .padding(.horizontal)
                chartCard
                aboutCard
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(metricDetailBackground)
    }

    private var valueHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(touchedValueText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                if let unit = kind.unit {
                    Text(unit)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(touchedDayText)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Full-bleed white band, not a rounded card — see this type's own doc comment. The chart
    /// keeps its own horizontal/vertical padding so its bars/lines don't sit flush against the
    /// sheet's edges even though the white fill behind it does.
    private var chartCard: some View {
        detailChart
            .padding(.horizontal)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(metricDetailChartCardBackground)
    }

    @ViewBuilder
    private var detailChart: some View {
        switch kind {
        case .load:
            LoadDetailChartView(
                metrics: chartContext.metrics,
                touchedDay: chartContext.touchedDay,
                calendar: chartContext.calendar
            )
        case .fitness, .fatigue, .form:
            FitnessTrendDetailChartView(
                metrics: chartContext.metrics,
                emphasized: kind,
                touchedDay: chartContext.touchedDay,
                calendar: chartContext.calendar
            )
        }
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About \(kind.name)")
                .font(.headline)
            Text(kind.explanation)
                .foregroundStyle(.secondary)
            if kind == .form, let touchedMetrics {
                Divider()
                formZoneExplanation(for: touchedMetrics)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(metricDetailAboutCardBackground)
        }
    }

    /// Deliberately plain (bold text, no zone color) — matching this view's own headers, which
    /// stay un-tinted even though the chart above (and the main week graph) shade this same zone
    /// in color; the color association lives in the chart, not repeated here in text.
    private func formZoneExplanation(for metrics: FitnessMetrics) -> some View {
        let zone = metrics.tsbZone()
        return VStack(alignment: .leading, spacing: 4) {
            Text("Currently: \(zone.label)")
                .font(.subheadline.bold())
            Text(zone.explanation)
                .foregroundStyle(.secondary)
        }
    }
}
