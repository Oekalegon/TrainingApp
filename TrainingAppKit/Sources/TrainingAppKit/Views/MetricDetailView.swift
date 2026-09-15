import SwiftUI
import TrainingCore

/// What `MetricDetailView`/`FitnessMetricsInfoView` need to draw one metric's own chart and read
/// its touched day's value (MVP1-45).
struct MetricChartContext {
    /// The 3-week window `WeekViewModel.chartMetrics(for:)` returns for the week containing
    /// `touchedDay` — the same data `FitnessChartView`/`DailyLoadChartView` plot for the main week
    /// graph, so the numbers agree between the two places they're shown. Used as-is for
    /// `ChartPeriod.week` (the default); a wider period re-fetches via `metricsProvider` instead.
    let metrics: [FitnessMetrics]
    /// The specific day whose pill was tapped — marked in the chart, and whose own value the big
    /// number header (and, for Form, the zone name/explanation) reads from.
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

/// One metric's own detail screen (MVP1-45), Apple Health-style, top to bottom: a period-picker
/// segmented control first (this is still a sheet, typically opening at `.medium` height, so the
/// range control needs to be reachable without scrolling past everything else first), then the
/// metric's own name+abbreviation as a secondary title, the touched day's own value in a large
/// bold number (with unit, if the metric has one — and, for Form, that day's own TSB zone label at
/// the same large size right next to the value), the day's own date underneath, that metric's own
/// trend chart in a plain white band stretching the full width (not a rounded card — the chart
/// itself keeps its own inset), the touched day's own zone name+explanation card for Form only,
/// and finally an "About `name`" card — each of those last two a title sitting above a rounded,
/// grouped-list-style rectangle, not inside it. All in one `ScrollView`, no `List` — a `List`'s
/// per-row insets and separators don't fit this full-bleed-chart layout, and a plain `ScrollView`
/// is what a future dashboard screen embedding this same content will want anyway.
///
/// A later "Options" section (e.g. jumping to the athlete's own zone settings) would be a further
/// sibling appended after `aboutSection` in `body`'s `VStack`, below this same scroll content.
struct MetricDetailView: View {
    let kind: TrainingMetricKind
    let chartContext: MetricChartContext
    /// The selected chart period — owned by `WeekView` (not this view), so it's retained across
    /// separate metric sheets rather than resetting to `.week` every time a different pill is
    /// tapped.
    @Binding var period: ChartPeriod
    /// Fetches (and, if needed, loads) metrics for an arbitrary range — `WeekViewModel.metrics(in:asOf:)`
    /// in practice. Not called for `.week`, which already has everything it needs in
    /// `chartContext.metrics`.
    let metricsProvider: (ClosedRange<Date>) async -> [FitnessMetrics]

    /// What the chart/value actually render from — `chartContext.metrics` until `period` picks
    /// something wider, at which point `.task(id: period)` below replaces this via
    /// `metricsProvider`.
    @State private var displayedMetrics: [FitnessMetrics]

    init(
        kind: TrainingMetricKind,
        chartContext: MetricChartContext,
        period: Binding<ChartPeriod>,
        metricsProvider: @escaping (ClosedRange<Date>) async -> [FitnessMetrics]
    ) {
        self.kind = kind
        self.chartContext = chartContext
        self._period = period
        self.metricsProvider = metricsProvider
        self._displayedMetrics = State(initialValue: chartContext.metrics)
    }

    private static let unsignedValueFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
    private static let signedValueFormat = FloatingPointFormatStyle<Double>.number
        .sign(strategy: .always()).precision(.fractionLength(0))

    private var periodRange: ClosedRange<Date> {
        period.range(around: chartContext.touchedDay, calendar: chartContext.calendar)
    }

    /// `chartContext.touchedDay`'s own metrics point — `nil` if that day isn't in
    /// `displayedMetrics` yet (not loaded).
    private var touchedMetrics: FitnessMetrics? {
        displayedMetrics.first {
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
                periodPicker
                    .padding(.horizontal)
                VStack(alignment: .leading, spacing: 12) {
                    kindTitle
                    valueHeader
                }
                .padding(.horizontal)
                chartCard
                formZoneSection
                aboutSection
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(metricDetailBackground)
        .task(id: period) {
            guard period != .week else {
                displayedMetrics = chartContext.metrics
                return
            }
            displayedMetrics = await metricsProvider(periodRange)
        }
    }

    /// Replaces the sheet's own navigation title (MVP1-45 review: no toolbar/Done button on this
    /// screen at all) — the same "Form (TSB)" text a `.navigationTitle` would have shown, just
    /// inline above the value instead. Bigger than `touchedDayText` below it (`.title3` vs.
    /// `.subheadline`) even though both are secondary-colored, so the hierarchy reads value >
    /// title > date rather than the date outweighing the title naming what's actually shown.
    private var kindTitle: some View {
        Text("\(kind.name) (\(kind.abbreviation))")
            .font(.title3.weight(.semibold))
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
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Full-bleed white band, not a rounded card — see this type's own doc comment. The chart
    /// keeps its own horizontal/vertical padding so it doesn't sit flush against the sheet's edges
    /// even though the white fill behind it does.
    private var chartCard: some View {
        detailChart
            .padding(.horizontal)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(metricDetailChartCardBackground)
    }

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(ChartPeriod.allCases) { period in
                Text(period.shortLabel).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var detailChart: some View {
        switch kind {
        case .load:
            LoadDetailChartView(metrics: displayedMetrics, touchedDay: chartContext.touchedDay, calendar: chartContext.calendar)
        case .fitness, .fatigue, .form:
            FitnessTrendDetailChartView(
                metrics: displayedMetrics,
                emphasized: kind,
                touchedDay: chartContext.touchedDay,
                calendar: chartContext.calendar
            )
        }
    }

    /// The touched day's own TSB zone name+explanation, Form only — a plain title (the zone's own
    /// name, e.g. "Training") above a rounded card, the same "title above, not inside" treatment
    /// `aboutSection` uses below it.
    @ViewBuilder
    private var formZoneSection: some View {
        if kind == .form, let touchedZone {
            infoCard(title: touchedZone.label, body: touchedZone.explanation)
                .padding(.horizontal)
        }
    }

    /// "About `name`" as a plain title sitting above the rounded card, not inside it — matching
    /// how a grouped `List` section's own header reads, without actually using a `List`.
    private var aboutSection: some View {
        infoCard(title: "About \(kind.name)", body: kind.explanation)
    }

    /// A plain title above a rounded, grouped-list-style card — shared by `formZoneSection` and
    /// `aboutSection` so the two read as the same kind of information block. `.primary`, not
    /// `.secondary`: this is the screen's actual explanatory content, not a caption.
    private func infoCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.bold))
            Text(body)
                .foregroundStyle(.primary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(metricDetailAboutCardBackground)
                }
        }
    }
}
