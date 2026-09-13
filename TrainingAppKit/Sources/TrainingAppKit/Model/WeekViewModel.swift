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

    /// Sport-stats pages, cached per week (keyed by that week's `weekStart`) — see
    /// ``sportStatsPages(for:asOf:)``'s own doc comment. Not `@ObservationIgnored`: `WeekView`
    /// reads this indirectly through that method, and needs the read tracked the same way a plain
    /// stored property's would be.
    private var sportStatsPagesCaches: [Date: [SportStatsPage]] = [:]
    /// `(model.activities.count, today)` as of the last time ``sportStatsPagesCaches`` was
    /// populated — either changing invalidates the whole cache (an import/dedup could change any
    /// cached week's activities, not just the displayed one, and a new calendar day shifts every
    /// week's own change-vs-previous-week percentages).
    @ObservationIgnored
    private var sportStatsPagesCachesKey: (activityCount: Int, today: Date)?

    /// Each week's heart-rate histogram, cached per week (keyed by that week's `weekStart`) — at
    /// most 3 entries (``displayedWeekStart`` and its immediate neighbors) at any time, refreshed
    /// by ``refreshWeekCachesIfNeeded()``. Not `@ObservationIgnored`, for the same reason as
    /// ``sportStatsPagesCaches``.
    private var weekGraphCaches: [Date: HeartRateHistogram] = [:]
    /// `model.activities.count` as of the last time ``weekGraphCaches`` was populated — see
    /// ``sportStatsPagesCachesKey``'s own doc comment for why a mismatch invalidates the whole
    /// cache rather than trying to single out which weeks actually changed.
    @ObservationIgnored
    private var weekGraphCachesActivityCount: Int?

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

    /// ``displayedWeekStart`` and its immediate neighbors — the window ``sportStatsPagesCaches``/
    /// ``weekGraphCaches`` keep cached, and the only weeks `WeekView`'s carousel ever shows at once.
    private var cachedWeekStarts: [Date] {
        [-7, 0, 7].compactMap { calendar.date(byAdding: .day, value: $0, to: displayedWeekStart) }
    }

    /// Completed activities in the 7-day week starting `weekStart` (which need not be
    /// ``displayedWeekStart``), in the same terms ``activities(on:)`` filters a single day by —
    /// used to compute an arbitrary cached week's own graph data.
    private func activities(forWeekStarting weekStart: Date) -> [Activity] {
        (0..<7)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
            .flatMap { activities(on: $0) }
    }

    /// The 3-week range (the week before, the displayed week, the week after) the chart covers
    /// and `load(asOf:)` fetches.
    public var chartRange: ClosedRange<Date> {
        Self.chartRange(for: displayedWeekStart, calendar: calendar)
    }

    /// The 3-week range `chartRange` would be if ``displayedWeekStart`` were `weekStart` instead —
    /// used by ``preload(weekStart:asOf:)`` to fetch a target week's data ahead of actually
    /// navigating there.
    private static func chartRange(for weekStart: Date, calendar: Calendar) -> ClosedRange<Date> {
        let start = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let end = calendar.date(byAdding: .day, value: 13, to: weekStart) ?? weekStart
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
    /// Convenience for ``displayedWeekStart``'s own pages — see ``sportStatsPages(for:asOf:)``'s
    /// own doc comment.
    public func sportStatsPages(asOf today: Date = .now) -> [SportStatsPage] {
        sportStatsPages(for: displayedWeekStart, asOf: today)
    }

    /// One page per sport for the given week's stats pager (MVP1-52; design doc: "a weekly overview
    /// highlighting one sport's duration/distance/TRIMP … above the rest") — ``AthleteProfile/mainSport``
    /// always first, then every other sport with activity that week, most distance first (ties
    /// broken alphabetically) for a deterministic order. Always at least one page (the main
    /// sport's, zero-filled if it had no activity that week), so the pager never has nothing to
    /// show.
    ///
    /// Cached per week (`weekStart`, not just ``displayedWeekStart``): `WeekView` calls this from
    /// each of its 3 carousel pages' own pinned stats bar, including the previous/next week's,
    /// which re-evaluate on every touch-move frame of the day list's own swipe gesture just like
    /// the current page does. Without a cache keyed per week, each of those frames on each page
    /// would redundantly re-run two full `periodStats` computations (one `LoadCalculator`
    /// invocation per activity, each) even though neither that page's own week nor the underlying
    /// data changed — the same class of freeze this codebase already fixed once for the day list
    /// itself (MVP1-19). The whole cache is invalidated together (not per week) whenever
    /// `model.activities.count` or `today`'s calendar day changes, since either can shift every
    /// cached week's own figures at once.
    public func sportStatsPages(for weekStart: Date, asOf today: Date = .now) -> [SportStatsPage] {
        let activityCount = model.activities.count
        let keyIsCurrent = sportStatsPagesCachesKey.map {
            $0.activityCount == activityCount && calendar.isDate($0.today, inSameDayAs: today)
        } ?? false
        if !keyIsCurrent {
            sportStatsPagesCaches.removeAll()
            sportStatsPagesCachesKey = (activityCount, today)
        }
        if let cached = sportStatsPagesCaches[weekStart] {
            return cached
        }
        let pages = computeSportStatsPages(weekStart: weekStart, asOf: today)
        sportStatsPagesCaches[weekStart] = pages
        return pages
    }

    private func computeSportStatsPages(weekStart: Date, asOf today: Date) -> [SportStatsPage] {
        let current = periodStats(weekStart: weekStart, asOf: today)
        let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
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

    /// `weekStart`'s heart-rate histogram, for the graph panel's "Heart Rate Histogram" page
    /// (MVP1-55) —
    /// every completed activity in that week's raw heart-rate samples, binned by
    /// `HeartRateHistogram.aggregating(_:athlete:)`. Empty until ``refreshWeekCachesIfNeeded()``
    /// has cached `weekStart` — in practice near-instant for ``displayedWeekStart`` and its
    /// immediate neighbors, which are the only weeks ever prefetched (see that method's own doc
    /// comment) and so the only ones `WeekView`'s carousel ever asks for.
    public func heartRateHistogram(for weekStart: Date) -> HeartRateHistogram {
        weekGraphCaches[weekStart] ?? .empty
    }

    /// Prefetches (and evicts stale entries from) ``weekGraphCaches`` for ``displayedWeekStart``
    /// and its immediate neighbors, so paging to a neighboring week almost always finds its graph
    /// data already cached — computed while the athlete was still looking at a different week —
    /// instead of needing a fresh async computation on every swipe. Called after every
    /// load/import/dedup that could change the underlying activities, and by `WeekView` whenever
    /// ``displayedWeekStart`` changes.
    ///
    /// The displayed week itself is computed first, at `.userInitiated` priority, so the graph
    /// panel actually on screen updates as promptly as possible; its neighbors follow at the
    /// lower `.utility` priority, so the scheduler still favors the visible week's own work over
    /// prefetching ones the athlete isn't looking at yet. All still awaited here (structured
    /// concurrency, not a detached fire-and-forget `Task`) — by the time `WeekView`'s own
    /// `.task(id: displayedWeekStart)` next has anything else to do, the whole 3-week window is
    /// settled, and a caller that only cares about the displayed week's own data (already updated
    /// first) isn't kept waiting by anything else, since `WeekView` never awaits this call itself.
    ///
    /// A changed `activityCount` marks every currently cached week stale and due for
    /// recomputation, but deliberately doesn't clear ``weekGraphCaches`` up front to do that —
    /// `weekGraphCaches` is an observed, not `@ObservationIgnored`, property, so clearing it here
    /// (synchronously, before this method's first `await`) was visible to
    /// `HeartRateHistogramChartView` as a real, if momentary, "no data" state — the displayed
    /// week's own chart flashing to its empty-state view and back on every week-navigation
    /// `.task(id:)` firing that happened to load a not-yet-seen neighboring week's activities
    /// (changing `activityCount`), even though the
    /// same chart was on screen, correct, immediately before and after. Leaving the stale entry in
    /// place until ``cacheWeekGraph(weekStart:priority:)`` overwrites it with a fresh one instead
    /// shows one (very briefly) outdated frame rather than a spurious empty one — never a
    /// user-visible difference in practice, since the underlying activities rarely change whichever
    /// week's own histogram they'd affect this dramatically between one frame and the next.
    public func refreshWeekCachesIfNeeded() async {
        let activityCount = model.activities.count
        let activityCountChanged = weekGraphCachesActivityCount != activityCount
        if activityCountChanged {
            weekGraphCachesActivityCount = activityCount
        }
        let window = cachedWeekStarts
        let windowSet = Set(window)
        weekGraphCaches = weekGraphCaches.filter { windowSet.contains($0.key) }

        let displayedWeekStart = self.displayedWeekStart
        if activityCountChanged || weekGraphCaches[displayedWeekStart] == nil {
            await cacheWeekGraph(weekStart: displayedWeekStart, priority: .userInitiated)
        }
        for weekStart in window where weekStart != displayedWeekStart
            && (activityCountChanged || weekGraphCaches[weekStart] == nil) {
            await cacheWeekGraph(weekStart: weekStart, priority: .utility)
        }
    }

    /// Computes one week's heart-rate histogram off the main actor and stores it in
    /// ``weekGraphCaches``, unless the 3-week window has moved on again by the time it lands (a
    /// stale result for a week no longer near ``displayedWeekStart`` is simply dropped, not
    /// cached).
    private func cacheWeekGraph(weekStart: Date, priority: TaskPriority) async {
        let activityCount = model.activities.count
        let weekActivities = activities(forWeekStarting: weekStart)
        let athlete = model.athlete

        let histogram = await Task.detached(priority: priority) {
            HeartRateHistogram.aggregating(weekActivities, athlete: athlete)
        }.value
        guard isStillCacheable(weekStart, activityCount: activityCount) else { return }
        weekGraphCaches[weekStart] = histogram
    }

    /// Whether a background computation for `weekStart` (started when `activityCount` was
    /// `model.activities.count`) is still worth storing — `false` once either has moved on, since
    /// the result is now either stale (a subsequent import changed the underlying activities) or
    /// for a week that's fallen outside the 3-week window this cache keeps.
    private func isStillCacheable(_ weekStart: Date, activityCount: Int) -> Bool {
        cachedWeekStarts.contains(weekStart) && activityCount == model.activities.count
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
        await refreshWeekCachesIfNeeded()
    }

    /// Fetches the 3-week range `chartRange` would cover if ``displayedWeekStart`` were `weekStart`,
    /// without actually changing ``displayedWeekStart`` (MVP1-32).
    ///
    /// `TrainingModel.load(in:)` replaces `model.metrics` outright with whatever the given range
    /// covers, rather than merging it into what's already loaded. So flipping
    /// ``displayedWeekStart`` before that finishes leaves a window where ``chartMetrics`` filters
    /// the *old* `model.metrics` by the *new* (wider-reaching) ``chartRange`` — a real gap, not
    /// just stale data, for whichever few days the new range reaches that the old one didn't (e.g.
    /// swiping forward one week always reaches one more week's worth of days than was loaded
    /// before). Calling this first and awaiting it — as `WeekView`'s swipe-completion handler
    /// does — means `model` already covers the target range by the time ``displayedWeekStart``
    /// actually flips, so ``chartMetrics`` never has anything to be missing.
    public func preload(weekStart: Date, asOf today: Date = .now) async {
        try? await model.load(in: Self.chartRange(for: weekStart, calendar: calendar), asOf: today)
    }

    /// Runs a pull-to-refresh import via `refresher`. `TrainingModel.importActivities(from:)`
    /// already reloads `activities` and recomputes `metrics` for whatever range was last loaded
    /// (``chartRange``, assuming ``load(asOf:)`` already ran once for it), so nothing further is
    /// needed here. Failures fail silently back to the pre-refresh state (design doc §3.4).
    public func refresh(asOf today: Date = .now) async {
        isRefreshing = true
        defer { isRefreshing = false }
        try? await refresher.refreshActivities(asOf: today)
        await refreshWeekCachesIfNeeded()
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
        await refreshWeekCachesIfNeeded()
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
        await refreshWeekCachesIfNeeded()
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
        await refreshWeekCachesIfNeeded()
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
