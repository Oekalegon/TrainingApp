import SwiftUI
import TrainingCore

/// What `MetricDetailView` needs to draw one metric's own chart and read its subject's value
/// (MVP1-45/MVP1-60).
struct MetricChartContext {
    /// The 3-week window `WeekViewModel.chartMetrics(for:)` returns for the week containing
    /// `subject` — the same data `FitnessChartView`/`DailyLoadChartView` plot for the main week
    /// graph, so the numbers agree between the two places they're shown. Used only to seed the
    /// screen's first paint before `metricsProvider` fetches its own, wider buffer.
    let metrics: [FitnessMetrics]
    /// A specific day (a day-list pill tap) or a whole displayed week (a graph-panel tap) — see
    /// `MetricDetailSubject`'s own doc comment.
    let subject: MetricDetailSubject
    /// The athlete's own calendar — matching `subject` against `metrics` needs
    /// `calendar.isDate(_:inSameDayAs:)`, not `==`, the same reasoning `WeekViewModel.metrics(on:)`
    /// already documents for the same comparison. Also supplies `calendar.timeZone` for formatting.
    let calendar: Calendar

    /// The single date `ChartPanState`/`ChartPeriod.range(around:)` anchor around — the tapped day
    /// itself, or a week subject's own start (so `period.range(around:)`'s "+7 days forward" reach
    /// lands close to that week's own end, the same way a day subject's does relative to the day
    /// tapped).
    var anchorDate: Date {
        switch subject {
        case .day(let day): return day
        case .week(let range): return range.lowerBound
        }
    }
}

/// One metric's own detail screen (MVP1-45/MVP1-60), Apple Health-style: `WeekView` pushes this
/// onto its own `NavigationStack` (`.navigationDestination(item:)`) when a day-list pill or the
/// graph panel itself is tapped — a real back button and push transition, not a dismiss-by-swiping
/// `.sheet`, since this is a full detail screen (chart + explanation + zone card) rather than a
/// quick modal glance. `.navigationTitle` names the metric (e.g. "Form (TSB)") in the nav bar
/// itself, so the scroll content below doesn't repeat it. Top to bottom: a period-picker segmented
/// control first — reachable immediately, before scrolling past anything else — then
/// `chartContext.subject`'s own value in a large bold number (and, for Form, its own TSB zone
/// label at the same large size right next to the value — `abbreviation` in the nav title already
/// covers what a unit would otherwise say, e.g. "TRIMP" for Load) with its own date/date-range
/// underneath, that metric's own trend chart in a plain white band stretching the full width (not a
/// rounded card — the chart itself keeps its own inset), the subject's own zone name+explanation
/// card for Form only, and finally an "About `name`" card — each of those last two a title sitting
/// above a rounded, grouped-list-style rectangle, not inside it. All in one `ScrollView`, no `List`
/// — a `List`'s per-row insets and separators don't fit this full-bleed-chart layout, and a plain
/// `ScrollView` is what a future dashboard screen embedding this same content will want anyway.
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
    /// `ChartPanState.bufferRange(around:period:calendar:)`), so dragging the chart can pan the
    /// visible window without waiting on a refetch each time. Seeded from `chartContext.metrics`
    /// for an instant first paint, then replaced by a proper buffer fetched via `metricsProvider`
    /// once `.task(id: period)` runs.
    @State private var displayedMetrics: [FitnessMetrics]
    /// The chart's own pan/anchor/buffer-window state — a plain, testable type (see its own doc
    /// comment) rather than a handful of parallel `@State` vars living directly on this view.
    @State private var panState: ChartPanState
    /// Live, uncommitted translation from an in-progress pan gesture — added on top of
    /// `panState.anchorDate` only while the drag is active, and folded into it once the drag ends
    /// (`commitPan(translation:)`). A plain `@State` (not `@GestureState`) so `onEnded` can read the
    /// final value after the gesture has already reset the `@GestureState` back to zero.
    @State private var dragTranslation: CGFloat = 0
    /// The most recent background buffer fetch, if any — cancelled and replaced by each new one
    /// (`.task(id: period)` or a pan landing near `panState.loadedRange`'s own edge) so two
    /// overlapping fetches can never race to overwrite `displayedMetrics`/`panState.loadedRange`
    /// with a stale result: whichever fetch starts last cancels every earlier one, and
    /// `loadBuffer(around:)` itself checks `Task.isCancelled` before writing, so a cancelled
    /// fetch's result is simply dropped even if `metricsProvider` still runs it to completion.
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
        self._panState = State(
            initialValue: ChartPanState(
                anchorDate: chartContext.anchorDate,
                loadedRange: ChartDayDomain.range(for: chartContext.metrics)
            )
        )
    }

    private static let unsignedValueFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
    private static let signedValueFormat = FloatingPointFormatStyle<Double>.number
        .sign(strategy: .always()).precision(.fractionLength(0))

    private var periodRange: ClosedRange<Date> {
        period.range(around: panState.anchorDate, calendar: chartContext.calendar)
    }

    /// The chart's actual on-screen window — `periodRange` re-centered on wherever an in-progress
    /// drag currently sits, so the plotted range moves continuously with the finger rather than
    /// only jumping once the gesture ends.
    private var visibleRange: ClosedRange<Date> {
        let liveAnchor = panState.panAnchor(for: dragTranslation, period: period, calendar: chartContext.calendar)
        return period.range(around: liveAnchor, calendar: chartContext.calendar)
    }

    /// Commits an ended pan gesture's final translation into `panState.anchorDate`, then tops up
    /// the loaded buffer in the background if that landed close enough to `loadedRange`'s own edge
    /// that another pan the same way would run out of data.
    private func commitPan(translation: CGFloat) {
        panState.anchorDate = panState.panAnchor(for: translation, period: period, calendar: chartContext.calendar)
        dragTranslation = 0
        let margin = period.lookbackDays / 4
        guard
            let earlyWarning = chartContext.calendar.date(byAdding: .day, value: margin, to: panState.loadedRange.lowerBound),
            let lateWarning = chartContext.calendar.date(byAdding: .day, value: -margin, to: panState.loadedRange.upperBound),
            periodRange.lowerBound < earlyWarning || periodRange.upperBound > lateWarning
        else { return }
        reloadBuffer(around: panState.anchorDate)
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
        let buffer = panState.bufferRange(around: anchor, period: period, calendar: chartContext.calendar)
        let metrics = await metricsProvider(buffer)
        guard !Task.isCancelled else { return }
        displayedMetrics = metrics
        panState.loadedRange = buffer
    }

    /// `chartContext.subject`'s own metrics points — the single day's point for a `.day` subject
    /// (`nil`/empty if that day isn't in `displayedMetrics` yet), or every point inside a `.week`
    /// subject's own range (used to average, below).
    private var subjectMetrics: [FitnessMetrics] {
        switch chartContext.subject {
        case .day(let day):
            return displayedMetrics.filter { chartContext.calendar.isDate($0.day, inSameDayAs: day) }
        case .week(let range):
            // A half-open comparison, not `range.contains(_:)` -- `range` itself
            // (`WeekViewModel.displayedWeekRange(for:)`) is `weekStart...weekStart+7days`, so a
            // `ClosedRange`'s inclusive upper bound would wrongly pull in the *next* week's own
            // point for whichever day happens to land exactly on that boundary.
            return displayedMetrics.filter { $0.day >= range.lowerBound && $0.day < range.upperBound }
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

    /// `subjectMetrics`'s own value for `kind` — that single day's value for a `.day` subject, or
    /// the plain mean across the week for a `.week` one. `nil` when nothing's loaded yet.
    private var subjectValue: Double? {
        let values = subjectMetrics.map { value(for: kind, in: $0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// "42" for a single day, "Avg 42" for a week -- the averaging itself needs no separate
    /// disclosure (a week obviously isn't one day's own reading), but the label makes clear this
    /// number isn't the same kind of reading as a day subject's own value.
    private var subjectValueText: String {
        guard let subjectValue else { return "–" }
        let format = kind == .form ? Self.signedValueFormat : Self.unsignedValueFormat
        let formatted = subjectValue.formatted(format)
        switch chartContext.subject {
        case .day: return formatted
        case .week: return "Avg \(formatted)"
        }
    }

    private var subjectDateText: String {
        switch chartContext.subject {
        case .day(let day):
            var format = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day().year()
            format.calendar = chartContext.calendar
            format.timeZone = chartContext.calendar.timeZone
            return day.formatted(format)
        case .week(let range):
            // The week's own last actual day (`range.upperBound` is the *next* week's start -- see
            // `subjectMetrics`'s own doc comment) through a full "weekday, month day, year" format
            // would repeat the year twice for a week that doesn't cross one -- a plain "Sep 14 – Sep
            // 20, 2026" range reads better here than either duplicating or omitting it conditionally.
            var format = Date.FormatStyle.dateTime.month(.abbreviated).day()
            format.calendar = chartContext.calendar
            format.timeZone = chartContext.calendar.timeZone
            let yearFormat = format.year()
            let lastDay = chartContext.calendar.date(byAdding: .day, value: -1, to: range.upperBound) ?? range.lowerBound
            return "\(range.lowerBound.formatted(format)) – \(lastDay.formatted(yearFormat))"
        }
    }

    /// `subjectValue`'s own TSB zone, for Form only — `nil` for every other kind, and for Form
    /// itself when `subjectValue` isn't loaded yet.
    private var subjectZone: TSBZone? {
        guard kind == .form, let subjectValue else { return nil }
        return TSBZone(tsb: subjectValue)
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
            panState.anchorDate = chartContext.anchorDate
            reloadBuffer(around: chartContext.anchorDate)
        }
    }

    private var valueHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(subjectValueText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                // The subject's own TSB zone, at the same size the Form value's own unit would be
                // if it had one, but `.primary` -- naming the zone is as central to reading Form's
                // value as the number itself, not a secondary annotation.
                if let subjectZone {
                    Text(subjectZone.label)
                        .font(.title3.weight(.semibold))
                }
            }
            Text(subjectDateText)
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
                        .onAppear { panState.chartWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, newValue in panState.chartWidth = newValue }
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
                period: period,
                subject: chartContext.subject,
                calendar: chartContext.calendar
            )
        case .fitness, .fatigue, .form:
            FitnessTrendDetailChartView(
                metrics: displayedMetrics,
                visibleRange: visibleRange,
                period: period,
                emphasized: kind,
                subject: chartContext.subject,
                calendar: chartContext.calendar
            )
        }
    }

    /// The subject's own TSB zone name+explanation, Form only — a plain title (the zone's own
    /// name, e.g. "Training") above a rounded card, the same "title above, not inside" treatment
    /// `aboutSection` uses below it.
    @ViewBuilder
    private var formZoneSection: some View {
        if kind == .form, let subjectZone {
            infoCard(title: subjectZone.label, body: subjectZone.explanation)
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
