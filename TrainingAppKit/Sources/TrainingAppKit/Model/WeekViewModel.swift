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

    /// The 3-week range (the week before, the displayed week, the week after) the chart covers.
    public var chartRange: ClosedRange<Date> {
        chartRange(for: displayedWeekStart)
    }

    /// The 3-week range `chartRange` would be if ``displayedWeekStart`` were `weekStart` instead —
    /// used by `WeekView`'s carousel so each page renders its own week's chart rather than
    /// whichever week happens to be ``displayedWeekStart`` (MVP1-32).
    public func chartRange(for weekStart: Date) -> ClosedRange<Date> {
        Self.chartRange(for: weekStart, calendar: calendar)
    }

    private static func chartRange(for weekStart: Date, calendar: Calendar) -> ClosedRange<Date> {
        let start = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let end = calendar.date(byAdding: .day, value: 13, to: weekStart) ?? weekStart
        return start...end
    }

    /// The range ``load(asOf:)`` actually fetches from the stores: wide enough to cover not just
    /// `weekStart`'s own ``chartRange(for:)``, but its immediate neighbors' as well (MVP1-32) — so
    /// `WeekView`'s carousel can render each neighbor page's own complete, correct 3-week chart
    /// continuously (not just after actually navigating there), and a swipe or button navigation
    /// never finds anything left to load once it flips ``displayedWeekStart``. Deliberately wider
    /// than ``chartRange(for:)`` itself, which stays exactly 3 weeks — that's still the range each
    /// page's own chart *displays*, just now backed by a `model.metrics` that already reaches far
    /// enough to cover its neighbors' displays too.
    private static func loadRange(for weekStart: Date, calendar: Calendar) -> ClosedRange<Date> {
        let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let start = chartRange(for: previousWeekStart, calendar: calendar).lowerBound
        let end = chartRange(for: nextWeekStart, calendar: calendar).upperBound
        return start...end
    }

    /// `model.metrics` restricted to ``chartRange``, in day order.
    public var chartMetrics: [FitnessMetrics] {
        chartMetrics(for: displayedWeekStart)
    }

    /// `model.metrics` restricted to ``chartRange(for:)``'s own range for `weekStart`, in day
    /// order — `WeekView`'s carousel uses this (rather than the unparameterized ``chartMetrics``)
    /// so each page renders *that page's own* 3-week window instead of whichever week happens to
    /// be ``displayedWeekStart`` (MVP1-32).
    public func chartMetrics(for weekStart: Date) -> [FitnessMetrics] {
        let range = chartRange(for: weekStart)
        return model.metrics
            .filter { range.contains($0.day) }
            .sorted { $0.day < $1.day }
    }

    /// The date range of ``displayedWeekStart`` — the week currently visible in the day list, not
    /// necessarily today's. Used to highlight that week's background on the fitness chart, so the
    /// 3-week trend stays visually anchored to whichever week the athlete has scrolled to.
    public var displayedWeekRange: ClosedRange<Date> {
        displayedWeekRange(for: displayedWeekStart)
    }

    /// The date range of `weekStart` — used by `WeekView`'s carousel (MVP1-32) so a
    /// previous/next page highlights *its own* week's background rather than
    /// ``displayedWeekStart``'s.
    public func displayedWeekRange(for weekStart: Date) -> ClosedRange<Date> {
        let end = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        return weekStart...end
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
                loadChangeFraction: loadChangeFraction,
                polarizedSplit: currentSport.timeInZone.polarizedSplit
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

    /// `activity.id` → the overlap issue worth warning about, for every activity named by a real
    /// (non-``OverlapRecommendation/possibleMultisport``) advice — one pass over
    /// ``TrainingModel/overlapAdvice`` rather than the N passes ``overlapWarning(for:)`` would need
    /// re-filtering it per activity. `TrainingModel.overlapAdvice` itself reruns
    /// `ActivityOverlapChecker.findOverlaps(in:)` on every access (its own doc comment warns a
    /// SwiftUI-`body` caller to cache it), and `DayActivitiesSection` calls ``overlapWarning(for:)``
    /// once per activity card while building the day list — the same `body`-during-swipe path
    /// `sportStatsPagesCaches`/`weekGraphCaches` already exist to keep MVP1-19's freeze from
    /// recurring, so batching this into a single dictionary build per access is worth doing even
    /// though `ActivityOverlapChecker` itself is cheap at today's realistic activity counts.
    private var overlapWarningsByActivityID: [UUID: OverlapRecommendation] {
        var result: [UUID: OverlapRecommendation] = [:]
        for advice in model.overlapAdvice {
            if case .possibleMultisport = advice.recommendation { continue }
            for id in [advice.first, advice.second] where result[id] == nil {
                result[id] = advice.recommendation
            }
        }
        return result
    }

    /// The overlap issue worth warning about for `activity`, if any (MVP1-63) — skips
    /// ``OverlapRecommendation/possibleMultisport``: that case describes activities that
    /// legitimately sit close together (e.g. a triathlon's separately-logged legs) rather than a
    /// problem, so it isn't surfaced as a warning; `.duplicate`/`.merge`/`.conflict` all are.
    public func overlapWarning(for activity: Activity) -> OverlapRecommendation? {
        overlapWarningsByActivityID[activity.id]
    }

    /// `activity`'s overlap context — its recommendation plus the specific other activity it
    /// overlaps with — for the activity detail sheet's resolution UI (MVP1-63). Unlike
    /// ``overlapWarning(for:)``, this doesn't skip ``OverlapRecommendation/possibleMultisport``:
    /// the detail sheet is where all four recommendation types are meant to surface distinctly
    /// (MVP1-29), even the ones that don't need a delete action.
    public func overlapContext(for activity: Activity) -> OverlapContext? {
        for advice in model.overlapAdvice where advice.first == activity.id || advice.second == activity.id {
            let otherID = advice.first == activity.id ? advice.second : advice.first
            guard let other = model.activities.first(where: { $0.id == otherID }) else { continue }
            return OverlapContext(recommendation: advice.recommendation, otherActivity: other)
        }
        return nil
    }

    /// One row per activity worth reviewing for an overlap issue (MVP1-63) — every activity named
    /// by a non-``OverlapRecommendation/possibleMultisport`` advice, deduplicated (an activity
    /// appearing in more than one pair only lists once, under whichever advice named it first) and
    /// sorted by start time. Backs the sheet the import summary banner opens onto.
    public var overlapReviewItems: [OverlapReviewItem] {
        var seenIDs: Set<UUID> = []
        var items: [OverlapReviewItem] = []
        for advice in model.overlapAdvice {
            if case .possibleMultisport = advice.recommendation { continue }
            for id in [advice.first, advice.second] where !seenIDs.contains(id) {
                guard let activity = model.activities.first(where: { $0.id == id }) else { continue }
                seenIDs.insert(id)
                items.append(OverlapReviewItem(activity: activity, recommendation: advice.recommendation))
            }
        }
        return items.sorted { $0.activity.start < $1.activity.start }
    }

    /// How many activities currently have an overlap issue worth reviewing (MVP1-67) — the same
    /// live count ``overlapReviewItems`` lists, surfaced as a plain `Int` for the Athlete tab's
    /// warning banner and its tab-bar badge. Always current: unlike the one-time
    /// `overlapImportSummary` snapshot this replaced, it reflects whatever `model.overlapAdvice`
    /// says right now, so resolving an overlap (``resolveOverlap(deleting:)``) updates both
    /// surfaces the moment the delete lands, with no separate "refresh the summary" step needed.
    public var overlapWarningCount: Int {
        overlapReviewItems.count
    }

    /// Resolves one side of an overlap by deleting it (MVP1-63) — the activity detail sheet's
    /// action for ``OverlapRecommendation/duplicate(keep:remove:)``/``OverlapRecommendation/merge``/
    /// ``OverlapRecommendation/conflict``: "remove this one, keep the other".
    public func resolveOverlap(deleting id: UUID, asOf today: Date = .now) async {
        await deleteActivity(id: id, asOf: today)
    }

    /// The activity detail sheet's general "Delete Activity" action (MVP1-65), independent of any
    /// overlap — e.g. a bad HealthKit import the athlete just wants gone, not something
    /// ``TrainingModel/overlapAdvice`` flagged. The view gates this behind its own confirmation
    /// alert before calling it; this method itself performs the delete unconditionally.
    public func deleteActivity(_ activity: Activity, asOf today: Date = .now) async {
        await deleteActivity(id: activity.id, asOf: today)
    }

    /// Shared by ``resolveOverlap(deleting:)`` and ``deleteActivity(_:asOf:)`` — both ultimately
    /// just delete one activity by id (MVP1-64's soft-delete/tombstone semantics live entirely in
    /// `TrainingModel.deleteActivity(id:asOf:)` itself, not here). Failures fail silently, same as
    /// every other store-mutating action here — MVP 1 has no error UI.
    private func deleteActivity(id: UUID, asOf today: Date) async {
        try? await model.deleteActivity(id: id, asOf: today)
        await refreshWeekCachesIfNeeded()
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
        let statisticsCalculator = self.statisticsCalculator
        // The week's own end (not `.now`/today), so `HeartRateHistogram.aggregating`'s zone
        // boundaries reflect the zones actually in effect that week -- a week long in the past must
        // not shade against the athlete's *current* zones, which could be way off by then
        // (MVP1-78 follow-up).
        let asOf = displayedWeekRange(for: weekStart).upperBound

        let histogram = await Task.detached(priority: priority) {
            HeartRateHistogram.aggregating(
                weekActivities, athlete: athlete, asOf: asOf, statisticsCalculator: statisticsCalculator
            )
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
        ActivityDetailViewModel(activity: activity, athlete: model.athlete, overlapContext: overlapContext(for: activity))
    }

    /// The view model for the "Create Planned Workout" sheet (MVP2-15), opened from a day row's
    /// add affordance — `date` defaults the sheet to that day, still editable inside it.
    public func plannedWorkoutSheetViewModel(date: Date) -> PlannedWorkoutSheetViewModel {
        PlannedWorkoutSheetViewModel(model: model, date: date)
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

    /// Loads ``loadRange(for:calendar:)`` for ``displayedWeekStart`` from the stores into `model`
    /// — wider than ``chartRange`` itself, so `WeekView`'s neighbor carousel pages already have
    /// their own complete chart data before the athlete ever swipes to them (MVP1-32). Errors are
    /// swallowed — a failed load leaves `model` exactly as it was (`TrainingModel.load(in:)`'s own
    /// guarantee), so there's nothing for the view to reconcile; MVP 1 has no load-failure UI.
    public func load(asOf today: Date = .now) async {
        try? await model.load(in: Self.loadRange(for: displayedWeekStart, calendar: calendar), asOf: today)
        await refreshWeekCachesIfNeeded()
    }

    /// `model.metrics` restricted to `range`, in day order — for the metrics detail view's period
    /// picker (MVP1-45), which can ask for a window (e.g. a year) wider than the 3-week default
    /// `chartMetrics(for:)` already has loaded. Loads the *union* of `range` and the currently
    /// loaded window before reading, never just `range` alone — `TrainingModel.load(in:)` replaces
    /// `model.activities`/`plans`/`metrics` outright rather than merging into them, so loading a
    /// shifted range on its own would silently drop data `WeekView`'s own day list still needs
    /// until the next natural navigation reloads it. The union is a strict superset of both, so
    /// nothing the main view relies on is ever lost by calling this.
    public func metrics(in range: ClosedRange<Date>, asOf today: Date = .now) async -> [FitnessMetrics] {
        let currentLoadRange = Self.loadRange(for: displayedWeekStart, calendar: calendar)
        let unionRange = min(range.lowerBound, currentLoadRange.lowerBound)...max(range.upperBound, currentLoadRange.upperBound)
        try? await model.load(in: unionRange, asOf: today)
        await refreshWeekCachesIfNeeded()
        return model.metrics.filter { range.contains($0.day) }.sorted { $0.day < $1.day }
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
