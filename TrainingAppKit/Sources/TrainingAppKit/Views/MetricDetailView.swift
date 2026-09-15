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

/// One metric's own detail screen (MVP1-45), Apple Health-style, top to bottom: the metric's own
/// name+abbreviation as a small secondary title, the touched day's own value in a large bold
/// number (with unit, if the metric has one — and, for Form, that day's own TSB zone label at the
/// same large size right next to the value), the day's own date underneath, that metric's own
/// trend chart in a plain white band stretching the full width (not a rounded card — the chart
/// itself keeps its own inset), the touched day's own zone explanation immediately below the chart
/// for Form only, and finally an "About `name`" card in a rounded, grouped-list-style rectangle
/// headed by a plain title sitting above it (not inside it). All in one `ScrollView`, no `List` —
/// a `List`'s per-row insets and separators don't fit this full-bleed-chart layout, and a plain
/// `ScrollView` is what a future dashboard screen embedding this same content (this view takes no
/// sheet-specific dependencies — no dismiss action, no navigation title) will want anyway.
///
/// A later "Options" section (e.g. jumping to the athlete's own zone settings) would be a further
/// sibling appended after `aboutSection` in `body`'s `VStack`, below this same scroll content.
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

    /// `touchedMetrics`'s own TSB zone, for Form only — `nil` for every other kind, and for Form
    /// itself when `touchedMetrics` isn't loaded yet.
    private var touchedZone: TSBZone? {
        guard kind == .form else { return nil }
        return touchedMetrics?.tsbZone()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    kindTitle
                    valueHeader
                }
                .padding(.horizontal)
                chartCard
                if kind == .form, let touchedZone {
                    Text(touchedZone.explanation)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                aboutSection
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(metricDetailBackground)
    }

    /// Replaces the sheet's own navigation title (MVP1-45 review: no toolbar/Done button on this
    /// screen at all) — the same "Form (TSB)" text a `.navigationTitle` would have shown, just
    /// inline above the value instead, secondary-colored and a step smaller than the value's own
    /// `.title3` unit/date text so the hierarchy reads value > date > this title.
    private var kindTitle: some View {
        Text("\(kind.name) (\(kind.abbreviation))")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private var valueHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(touchedValueText)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    if let unit = kind.unit {
                        Text(unit)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                // The touched day's own TSB zone, at the same size as Load's unit would be, but
                // `.primary` -- naming the zone is as central to reading Form's value as the
                // number itself, not a secondary annotation.
                if let touchedZone {
                    Text(touchedZone.label)
                        .font(.title3.weight(.semibold))
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

    /// "About `name`" as a plain title sitting above the rounded card, not inside it — matching
    /// how a grouped `List` section's own header reads, without actually using a `List`.
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About \(kind.name)")
                .font(.headline)
            Text(kind.explanation)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(metricDetailAboutCardBackground)
                }
        }
    }
}
