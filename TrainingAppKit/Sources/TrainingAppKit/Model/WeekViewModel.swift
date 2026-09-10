import Foundation
import TrainingCore

/// Drives the week view (design doc §2.1): which week is displayed, the 3-week window the
/// CTL/ATL/TSB chart shows, and the day-by-day activities/plans below it.
///
/// Reads `model.activities`/`plans`/`metrics` directly rather than caching its own copies, so it
/// always reflects whatever `TrainingModel.load(in:)`/`recompute` last produced — this view model
/// only owns the "which week" navigation state, not the training data itself.
@Observable
@MainActor
public final class WeekViewModel {
    private let model: TrainingModel
    private let refresher: any ActivityRefreshing
    private let calendar: Calendar
    /// Computes ``trainingLoad(for:)`` — the same default calculators `ActivityDetailViewModel`
    /// uses, so a card's headline Load number always agrees with the detail sheet's own figure.
    private let statisticsCalculator = StatisticsCalculator()
    /// Memoizes ``sportStatsPages(asOf:)`` — see that method's own doc comment for why this exists.
    /// `@ObservationIgnored` since it's a pure implementation-detail cache, not user-facing state;
    /// writing to it shouldn't itself trigger a view update.
    @ObservationIgnored
    private var sportStatsPagesCache: (weekStart: Date, activityCount: Int, today: Date, pages: [SportStatsPage])?
    /// Memoizes ``heartRateHistogram()`` — see that method's own doc comment for why this exists.
    @ObservationIgnored
    private var heartRateHistogramCache: (weekStart: Date, activityCount: Int, histogram: HeartRateHistogram)?

    /// The first day (in the athlete's timezone, respecting `weekStartsOn`) of the week currently
    /// on screen.
    public private(set) var displayedWeekStart: Date
    /// `true` while a pull-to-refresh import is in flight.
    public private(set) var isRefreshing = false
    /// `true` while a full resync (the athlete screen's "Force Full Resync" action) is in flight.
    /// Kept separate from ``isRefreshing`` so the two actions' spinners never conflate — the
    /// athlete screen's own button state shouldn't flip just because a pull-to-refresh happens to
    /// be running underneath it, or vice versa.
    public private(set) var isResyncing = false
    /// `true` while the athlete screen's "Deduplicate Activities" action is in flight. Kept
    /// separate from ``isRefreshing``/``isResyncing`` for the same reason those two are kept
    /// separate from each other.
    public private(set) var isDeduplicating = false

    /// Creates a week view model showing the week containing `today`.
    public init(model: TrainingModel, refresher: any ActivityRefreshing, today: Date = .now) {
        self.model = model
        self.refresher = refresher
        let calendar = Self.calendar(for: model.athlete)
        self.calendar = calendar
        self.displayedWeekStart = Self.weekStart(containing: today, calendar: calendar)
    }

    /// `true` while no HealthKit import has yet completed for this athlete — the empty-state
    /// trigger (design doc §2.1).
    ///
    /// Deliberately keyed on `model.hasEverImportedActivities`, not `model.activities.isEmpty`:
    /// the latter only reflects whatever range was last loaded (``chartRange``, the 3 weeks around
    /// ``displayedWeekStart``), so an athlete who connected and has real training history outside
    /// that window would otherwise see the "Connect Health Data" prompt again instead of their
    /// (empty-for-this-week) calendar.
    public var hasNoActivities: Bool {
        !model.hasEverImportedActivities
    }

    /// The athlete's timezone — views should format every date they show with this, not the
    /// device's default, so displayed dates agree with how `displayedWeekStart`/`weekDates` were
    /// actually computed.
    public var athleteTimeZone: TimeZone {
        model.athlete.timeZone
    }

    /// The athlete's calendar (timezone + `weekStartsOn` applied) — used to keep the "Select Date"
    /// picker's own week-row layout consistent with how `displayedWeekStart`/`weekDates` are
    /// actually computed, not the device's locale default.
    public var athleteCalendar: Calendar {
        calendar
    }

    /// The 7 days of the displayed week, starting `displayedWeekStart`.
    public var weekDates: [Date] {
        weekDates(offsetWeeks: 0)
    }

    /// The 7 days of the week `weeks` weeks away from ``displayedWeekStart`` (negative for
    /// earlier, positive for later), without changing ``displayedWeekStart`` itself.
    ///
    /// Lets a view render the neighboring weeks (e.g. to peek during a swipe) purely from data
    /// already covered by ``chartRange`` — no navigation state changes, no separate load.
    public func weekDates(offsetWeeks weeks: Int) -> [Date] {
        let start = calendar.date(byAdding: .day, value: weeks * 7, to: displayedWeekStart) ?? displayedWeekStart
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// The 3-week range (the week before, the displayed week, the week after) the chart covers
    /// and `load(asOf:)` fetches.
    public var chartRange: ClosedRange<Date> {
        let start = calendar.date(byAdding: .day, value: -7, to: displayedWeekStart) ?? displayedWeekStart
        let end = calendar.date(byAdding: .day, value: 13, to: displayedWeekStart) ?? displayedWeekStart
        return start...end
    }

    /// `model.metrics` restricted to ``chartRange``, in day order.
    public var chartMetrics: [FitnessMetrics] {
        model.metrics
            .filter { chartRange.contains($0.day) }
            .sorted { $0.day < $1.day }
    }

    /// The date range of ``displayedWeekStart`` — the week currently visible in the day list, not
    /// necessarily today's. Used to highlight that week's background on the fitness chart, so the
    /// 3-week trend stays visually anchored to whichever week the athlete has scrolled to.
    public var displayedWeekRange: ClosedRange<Date> {
        let end = calendar.date(byAdding: .day, value: 7, to: displayedWeekStart) ?? displayedWeekStart
        return displayedWeekStart...end
    }

    /// The calendar week number of ``displayedWeekStart``, for the week view's title (MVP1-56).
    public var displayedWeekOfYear: Int {
        calendar.component(.weekOfYear, from: displayedWeekStart)
    }

    /// A short "Sep 8 – Sep 14, 2026" description of the displayed week, for the subtitle under
    /// ``displayedWeekOfYear`` (MVP1-56) — the year sits on the end date only, unless the week
    /// crosses a year boundary (e.g. "Dec 29, 2026 – Jan 4, 2027"), in which case both ends show
    /// their own year so the range doesn't read as if it were entirely in the later one.
    public var displayedWeekDateRangeDescription: String {
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: displayedWeekStart) ?? displayedWeekStart
        let bareFormat = Date.FormatStyle(calendar: calendar, timeZone: athleteTimeZone)
            .day().month(.abbreviated)
        let withYearFormat = bareFormat.year()
        let crossesYearBoundary = calendar.component(.year, from: displayedWeekStart)
            != calendar.component(.year, from: weekEnd)
        let startFormat = crossesYearBoundary ? withYearFormat : bareFormat
        return "\(displayedWeekStart.formatted(startFormat)) – \(weekEnd.formatted(withYearFormat))"
    }

    /// Completed activities on `day`, in start-time order.
    public func activities(on day: Date) -> [Activity] {
        model.activities
            .filter { calendar.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }

    /// Planned activities on `day` — including ones already reconciled to a completed activity,
    /// since the view renders that distinction itself rather than this method filtering it away.
    public func plans(on day: Date) -> [PlannedActivity] {
        model.plans
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// The workout a plan schedules, if still in the library.
    public func workout(for plan: PlannedActivity) -> StructuredWorkout? {
        model.workouts.first { $0.id == plan.workoutID }
    }

    /// `day`'s fitness metrics, if computed — `nil` before ``load(asOf:)`` has covered it (e.g.
    /// the first frame, before `.task` runs). Used by the day list's CTL/ATL/TSB pills (MVP1-40).
    public func metrics(on day: Date) -> FitnessMetrics? {
        model.metrics.first { calendar.isDate($0.day, inSameDayAs: day) }
    }

    /// One page per sport for the week view's stats pager (MVP1-52; design doc: "a weekly overview
    /// highlighting one sport's duration/distance/TRIMP … above the rest") — ``AthleteProfile/mainSport``
    /// always first, then every other sport with activity in the displayed week, most distance
    /// first (ties broken alphabetically) for a deterministic order. Always at least one page (the
    /// main sport's, zero-filled if it had no activity this week), so the pager never has nothing
    /// to show.
    ///
    /// Memoized on `(displayedWeekStart, model.activities.count, today's calendar day)`: `WeekView`
    /// calls this from its `weekContent` computed property, which SwiftUI re-evaluates on every
    /// `@State` change — including every touch-move frame of the *day list*'s own unrelated swipe
    /// gesture. Without a cache, each of those frames would redundantly re-run two full
    /// `periodStats` computations (one `LoadCalculator` invocation per activity, each) even though
    /// neither the displayed week nor the underlying data changed — the same class of freeze this
    /// codebase already fixed once for the day list itself (MVP1-19).
    public func sportStatsPages(asOf today: Date = .now) -> [SportStatsPage] {
        if let cache = sportStatsPagesCache,
            cache.weekStart == displayedWeekStart,
            cache.activityCount == model.activities.count,
            calendar.isDate(cache.today, inSameDayAs: today) {
            return cache.pages
        }
        let pages = computeSportStatsPages(asOf: today)
        sportStatsPagesCache = (displayedWeekStart, model.activities.count, today, pages)
        return pages
    }

    private func computeSportStatsPages(asOf today: Date) -> [SportStatsPage] {
        let current = periodStats(weekStart: displayedWeekStart, asOf: today)
        let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: displayedWeekStart) ?? displayedWeekStart
        let previous = periodStats(weekStart: previousWeekStart, asOf: today)

        let mainSport = model.athlete.mainSport
        let otherSports = current.bySport.keys
            .filter { $0 != mainSport }
            .sorted { lhs, rhs in
                let lhsDistance = current.bySport[lhs]?.distanceMeters ?? 0
                let rhsDistance = current.bySport[rhs]?.distanceMeters ?? 0
                return lhsDistance != rhsDistance ? lhsDistance > rhsDistance : lhs.displayName < rhs.displayName
            }
        let loadChangeFraction = Self.changeFraction(current.totalLoad - previous.totalLoad, of: previous.totalLoad)

        return ([mainSport] + otherSports).map { sport in
            let currentSport = current.bySport[sport] ?? Self.zeroSportStats(sport)
            let previousSport = previous.bySport[sport] ?? Self.zeroSportStats(sport)
            return SportStatsPage(
                sport: sport,
                distanceMeters: currentSport.distanceMeters,
                time: currentSport.time,
                distanceChangeFraction: Self.changeFraction(
                    currentSport.distanceMeters - previousSport.distanceMeters, of: previousSport.distanceMeters
                ),
                timeChangeFraction: Self.changeFraction(currentSport.time - previousSport.time, of: previousSport.time),
                load: current.totalLoad,
                loadChangeFraction: loadChangeFraction
            )
        }
    }

    /// Descriptive totals (every sport, not just one) for the calendar week starting `weekStart` —
    /// shared by ``sportStatsPages(asOf:)`` for both the displayed week and the previous one.
    private func periodStats(weekStart: Date, asOf today: Date) -> PeriodStats {
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return statisticsCalculator.periodStats(
            activities: model.activities,
            plans: model.plans,
            workouts: model.workouts,
            athlete: model.athlete,
            range: weekStart...weekEnd,
            asOf: today,
            previous: nil
        )
    }

    private static func zeroSportStats(_ sport: Sport) -> SportPeriodStats {
        SportPeriodStats(sport: sport, distanceMeters: 0, time: 0, load: 0, timeInZone: TimeInZone(), activityCount: 0)
    }

    /// Unlike `PeriodDelta` (which reports 0 for a zero previous total, to avoid `.nan`), this
    /// reports `.infinity` instead — going from no activity to some really is an unbounded
    /// increase, and the stats pager renders that case as "+∞%" explicitly rather than showing a
    /// misleadingly literal "+0%" for what's actually the biggest possible jump. `previousTotal ==
    /// 0` only reports 0 when `delta` (== the current total, since `previousTotal` is 0) is also 0
    /// — no activity in either week is genuinely "no change", not an infinite one.
    private static func changeFraction(_ delta: Double, of previousTotal: Double) -> Double {
        guard previousTotal != 0 else { return delta == 0 ? 0 : .infinity }
        return delta / previousTotal
    }

    /// `activity`'s training load (TRIMP), computed the same way ``activityDetailViewModel(for:)``
    /// does — the day list's activity cards show this as their headline number (MVP1-41). `nil`
    /// when no calculator could score the activity (`confidence == 0`), so the card shows nothing
    /// rather than a misleading "0".
    public func trainingLoad(for activity: Activity) -> Double? {
        let summary = statisticsCalculator.summary(for: activity, athlete: model.athlete)
        return summary.load.confidence > 0 ? summary.load.value : nil
    }

    /// The displayed week's heart-rate histogram, for the graph panel's "Time in zone" page
    /// (MVP1-55) — every completed activity in the displayed week's raw heart-rate samples,
    /// binned by `HeartRateHistogram.aggregating(_:athlete:)`.
    ///
    /// Memoized on `(displayedWeekStart, model.activities.count)`, the same pattern
    /// ``sportStatsPages(asOf:)`` uses and for the same reason: `WeekView` re-evaluates this from a
    /// `@State` change on every touch-move frame of the day list's own swipe gesture, and each call
    /// would otherwise re-walk every sample of every activity in the displayed week on every one
    /// of those frames.
    public func heartRateHistogram() -> HeartRateHistogram {
        if let cache = heartRateHistogramCache,
            cache.weekStart == displayedWeekStart,
            cache.activityCount == model.activities.count {
            return cache.histogram
        }
        let weekActivities = weekDates.flatMap { activities(on: $0) }
        let histogram = HeartRateHistogram.aggregating(weekActivities, athlete: model.athlete)
        heartRateHistogramCache = (displayedWeekStart, model.activities.count, histogram)
        return histogram
    }

    /// `true` if `day` is `today`'s calendar day in the athlete's timezone — used by the day
    /// list's weekday pills (MVP1-39) to highlight today's row.
    public func isToday(_ day: Date, asOf today: Date = .now) -> Bool {
        calendar.isDate(day, inSameDayAs: today)
    }

    /// The detail view model for `activity`, pushed when it's tapped in the day list.
    public func activityDetailViewModel(for activity: Activity) -> ActivityDetailViewModel {
        ActivityDetailViewModel(activity: activity, athlete: model.athlete)
    }

    /// The view model for the athlete account screen, presented from the week view's toolbar.
    public var athleteViewModel: AthleteViewModel {
        AthleteViewModel(athlete: model.athlete)
    }

    /// Moves the displayed week forward by one week.
    public func goToNextWeek() {
        displayedWeekStart = calendar.date(byAdding: .day, value: 7, to: displayedWeekStart) ?? displayedWeekStart
    }

    /// Moves the displayed week back by one week.
    public func goToPreviousWeek() {
        displayedWeekStart = calendar.date(byAdding: .day, value: -7, to: displayedWeekStart) ?? displayedWeekStart
    }

    /// Jumps back to the week containing `today`.
    public func goToToday(asOf today: Date = .now) {
        goToWeek(containing: today)
    }

    /// Jumps to the week containing `date` — the "Select Date" toolbar action's destination,
    /// for an arbitrary date rather than today's.
    public func goToWeek(containing date: Date) {
        displayedWeekStart = Self.weekStart(containing: date, calendar: calendar)
    }

    /// Loads ``chartRange`` from the stores into `model`. Errors are swallowed — a failed load
    /// leaves `model` exactly as it was (`TrainingModel.load(in:)`'s own guarantee), so there's
    /// nothing for the view to reconcile; MVP 1 has no load-failure UI.
    public func load(asOf today: Date = .now) async {
        try? await model.load(in: chartRange, asOf: today)
    }

    /// Runs a pull-to-refresh import via `refresher`. `TrainingModel.importActivities(from:)`
    /// already reloads `activities` and recomputes `metrics` for whatever range was last loaded
    /// (``chartRange``, assuming ``load(asOf:)`` already ran once for it), so nothing further is
    /// needed here. Failures fail silently back to the pre-refresh state (design doc §3.4).
    public func refresh(asOf today: Date = .now) async {
        isRefreshing = true
        defer { isRefreshing = false }
        try? await refresher.refreshActivities(asOf: today)
    }

    /// The empty-state "Connect Health data" action (design doc §2.1): requests authorization,
    /// then runs the same import ``refresh(asOf:)`` does. Failures fail silently, same as
    /// ``refresh(asOf:)`` — MVP 1 has no error UI, and the empty state simply stays empty.
    public func connectHealthData(asOf today: Date = .now) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await refresher.requestAuthorization()
            try await refresher.refreshActivities(asOf: today)
        } catch {
            return
        }
    }

    /// The athlete screen's "Force Full Resync" action (design doc §2.3): re-imports every
    /// matching activity from scratch via `refresher.resyncActivities(asOf:)`, so a mapping fix
    /// (e.g. a `Sport` case that used to fall back to `.other`) reaches activities that were
    /// already imported before the fix — `Sport` is resolved once at import time and persisted,
    /// not recomputed on read. Failures fail silently, same as ``refresh(asOf:)`` — MVP 1 has no
    /// error UI.
    public func resyncActivities(asOf today: Date = .now) async {
        isResyncing = true
        defer { isResyncing = false }
        try? await refresher.resyncActivities(asOf: today)
    }

    /// The athlete screen's "Deduplicate Activities" action (MVP1-44): removes duplicate
    /// `Activity` records left over from before the concurrent-import race that produced them was
    /// fixed (MVP1-26) — including duplicates already synced to CloudKit before that fix, which
    /// deleting and reinstalling the app doesn't clear on its own. Goes straight through `model`
    /// rather than `refresher`, since this is a plain store cleanup with no `ActivityImporting`
    /// dependency. Failures fail silently, same as ``resyncActivities(asOf:)`` — MVP 1 has no
    /// error UI.
    public func deduplicateActivities(asOf today: Date = .now) async {
        isDeduplicating = true
        defer { isDeduplicating = false }
        try? await model.deduplicateActivities(asOf: today)
    }

    static func calendar(for athlete: AthleteProfile) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        calendar.firstWeekday = athlete.weekStartsOn.rawValue
        // ISO-8601's rule, not Foundation's Gregorian default (1): a week belongs to a year only
        // if at least 4 of its days fall in that year. Without this, `displayedWeekOfYear` (MVP1-56)
        // disagrees with the week number every other fitness platform shows near a year boundary —
        // e.g. Foundation's default calls the Mon–Sun week containing a Sunday Jan 1 "week 1" of the
        // new year, while ISO-8601 (and the athlete's expectation) calls it week 52/53 of the one
        // before it.
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }
}
