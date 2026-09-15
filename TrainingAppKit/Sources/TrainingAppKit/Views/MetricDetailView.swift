import SwiftUI
import TrainingCore

/// What `MetricDetailView` needs to draw one metric's own chart and read its touched day's value
/// (MVP1-45).
struct MetricChartContext {
    /// The 3-week window `WeekViewModel.chartMetrics(for:)` returns for the week containing
    /// `touchedDay` — the same data `FitnessChartView`/`DailyLoadChartView` plot for the main week
    /// graph, so the numbers agree between the two places they're shown. Used only to seed the
    /// screen's first paint before `metricsProvider` fetches its own, wider buffer.
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

/// One metric's own detail screen (MVP1-45), Apple Health-style: `WeekView` pushes this onto its
/// own `NavigationStack` (`.navigationDestination(item:)`) when a day-list pill is tapped — a real
/// back button and push transition, not a dismiss-by-swiping `.sheet`, since this is a full detail
/// screen (chart + explanation + zone card) rather than a quick modal glance. `.navigationTitle`
/// names the metric (e.g. "Form (TSB)") in the nav bar itself, so the scroll content below doesn't
/// repeat it. Top to bottom: a period-picker segmented control first — reachable immediately,
/// before scrolling past anything else — then the touched day's own value in a large bold number
/// (and, for Form, that day's own TSB zone label at the same large size right next to the value —
/// `abbreviation` in the nav title already covers what a unit would otherwise say, e.g. "TRIMP" for
/// Load), the day's own date underneath, that metric's own trend
/// chart in a plain white band stretching the full width (not a rounded card — the chart itself
/// keeps its own inset), the touched day's own zone name+explanation card for Form only, and
/// finally an "About `name`" card — each of those last two a title sitting above a rounded,
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
    /// separate pushes rather than resetting to `.week` every time a different pill is tapped.
    @Binding var period: ChartPeriod
    /// Fetches (and, if needed, loads) metrics for an arbitrary range — `WeekViewModel.metrics(in:asOf:)`
    /// in practice. Called for every period, including `.week`, since the chart's own swipe-to-pan
    /// (MVP1-45) needs a buffer wider than `chartContext.metrics` alone provides.
    let metricsProvider: (ClosedRange<Date>) async -> [FitnessMetrics]

    /// What the chart actually renders from — always a wider buffer than what's on screen (see
    /// `bufferRange(around:)`), so dragging the chart can pan the visible window without waiting on
    /// a refetch each time. Seeded from `chartContext.metrics` for an instant first paint, then
    /// replaced by a proper buffer fetched via `metricsProvider` once `.task(id: period)` runs.
    @State private var displayedMetrics: [FitnessMetrics]
    /// The range currently loaded into `displayedMetrics` — a pan gesture is clamped so the visible
    /// window it produces never steps outside this, since there's no data beyond it to show yet.
    @State private var loadedRange: ClosedRange<Date>
    /// The center date `periodRange`/`visibleRange` are built around — separate from
    /// `chartContext.touchedDay`, which stays fixed to the tapped day's own header value/date/zone
    /// no matter how far the chart itself is panned. Reset back to `touchedDay` whenever `period`
    /// changes, so switching periods always re-centers on the tapped day rather than wherever a
    /// previous pan left it.
    @State private var anchorDate: Date
    /// The chart's own rendered width in points, captured once via a `GeometryReader` behind
    /// `chartCard` — lets a pan gesture convert its pixel translation into a day offset at
    /// (approximately) the chart's own pixel-per-day scale, so the plotted line/bars track the
    /// finger at roughly 1:1 speed rather than lagging or overshooting it.
    @State private var chartWidth: CGFloat = 1
    /// Live, uncommitted translation from an in-progress pan gesture — added on top of `anchorDate`
    /// only while the drag is active, and folded into `anchorDate` itself once it ends
    /// (`commitPan(translation:)`). A plain `@State` (not `@GestureState`) so `onEnded` can read the
    /// final value after the gesture has already reset the `@GestureState` back to zero.
    @State private var dragTranslation: CGFloat = 0
    /// The most recent background buffer fetch, if any — cancelled and replaced by each new one
    /// (`.task(id: period)` or a pan landing near `loadedRange`'s own edge) so two overlapping
    /// fetches can never race to overwrite `displayedMetrics`/`loadedRange` with a stale result:
    /// whichever fetch starts last cancels every earlier one, and `loadBuffer(around:)` itself
    /// checks `Task.isCancelled` before writing, so a cancelled fetch's result is simply dropped
    /// even if `metricsProvider` still runs it to completion.
    @State private var bufferTask: Task<Void, Never>?

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
        self._loadedRange = State(initialValue: ChartDayDomain.range(for: chartContext.metrics))
        self._anchorDate = State(initialValue: chartContext.touchedDay)
    }

    private static let unsignedValueFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
    private static let signedValueFormat = FloatingPointFormatStyle<Double>.number
        .sign(strategy: .always()).precision(.fractionLength(0))

    /// A buffer three times as wide as `period`'s own range around `anchor` — one extra span's
    /// worth of history and future on top of what's actually shown, so a pan gesture has real room
    /// to move before it runs out of loaded data and has to wait on `metricsProvider` again.
    private func bufferRange(around anchor: Date) -> ClosedRange<Date> {
        let base = period.range(around: anchor, calendar: chartContext.calendar)
        let span = base.upperBound.timeIntervalSince(base.lowerBound)
        return base.lowerBound.addingTimeInterval(-span)...base.upperBound.addingTimeInterval(span)
    }

    /// Converts a drag gesture's horizontal translation into a clamped candidate `anchorDate` —
    /// shared by the live (in-progress) and committed (`onEnded`) cases so both agree on exactly
    /// where a given translation lands. Dragging right reveals the past (translation is positive,
    /// so the offset is negative — earlier), matching a plain scroll view's own "content follows
    /// the finger" feel.
    private func panAnchor(for translation: CGFloat) -> Date {
        guard chartWidth > 1, translation != 0 else { return anchorDate }
        let visibleSpanDays = periodRange.upperBound.timeIntervalSince(periodRange.lowerBound) / 86_400
        let daysPerPoint = visibleSpanDays / Double(chartWidth)
        let dayOffset = Int((-Double(translation) * daysPerPoint).rounded())
        let candidate = chartContext.calendar.date(byAdding: .day, value: dayOffset, to: anchorDate) ?? anchorDate
        return clamped(candidate)
    }

    /// Keeps `period.range(around:)` for the candidate anchor fully inside `loadedRange` — panning
    /// stops at the edge of what's actually loaded instead of revealing a blank chart beyond it.
    private func clamped(_ candidate: Date) -> Date {
        guard
            let earliestAllowed = chartContext.calendar.date(byAdding: .day, value: period.lookbackDays, to: loadedRange.lowerBound),
            let latestAllowed = chartContext.calendar.date(byAdding: .day, value: -7, to: loadedRange.upperBound),
            earliestAllowed <= latestAllowed
        else { return anchorDate }
        return min(max(candidate, earliestAllowed), latestAllowed)
    }

    private var periodRange: ClosedRange<Date> {
        period.range(around: anchorDate, calendar: chartContext.calendar)
    }

    /// The chart's actual on-screen window — `periodRange` re-centered on wherever an in-progress
    /// drag currently sits, so the plotted range moves continuously with the finger rather than
    /// only jumping once the gesture ends.
    private var visibleRange: ClosedRange<Date> {
        period.range(around: panAnchor(for: dragTranslation), calendar: chartContext.calendar)
    }

    /// Commits an ended pan gesture's final translation into `anchorDate`, then tops up the loaded
    /// buffer in the background if that landed close enough to `loadedRange`'s own edge that another
    /// pan the same way would run out of data.
    private func commitPan(translation: CGFloat) {
        anchorDate = panAnchor(for: translation)
        dragTranslation = 0
        let margin = period.lookbackDays / 4
        guard
            let earlyWarning = chartContext.calendar.date(byAdding: .day, value: margin, to: loadedRange.lowerBound),
            let lateWarning = chartContext.calendar.date(byAdding: .day, value: -margin, to: loadedRange.upperBound),
            periodRange.lowerBound < earlyWarning || periodRange.upperBound > lateWarning
        else { return }
        reloadBuffer(around: anchorDate)
    }

    /// Cancels whatever buffer fetch is already in flight and starts a fresh one for `anchor` —
    /// the single path both `.task(id: period)` and `commitPan(translation:)` go through, so a
    /// period change and a pan can never race each other either (only whichever call happens last
    /// survives; see `bufferTask`'s own doc comment).
    private func reloadBuffer(around anchor: Date) {
        bufferTask?.cancel()
        bufferTask = Task { await loadBuffer(around: anchor) }
    }

    /// Fetches a fresh buffer around `anchor` and applies it — unless this particular fetch has
    /// been cancelled (a newer one superseded it) by the time `metricsProvider` returns, in which
    /// case its result is simply dropped rather than clobbering whatever the newer fetch already
    /// applied. See `bufferTask`'s own doc comment for why this check is what actually prevents the
    /// race, not just cancelling the `Task` (cancellation alone doesn't stop `metricsProvider` from
    /// running to completion and returning a result).
    private func loadBuffer(around anchor: Date) async {
        let buffer = bufferRange(around: anchor)
        let metrics = await metricsProvider(buffer)
        guard !Task.isCancelled else { return }
        displayedMetrics = metrics
        loadedRange = buffer
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
            VStack(alignment: .leading, spacing: 0) {
                // Everything through the chart reads as one continuous white surface -- the nav
                // bar, picker, value/date header and chart band -- matching Apple Health's own
                // "white above, grouped cards below" split rather than the grouped background
                // running underneath the header too.
                VStack(alignment: .leading, spacing: 20) {
                    periodPicker
                        .padding(.horizontal)
                        .padding(.top)
                    valueHeader
                        .padding(.horizontal)
                    chartCard
                }
                .background(metricDetailChartCardBackground)
                VStack(alignment: .leading, spacing: 20) {
                    formZoneSection
                    aboutSection
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .background(metricDetailBackground)
        .navigationTitle("\(kind.name) (\(kind.abbreviation))")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(metricDetailChartCardBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .task(id: period) {
            anchorDate = chartContext.touchedDay
            reloadBuffer(around: chartContext.touchedDay)
        }
    }

    private var valueHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(touchedValueText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                // The touched day's own TSB zone, at the same size the Form value's own unit would
                // be if it had one, but `.primary` -- naming the zone is as central to reading
                // Form's value as the number itself, not a secondary annotation.
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
    /// keeps its own horizontal/vertical padding so it doesn't sit flush against the screen's edges
    /// even though the white fill behind it does. Swipable (MVP1-45): a horizontal drag pans the
    /// chart's own visible window — see `visibleRange`/`panAnchor(for:)` — without disturbing the
    /// enclosing `ScrollView`'s own vertical scrolling, since only a translation whose horizontal
    /// component dominates the vertical one is treated as a pan.
    private var chartCard: some View {
        detailChart
            .padding(.horizontal)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(metricDetailChartCardBackground)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { chartWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, newValue in chartWidth = newValue }
                }
            )
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        dragTranslation = value.translation.width
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else {
                            dragTranslation = 0
                            return
                        }
                        commitPan(translation: value.translation.width)
                    }
            )
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
            LoadDetailChartView(
                metrics: displayedMetrics,
                visibleRange: visibleRange,
                touchedDay: chartContext.touchedDay,
                calendar: chartContext.calendar
            )
        case .fitness, .fatigue, .form:
            FitnessTrendDetailChartView(
                metrics: displayedMetrics,
                visibleRange: visibleRange,
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
                // Matches the card's own `.padding()` below, so the title's leading edge lines up
                // with the body text inside the card rather than the card's own outer edge.
                .padding(.horizontal)
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
