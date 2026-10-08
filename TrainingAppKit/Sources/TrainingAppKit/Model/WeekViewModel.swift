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
    // Internal (not private) so `WeekViewModel+Overlaps.swift`'s extension can reach it.
    let model: TrainingModel
    /// Keeps the Watch's scheduled workouts in step with the plans (MVP2-55); `nil` in tests and
    /// where WorkoutKit isn't available.
    let watchSync: WatchScheduleSync?
    /// The Watch sync ``requestWatchSync(asOf:)`` last started, so tests can wait for it.
    ///
    /// When a request lands while a sync is already running, this becomes a task that finishes at
    /// once, and the running sync does the extra round on its own; so wait on it only after a single
    /// request.
    @ObservationIgnored
    private(set) var pendingWatchSync: Task<Void, Never>?
    private let refresher: any ActivityRefreshing
    /// The calendar of the athlete's time zone and week start, rebuilt only when either changes
    /// (MVP2-132), since the athlete can now edit both. Read through ``calendar``.
    @ObservationIgnored
    private var calendarCache: (timeZone: TimeZone, weekStartsOn: Weekday, calendar: Calendar)
    /// The athlete's calendar: ``Calendar`` for their time zone with their week start applied. Built
    /// once and reused, so the week-swipe path doesn't create one per access; a changed time zone or
    /// week start gets a new one on the next access.
    private var calendar: Calendar {
        let athlete = model.athlete
        if calendarCache.timeZone != athlete.timeZone || calendarCache.weekStartsOn != athlete.weekStartsOn {
            calendarCache = (athlete.timeZone, athlete.weekStartsOn, Self.calendar(for: athlete))
        }
        return calendarCache.calendar
    }
    /// Computes ``trainingLoad(for:)`` — the same default calculators `ActivityDetailViewModel`
    /// uses, so a card's headline Load number always agrees with the detail sheet's own figure.
    /// Not `private` only because `WeekViewModel+LinkedPlan.swift` projects workouts with it too.
    let statisticsCalculator = StatisticsCalculator()

    /// Sport-stats pages, cached per week (keyed by that week's `weekStart`) — see
    /// ``sportStatsPages(for:asOf:)``'s own doc comment. Not `@ObservationIgnored`: `WeekView`
    /// reads this indirectly through that method, and needs the read tracked the same way a plain
    /// stored property's would be.
    private var sportStatsPagesCaches: [Date: [SportStatsPage]] = [:]
    /// `(model.activities.count, model.plans.count, model.workouts.count, today)` as of the last
    /// time ``sportStatsPagesCaches`` was populated — any changing invalidates the whole cache (an
    /// import/dedup could change any cached week's activities, not just the displayed one; a new
    /// calendar day shifts every week's own change-vs-previous-week percentages; a plan or its
    /// workout can change independently of `model.activities`, e.g. saving a new planned workout
    /// via `PlannedWorkoutSheet`). The athlete is part of the key too: a changed max or resting
    /// heart rate rescores every activity's load (MVP2-56). So is ``plansFingerprint()``: editing a
    /// plan's load override, date or workout changes no count but does change the planned totals and
    /// which of them are estimates (MVP2-8). And ``activitiesFingerprint()``: a resync can change an
    /// activity's sport, distance or effort without changing the count (MVP2-54).
    @ObservationIgnored
    private var sportStatsPagesCachesKey: (activityCount: Int, planCount: Int, workoutCount: Int, athlete: AthleteProfile, today: Date, paceHistoryGeneration: Int, plans: Int, activities: Int)?

    /// Each week's heart-rate histogram, cached per week (keyed by that week's `weekStart`) — at
    /// most 3 entries (``displayedWeekStart`` and its immediate neighbors) at any time, refreshed
    /// by ``refreshWeekCachesIfNeeded()``. Not `@ObservationIgnored`, for the same reason as
    /// ``sportStatsPagesCaches``.
    private var weekGraphCaches: [Date: HeartRateHistogram] = [:]
    /// ``histogramFingerprint()`` of `model.activities` as of the last time ``weekGraphCaches`` was
    /// populated — see ``sportStatsPagesCachesKey``'s own doc comment for why a mismatch
    /// invalidates the whole cache rather than trying to single out which weeks actually changed.
    /// A fingerprint rather than the count: a resync can change an activity's heart-rate samples
    /// without changing how many activities there are (MVP2-130).
    @ObservationIgnored
    private var weekGraphCachesFingerprint: Int?
    /// `model.athlete` as of the last time ``weekGraphCaches`` was populated. A change (e.g. a new
    /// max heart rate, MVP2-56) moves the zone boundaries the histogram is shaded against, so it
    /// marks every cached week stale the same way a changed activity fingerprint does.
    @ObservationIgnored
    private var weekGraphCachesAthlete: AthleteProfile?

    /// ``dailyLoadSplit(for:)`` results, cached per week (keyed by that week's `weekStart`) — same
    /// reasoning as ``sportStatsPagesCaches``: `WeekView.graphPanel(weekStart:isCurrentPage:)` calls
    /// this for all three carousel pages (current plus both static previews) on every touch-move
    /// frame of the week-swipe drag, and unlike ``chartMetrics(for:)`` (a cheap filter over
    /// already-computed `model.metrics`), this does real per-activity TRIMP work
    /// (`StatisticsCalculator.summary(for:athlete:)`) — exactly the MVP1-19 freeze class this
    /// codebase already built ``sportStatsPagesCaches``/``weekGraphCaches`` to keep out of that path.
    private var dailyLoadSplitCaches: [Date: DailyLoadSplit] = [:]
    /// `(model.activities.count, model.plans.count, model.workouts.count)` as of the last time
    /// ``dailyLoadSplitCaches`` was populated — three counts, not just `activityCount` the way
    /// ``sportStatsPagesCachesKey`` does, since a plan or its workout can change independently of
    /// `model.activities` (e.g. saving a new planned workout via `PlannedWorkoutSheet`), plus the
    /// athlete, whose heart-rate settings every activity's load is scored with (MVP2-56), plus
    /// ``plansFingerprint()``, since an edited override, date or workout moves a planned bar without
    /// changing any count, plus ``activitiesFingerprint()``, since an activity changed in place (a
    /// resync) moves a performed bar without changing the count (MVP2-54).
    @ObservationIgnored
    private var dailyLoadSplitCachesKey: (activityCount: Int, planCount: Int, workoutCount: Int, athlete: AthleteProfile, today: Date, plans: Int, activities: Int)?

    /// The card caches: ``plannedCardSummary(for:)``, ``linkedPlanExpectation(for:)`` and
    /// ``intensity(for:)-(Activity)``/``intensity(for:)-(PlannedActivity)`` results. The day list
    /// re-renders on every touch-move frame of the week-swipe drag, and each of these runs the TRIMP
    /// estimator, a workout projection or the intensity classifier — the same freeze class
    /// ``dailyLoadSplitCaches`` exists to keep out of that path.
    ///
    /// Each entry remembers the inputs it was computed from (see `InputKeyedCache`), so an in-place
    /// edit — a plan's load override, a workout's parameters, an activity's link — refreshes it
    /// though no count changed; `refreshCardCachesIfNeeded()` drops them all when the athlete or the
    /// intensity thresholds change, and prunes deleted items. Not `private` only because the
    /// extensions using them live in their own files.
    @ObservationIgnored
    var plannedSummaryCache = InputKeyedCache<PlannedCardSummary>()
    /// ``scoredLoad(for:)`` per activity (MVP2-127, MVP2-128): the card, the stats bar's estimate flags
    /// and the day row's Load pill all ask for it, each time running a full statistics pass.
    @ObservationIgnored
    var scoredLoadCache = InputKeyedCache<TrainingLoad?>()
    @ObservationIgnored
    var linkedExpectationCache = InputKeyedCache<LinkedPlanExpectation?>()
    @ObservationIgnored
    var activityIntensityCache = InputKeyedCache<IntensityAssessment?>()
    @ObservationIgnored
    var planIntensityCache = InputKeyedCache<IntensityAssessment?>()
    /// What the card caches were filled under, for `refreshCardCachesIfNeeded()`.
    @ObservationIgnored
    var cardCacheAthlete: AthleteProfile?
    @ObservationIgnored
    var cardCacheIntensityParameters: IntensityClassifierParameters?
    @ObservationIgnored
    var cardCacheCounts: [Int]?

    /// Bumped whenever ``paceHistory`` is replaced, so the card and stats caches that project
    /// workouts with it recompute. Observed, so cards on screen re-read once a history lands.
    var paceHistoryGeneration = 0
    /// What ``paceHistory`` was built from, for `refreshPaceHistoryIfNeeded(asOf:force:)`.
    @ObservationIgnored
    var paceHistoryKey: PaceHistoryKey?

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
    /// A workout that held a heart rate above the athlete's max, waiting for them to confirm or
    /// decline raising it (MVP2-56). `WeekView` shows it as an alert. See
    /// ``checkForMaxHeartRateSuggestion(asOf:)``.
    public internal(set) var maxHeartRateSuggestion: MaxHeartRateSuggestion?
    /// Set when saving an accepted max heart rate failed, for `WeekView` to report; cleared when
    /// shown.
    public internal(set) var maxHeartRateUpdateFailed = false
    /// `true` while an accepted max heart rate is being saved. Until it lands, `model.athlete`
    /// still has the old max, so a check in that window would ask about the same workout again.
    @ObservationIgnored
    var isApplyingMaxHeartRate = false
    /// What the athlete has already declined, and whether the history scan has run.
    @ObservationIgnored
    let maxHeartRatePromptHistory: any MaxHeartRatePromptHistory

    /// Creates the week view model.
    ///
    /// - Parameters:
    ///   - model: The training model to read from and write to.
    ///   - refresher: Runs HealthKit imports for pull-to-refresh.
    ///   - maxHeartRatePromptHistory: What the athlete already said about max heart rate
    ///     suggestions; defaults to the app's `UserDefaults`-backed record.
    ///   - watchSync: Run again after anything that changes plans or their links (MVP2-55,
    ///     MVP2-116); `nil` skips it.
    ///   - today: The day whose week is shown first.
    public init(
        model: TrainingModel,
        refresher: any ActivityRefreshing,
        maxHeartRatePromptHistory: (any MaxHeartRatePromptHistory)? = nil,
        watchSync: WatchScheduleSync? = nil,
        today: Date = .now
    ) {
        self.model = model
        self.refresher = refresher
        self.watchSync = watchSync
        self.maxHeartRatePromptHistory = maxHeartRatePromptHistory ?? UserDefaultsMaxHeartRatePromptHistory()
        let calendar = Self.calendar(for: model.athlete)
        self.calendarCache = (model.athlete.timeZone, model.athlete.weekStartsOn, calendar)
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

    /// The races inside ``chartRange(for:)`` for `weekStart` (see ``chartRaces(in:)``), for the
    /// graph panel's race markers (MVP2-104).
    public func chartRaces(for weekStart: Date) -> [Race] {
        chartRaces(in: chartRange(for: weekStart))
    }

    /// The loaded races inside `range`, in date order, one per day: the most important (primary,
    /// then secondary, then tertiary; by name when equal), since markers for two races on one day
    /// would sit on top of each other (MVP2-104). Only races the model has loaded: the metric detail
    /// charts get theirs from ``chartBuffer(in:asOf:)``, which loads the range first.
    ///
    /// Not cached, unlike the other chart inputs, though ``chartRaces(for:)`` runs on the week-swipe path:
    /// the work is one date comparison per loaded race, and a day lookup only for the few races that
    /// fall in `range`, and an uncached read can never show a race that was just edited or deleted.
    public func chartRaces(in range: ClosedRange<Date>) -> [Race] {
        let order = RacePriority.allCases
        func rank(_ race: Race) -> Int { order.firstIndex(of: race.priority) ?? 0 }
        var byDay: [Date: Race] = [:]
        for race in model.races where range.contains(race.date) {
            let day = calendar.startOfDay(for: race.date)
            if let existing = byDay[day], (rank(existing), existing.name) <= (rank(race), race.name) { continue }
            byDay[day] = race
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    /// ``chartRange(for:)``'s own range for `weekStart`'s daily load, split into what was actually
    /// performed vs. what's planned (MVP2-30) — for `DailyLoadChartView`'s bars.
    ///
    /// Deliberately *not* `chartMetrics(for:)`'s merged `FitnessMetrics.load`: that figure follows
    /// `DailyLoadSeries`'s either/or merge rule (today/future use whichever of actual-or-planned
    /// applies, never both), which is right for CTL/ATL but wrong for this chart — a planned
    /// workout the athlete hasn't done yet should show only its planned bar, but once performed
    /// (possibly at a different load than predicted), both the original planned estimate and the
    /// real performed figure should stay visible together. Both halves are computed independently
    /// at the day level, not per-workout: `PlanReconciler` (MVP2-19, matching a specific plan to its
    /// specific completed activity) doesn't exist yet, so "a day has both" is the closest available
    /// signal, the same granularity `StatisticsCalculator.periodStats` already merges at. The
    /// planned side only covers `today` or later, matching that same merge rule (and
    /// `DailyLoadSeries`'s) — a plan from before `today` that was never performed reads as
    /// genuinely missed, not as a bar this chart keeps showing indefinitely.
    ///
    /// Cached per week: unlike `chartMetrics(for:)` (a cheap filter over already-computed
    /// `model.metrics`), this does real per-activity TRIMP work
    /// (`StatisticsCalculator.summary(for:athlete:)`), and `WeekView.graphPanel(weekStart:isCurrentPage:)`
    /// calls it for all three carousel pages on every touch-move frame of the week-swipe drag — see
    /// ``dailyLoadSplitCaches``'s own doc comment for why this needs the same per-week caching
    /// ``sportStatsPages(for:asOf:)``/``heartRateHistogram(for:)`` already have.
    func dailyLoadSplit(for weekStart: Date, asOf today: Date = .now) -> DailyLoadSplit {
        let key = (model.activities.count, model.plans.count, model.workouts.count)
        let plans = plansFingerprint()
        let activities = activitiesFingerprint()
        let keyIsCurrent = dailyLoadSplitCachesKey.map {
            $0.activityCount == key.0 && $0.planCount == key.1 && $0.workoutCount == key.2
                && $0.athlete == model.athlete && calendar.isDate($0.today, inSameDayAs: today)
                && $0.plans == plans && $0.activities == activities
        } ?? false
        if !keyIsCurrent {
            dailyLoadSplitCaches.removeAll()
            dailyLoadSplitCachesKey = (key.0, key.1, key.2, model.athlete, today, plans, activities)
        }
        if let cached = dailyLoadSplitCaches[weekStart] {
            return cached
        }
        let split = computeDailyLoadSplit(in: chartRange(for: weekStart), asOf: today)
        dailyLoadSplitCaches[weekStart] = split
        return split
    }

    /// `dailyLoadSplit(for:asOf:)`'s own actual/planned split, but over an arbitrary `range` rather
    /// than a week's fixed ``chartRange(for:)`` — for `MetricDetailView`'s Load chart, which pans
    /// across a caller-chosen window (MVP1-45's Week/Month/3M/6M/Year periods) instead of the fixed
    /// 3-week carousel `DailyLoadChartView` shows. Not cached, matching ``metrics(in:asOf:)``'s own
    /// precedent for the same reason: this is only ever called from a pan/period-change buffer
    /// reload, never from the per-frame swipe-drag hot path ``dailyLoadSplit(for:asOf:)`` itself
    /// has to guard against.
    ///
    /// Loads the *union* of `range` and the currently loaded window first, same reasoning
    /// ``metrics(in:asOf:)`` documents: `TrainingModel.load(in:)` replaces `model.activities`/
    /// `plans`/`workouts` outright rather than merging into them, so loading a shifted range on its
    /// own would silently drop data the main week view's own carousel still needs.
    func dailyLoadSplit(in range: ClosedRange<Date>, asOf today: Date = .now) async -> DailyLoadSplit {
        let currentLoadRange = Self.loadRange(for: displayedWeekStart, calendar: calendar)
        let unionRange = min(range.lowerBound, currentLoadRange.lowerBound)...max(range.upperBound, currentLoadRange.upperBound)
        try? await model.load(in: unionRange, asOf: today)
        await refreshWeekCachesIfNeeded(asOf: today)
        return computeDailyLoadSplit(in: range, asOf: today)
    }

    private func computeDailyLoadSplit(in range: ClosedRange<Date>, asOf today: Date) -> DailyLoadSplit {
        let athlete = model.athlete
        let todayStart = calendar.startOfDay(for: today)

        let activitiesByDay = Dictionary(grouping: model.activities.filter { range.contains(calendar.startOfDay(for: $0.start)) }) {
            calendar.startOfDay(for: $0.start)
        }
        let actual = activitiesByDay.map { day, activities in
            DailyLoad(day: day, load: activities.reduce(0) { $0 + statisticsCalculator.summary(for: $1, athlete: athlete).load.value })
        }

        let workoutsByID = Dictionary(uniqueKeysWithValues: model.workouts.map { ($0.id, $0) })
        let plansByDay = Dictionary(grouping: model.plans.filter { plan in
            let day = calendar.startOfDay(for: plan.date)
            return range.contains(day) && day >= todayStart
        }) {
            calendar.startOfDay(for: $0.date)
        }
        let planned = plansByDay.map { day, plans -> DailyLoad in
            let load = plans.reduce(0.0) { total, plan in
                guard let workout = workoutsByID[plan.workoutID] else { return total }
                let estimate = plan.expectedLoadOverride
                    ?? statisticsCalculator.estimator.estimatedLoad(for: workout, athlete: athlete).value
                return total + estimate
            }
            return DailyLoad(day: day, load: load)
        }

        return DailyLoadSplit(
            actual: actual.filter { $0.load > 0 }.sorted { $0.day < $1.day },
            planned: planned.filter { $0.load > 0 }.sorted { $0.day < $1.day }
        )
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

    /// `plans(on:)` minus those already matched to a completed activity (`completedActivityID !=
    /// nil`) — that activity's own card represents them, so the day list shouldn't lay out a row
    /// for them at all.
    public func pendingPlans(on day: Date) -> [PlannedActivity] {
        plans(on: day).filter { $0.completedActivityID == nil }
    }

    /// Races on `day` (MVP2-104), most important first (primary, then secondary, then tertiary) so
    /// the day row lists them in a stable, meaningful order.
    public func races(on day: Date) -> [Race] {
        let onDay = model.races.filter { calendar.isDate($0.date, inSameDayAs: day) }
        // Most days have no race: skip the sort, which runs for every day of three pages per drag frame.
        guard onDay.count > 1 else { return onDay }
        // `allCases` is declared most important first (primary, secondary, tertiary).
        let order = RacePriority.allCases
        return onDay.sorted {
            let (a, b) = (order.firstIndex(of: $0.priority) ?? 0, order.firstIndex(of: $1.priority) ?? 0)
            return a == b ? $0.name < $1.name : a < b
        }
    }

    /// The workout a plan schedules, if still in the library.
    public func workout(for plan: PlannedActivity) -> StructuredWorkout? {
        model.workouts.first { $0.id == plan.workoutID }
    }

    /// Everything a planned activity's card shows (MVP2-37), derived from the plan and its workout.
    public struct PlannedCardSummary: Equatable, Sendable {
        /// The one measure a workout is defined by, for places with room for a single figure (the
        /// activity sheet's plan-link options). The card shows both ``duration`` and
        /// ``distanceMeters``, the forecast one marked with a "~".
        public enum Extent: Equatable, Sendable {
            case duration(TimeInterval)
            case distance(meters: Double)
        }

        /// `.running` when the plan's workout is no longer in the library.
        public let sport: Sport
        /// `nil` when the plan's workout is no longer in the library.
        public let name: String?
        /// ``PlannedActivity/expectedLoadOverride``, else the estimator's figure; `nil` when the
        /// workout is missing.
        public let load: Double?
        /// Whether ``load`` is the estimator's figure, shown with a "~" (MVP2-8); `false` for the
        /// athlete's own override, which is a target.
        public let isLoadEstimated: Bool
        public let extent: Extent?
        /// Expected duration: the sum of the steps' times for a workout of time steps only, else
        /// forecast from the athlete's paces. `nil` when the workout is missing.
        public let duration: TimeInterval?
        /// Expected distance: the sum of the steps' distances for a workout of distance steps only,
        /// else forecast from the athlete's paces. `nil` when the workout is missing, when it can't be
        /// forecast (no heart-rate zone settings recorded) or when it comes to nothing.
        public let distanceMeters: Double?
        /// Whether ``duration`` is a forecast, shown with a "~" (MVP2-8): the workout has a distance
        /// or open step (`StructuredWorkout.isDurationForecast`).
        public let isDurationEstimated: Bool
        /// Whether ``distanceMeters`` is a forecast, shown with a "~" (MVP2-8): the workout isn't made
        /// solely of distance steps (`StructuredWorkout.isDistanceForecast`).
        public let isDistanceEstimated: Bool
        /// How many earlier activities the forecast came from; `0` for the pace model alone. The
        /// detail sheet's footer says so.
        public let forecastActivityCount: Int

        /// Whether ``extent`` is a forecast: the duration's flag for a duration, never for a distance
        /// (only a workout of distance steps alone is shown by its distance).
        public var isExtentEstimated: Bool {
            switch extent {
            case .duration?: isDurationEstimated
            case .distance?, nil: false
            }
        }

        /// The summary for `plan` given its `workout` (`nil` when no longer in the library). Shared by
        /// the day list's card and ``PlannedWorkoutDetailViewModel``, so both always show the same
        /// numbers. A workout made up solely of distance-goal steps gets its distance as ``extent``;
        /// every other workout its expected duration. Whatever the steps don't set is forecast from
        /// `history` (MVP2-35, MVP2-111; see
        /// `StatisticsCalculator.projection(for:athlete:paceHistory:before:excluding:)`).
        ///
        /// "Distance steps alone" uses the same rule as the estimate flags
        /// (`StructuredWorkout.isDistanceForecast`, which skips blocks repeated zero times), so a
        /// distance shown as the workout's target is never one taken from the forecast.
        static func make(
            plan: PlannedActivity, workout: StructuredWorkout?, athlete: AthleteProfile,
            calculator: StatisticsCalculator, history: PaceHistory = .empty
        ) -> PlannedCardSummary {
            guard let workout else {
                return PlannedCardSummary(
                    sport: .running, name: nil, load: plan.expectedLoadOverride, isLoadEstimated: false,
                    extent: nil, duration: nil, distanceMeters: nil,
                    isDurationEstimated: false, isDistanceEstimated: false, forecastActivityCount: 0
                )
            }
            let load = plan.expectedLoadOverride
                ?? calculator.estimator.estimatedLoad(for: workout, athlete: athlete).value
            let projection = calculator.projection(
                for: workout, athlete: athlete, paceHistory: history, before: plan.date
            )

            // `isDistanceForecast` is `true` for a workout with no steps at all, so it's never shown
            // as "0 m".
            let extent: Extent
            let expectedDistance: Double?
            if workout.isDistanceForecast {
                extent = .duration(projection.duration)
                expectedDistance = projection.distanceMeters
            } else {
                let stepDistance = workout.blocks.reduce(0.0) { total, block in
                    let blockDistance = block.steps.reduce(0.0) { sum, step in
                        if case .distance(let meters) = step.goal { return sum + meters }
                        return sum
                    }
                    return total + blockDistance * Double(block.repetitions)
                }
                extent = .distance(meters: stepDistance)
                expectedDistance = stepDistance
            }

            return PlannedCardSummary(
                sport: workout.sport, name: workout.name, load: load, isLoadEstimated: plan.isExpectedLoadEstimated,
                extent: extent, duration: projection.duration,
                distanceMeters: expectedDistance.flatMap { $0 > 0 ? $0 : nil },
                isDurationEstimated: workout.isDurationForecast, isDistanceEstimated: workout.isDistanceForecast,
                forecastActivityCount: projection.matchedActivityCount
            )
        }
    }

    /// The card content for `plan` (MVP2-37): its expected duration and distance, whichever the
    /// steps don't set forecast from ``paceHistory``.
    public func plannedCardSummary(for plan: PlannedActivity) -> PlannedCardSummary {
        refreshCardCachesIfNeeded()
        let workout = workout(for: plan)
        return plannedSummaryCache.value(for: plan.id, inputs: projectionInputs(for: plan, workout: workout)) {
            computePlannedCardSummary(for: plan)
        }
    }

    private func computePlannedCardSummary(for plan: PlannedActivity) -> PlannedCardSummary {
        PlannedCardSummary.make(
            plan: plan, workout: workout(for: plan), athlete: model.athlete, calculator: statisticsCalculator,
            history: paceHistory
        )
    }

    /// `day`'s fitness metrics, if computed — `nil` before ``load(asOf:)`` has covered it (e.g.
    /// the first frame, before `.task` runs). Used by the day list's CTL/ATL/TSB pills (MVP1-40).
    public func metrics(on day: Date) -> FitnessMetrics? {
        model.metrics.first { calendar.isDate($0.day, inSameDayAs: day) }
    }

    /// `day`'s metrics (see ``metrics(on:)``), whether its Form (TSB) pill shows an estimate
    /// (MVP2-8; see `FitnessMetrics.isFormProjected(on:in:calendar:)` — Load, Fitness and Fatigue
    /// follow `day`'s own ``FitnessMetrics/isProjected`` instead), and whether its Load pill does
    /// because an activity was scored from perceived effort (MVP2-127), for the day list's pill row.
    ///
    /// One scan of `model.metrics` for both: every day row calls this on each week-swipe frame. The
    /// series is one entry per day in order, so the previous day is normally the entry before
    /// `day`'s; anything else falls back to a lookup.
    public func dayMetrics(on day: Date) -> (metrics: FitnessMetrics?, isFormProjected: Bool, isLoadEstimated: Bool) {
        let series = model.metrics
        guard let index = series.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: day) }) else {
            return (nil, false, false)
        }
        let isLoadEstimated = isLoadEstimated(on: day)
        if index > 0, let previousDay = calendar.date(byAdding: .day, value: -1, to: day),
           calendar.isDate(series[index - 1].day, inSameDayAs: previousDay) {
            return (series[index], series[index - 1].isProjected, isLoadEstimated)
        }
        return (series[index], FitnessMetrics.isFormProjected(on: day, in: series, calendar: calendar), isLoadEstimated)
    }

    /// Whether `day`'s Load pill is an estimate because a completed activity that day was scored from
    /// perceived effort rather than heart rate (MVP2-127), the same test its card makes (MVP2-8). A day
    /// with any such activity counts, since its total load then includes an estimate. A projected day
    /// is estimated by `FitnessMetrics.isProjected` instead. Each activity's score is cached
    /// (``scoredLoad(for:)``), so this stays cheap on the week-swipe path.
    private func isLoadEstimated(on day: Date) -> Bool {
        activities(on: day).contains { scoredLoad(for: $0)?.method.isEstimate ?? false }
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
    /// would redundantly re-run two full `periodStatsSplit` computations (one `LoadCalculator`
    /// invocation per activity, each) even though neither that page's own week nor the underlying
    /// data changed — the same class of freeze this codebase already fixed once for the day list
    /// itself (MVP1-19). The whole cache is invalidated together (not per week) whenever
    /// `model.activities`/`model.plans`/`model.workouts`' counts or `today`'s calendar day changes
    /// — any of those can shift every cached week's own figures at once, and a plan/workout can
    /// change independently of `model.activities` (e.g. saving a new planned workout via
    /// `PlannedWorkoutSheet`). A new ``paceHistory`` invalidates it too: the planned distance and
    /// time are forecast from it.
    public func sportStatsPages(for weekStart: Date, asOf today: Date = .now) -> [SportStatsPage] {
        let key = (model.activities.count, model.plans.count, model.workouts.count)
        let plans = plansFingerprint()
        let activities = activitiesFingerprint()
        let keyIsCurrent = sportStatsPagesCachesKey.map {
            $0.activityCount == key.0 && $0.planCount == key.1 && $0.workoutCount == key.2
                && $0.athlete == model.athlete && calendar.isDate($0.today, inSameDayAs: today)
                && $0.paceHistoryGeneration == paceHistoryGeneration && $0.plans == plans
                && $0.activities == activities
        } ?? false
        if !keyIsCurrent {
            sportStatsPagesCaches.removeAll()
            sportStatsPagesCachesKey = (key.0, key.1, key.2, model.athlete, today, paceHistoryGeneration, plans, activities)
        }
        if let cached = sportStatsPagesCaches[weekStart] {
            return cached
        }
        let pages = computeSportStatsPages(weekStart: weekStart, asOf: today)
        sportStatsPagesCaches[weekStart] = pages
        return pages
    }

    /// A hash of what each plan contributes to the week's totals — its id, date, workout and load
    /// override — for the stats and daily-load cache keys. The counts alone miss an edit in place.
    /// Cheap enough for the swipe path: a handful of fields per loaded plan, no statistics.
    private func plansFingerprint() -> Int {
        var hasher = Hasher()
        for plan in model.plans {
            hasher.combine(plan.id)
            hasher.combine(plan.date)
            hasher.combine(plan.workoutID)
            hasher.combine(plan.expectedLoadOverride)
        }
        return hasher.finalize()
    }

    /// A hash of what each activity contributes to the stats and daily load — id, sport, start,
    /// duration, distance, effort, plan link and heart-rate sample count — so a resync that changes
    /// activities in place (same count) still invalidates the caches. Cheap enough for the swipe path
    /// (a handful of fields per loaded activity, no statistics). Deliberately approximate: it counts
    /// heart-rate samples rather than hashing them, so a same-length series with other values goes
    /// unnoticed.
    private func activitiesFingerprint() -> Int {
        var hasher = Hasher()
        for activity in model.activities {
            hasher.combine(activity.id)
            hasher.combine(activity.sport)
            hasher.combine(activity.start)
            hasher.combine(activity.duration)
            hasher.combine(activity.distanceMeters)
            hasher.combine(activity.perceivedExertion)
            hasher.combine(activity.linkedPlanID)
            hasher.combine(activity.heartRate.count)
        }
        return hasher.finalize()
    }

    private func computeSportStatsPages(weekStart: Date, asOf today: Date) -> [SportStatsPage] {
        let current = periodStatsSplit(weekStart: weekStart, asOf: today)
        let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let previous = periodStatsSplit(weekStart: previousWeekStart, asOf: today)

        let mainSport = model.athlete.mainSport
        let otherSports = Set(current.actual.keys).union(current.planned.keys)
            .filter { $0 != mainSport }
            .sorted { lhs, rhs in
                let lhsDistance = current.actual[lhs]?.distanceMeters ?? 0
                let rhsDistance = current.actual[rhs]?.distanceMeters ?? 0
                return lhsDistance != rhsDistance ? lhsDistance > rhsDistance : lhs.displayName < rhs.displayName
            }
        let currentTotalLoad = current.actual.values.reduce(0) { $0 + $1.load }
        let previousTotalLoad = previous.actual.values.reduce(0) { $0 + $1.load }
        let plannedTotalLoad = current.planned.values.reduce(0) { $0 + $1.load }
        let previousPlannedTotalLoad = previous.planned.values.reduce(0) { $0 + $1.load }
        // The previous week's own *expected* total (performed + still-planned as of `today`), not
        // its performed-only total — for a week fully in the past this is the same number (nothing
        // of that week is still "planned" relative to `today`), but for two still-future weeks
        // shown back to back, the earlier one's performed total is always 0 (it hasn't happened
        // yet), which would make every later week's own change read as a meaningless "+∞%". Using
        // the previous week's expected total instead gives a real baseline in both cases: the
        // week right after the one containing `today` compares against that week's own
        // performed-so-far-plus-still-planned total, and a week further out compares against the
        // week before it's own still-fully-planned total.
        let previousExpectedTotalLoad = previousTotalLoad + previousPlannedTotalLoad
        let estimates = weekEstimates(weekStart: weekStart, asOf: today)
        let loadChangeFraction = Self.changeFraction(currentTotalLoad - previousExpectedTotalLoad, of: previousExpectedTotalLoad)
        let expectedLoadChangeFraction = Self.changeFraction(
            (currentTotalLoad + plannedTotalLoad) - previousExpectedTotalLoad, of: previousExpectedTotalLoad
        )

        return ([mainSport] + otherSports).map { sport in
            let currentActual = current.actual[sport] ?? Self.zeroSportStats(sport)
            let previousActual = previous.actual[sport] ?? Self.zeroSportStats(sport)
            let currentPlanned = current.planned[sport] ?? Self.zeroSportStats(sport)
            let previousPlanned = previous.planned[sport] ?? Self.zeroSportStats(sport)
            // See `previousExpectedTotalLoad`'s own doc comment for why this is performed+planned,
            // not performed-only.
            let previousExpectedDistance = previousActual.distanceMeters + previousPlanned.distanceMeters
            let previousExpectedTime = previousActual.time + previousPlanned.time
            return SportStatsPage(
                sport: sport,
                distanceMeters: currentActual.distanceMeters,
                time: currentActual.time,
                distanceChangeFraction: Self.changeFraction(
                    currentActual.distanceMeters - previousExpectedDistance, of: previousExpectedDistance
                ),
                timeChangeFraction: Self.changeFraction(currentActual.time - previousExpectedTime, of: previousExpectedTime),
                load: currentTotalLoad,
                loadChangeFraction: loadChangeFraction,
                polarizedSplit: currentActual.timeInZone.polarizedSplit,
                plannedDistanceMeters: currentPlanned.distanceMeters,
                plannedTime: currentPlanned.time,
                plannedLoad: plannedTotalLoad,
                plannedPolarizedSplit: currentPlanned.timeInZone.polarizedSplit,
                expectedDistanceChangeFraction: Self.changeFraction(
                    (currentActual.distanceMeters + currentPlanned.distanceMeters) - previousExpectedDistance,
                    of: previousExpectedDistance
                ),
                expectedTimeChangeFraction: Self.changeFraction(
                    (currentActual.time + currentPlanned.time) - previousExpectedTime, of: previousExpectedTime
                ),
                expectedLoadChangeFraction: expectedLoadChangeFraction,
                isLoadEstimated: estimates.performedLoad,
                isExpectedDistanceEstimated: estimates.plannedDistanceSports.contains(sport),
                isExpectedTimeEstimated: estimates.plannedTimeSports.contains(sport),
                isExpectedLoadEstimated: estimates.performedLoad || estimates.plannedLoad
            )
        }
    }

    /// Which of a week's stats-bar totals include an estimate (MVP2-8), from the same activities and
    /// plans `StatisticsCalculator.periodStatsSplit` counts: activities up to and including today,
    /// plans from today on whose workout is still in the library.
    private struct WeekEstimates {
        /// An activity's load was scored from perceived effort rather than heart rate.
        var performedLoad = false
        /// A plan's load is the estimator's figure rather than one the athlete set.
        var plannedLoad = false
        /// Sports with a plan whose distance is forecast from the athlete's paces.
        var plannedDistanceSports: Set<Sport> = []
        /// Sports with a plan whose duration is forecast from the athlete's paces.
        var plannedTimeSports: Set<Sport> = []
    }

    private func weekEstimates(weekStart: Date, asOf today: Date) -> WeekEstimates {
        let todayStart = calendar.startOfDay(for: today)
        let rangeStart = calendar.startOfDay(for: weekStart)
        let rangeEnd = calendar.date(byAdding: .day, value: 6, to: rangeStart) ?? rangeStart
        var estimates = WeekEstimates()

        estimates.performedLoad = model.activities.contains { activity in
            let day = calendar.startOfDay(for: activity.start)
            guard day >= rangeStart, day <= rangeEnd, day <= todayStart else { return false }
            return scoredLoad(for: activity)?.method.isEstimate ?? false
        }

        let workoutsByID = Dictionary(model.workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for plan in model.plans {
            let day = calendar.startOfDay(for: plan.date)
            guard day >= rangeStart, day <= rangeEnd, day >= todayStart,
                  let workout = workoutsByID[plan.workoutID]
            else { continue }
            if plan.isExpectedLoadEstimated {
                estimates.plannedLoad = true
            }
            if workout.isDistanceForecast {
                estimates.plannedDistanceSports.insert(workout.sport)
            }
            if workout.isDurationForecast {
                estimates.plannedTimeSports.insert(workout.sport)
            }
        }
        return estimates
    }

    /// Descriptive totals (every sport, not just one), performed and planned independently, for
    /// the calendar week starting `weekStart` — shared by ``sportStatsPages(asOf:)`` for both the
    /// displayed week and the previous one.
    private func periodStatsSplit(weekStart: Date, asOf today: Date) -> PeriodStatsSplit {
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return statisticsCalculator.periodStatsSplit(
            activities: model.activities,
            plans: model.plans,
            workouts: model.workouts,
            athlete: model.athlete,
            range: weekStart...weekEnd,
            asOf: today,
            paceHistory: paceHistory
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
        scoredLoad(for: activity)?.value
    }

    /// ``trainingLoad(for:)`` with how it was computed, so a card can mark a load scored from
    /// perceived effort rather than heart rate as an estimate (MVP2-8). `nil` when no calculator
    /// could score the activity.
    ///
    /// Cached per activity (``scoredLoadCache``), keyed on what scores it: its sport, start, duration,
    /// effort and heart-rate sample count; the athlete's settings clear it
    /// (`refreshCardCachesIfNeeded()`). Like ``activitiesFingerprint()``, it counts heart-rate samples
    /// rather than hashing them, so a same-length series with other values goes unnoticed.
    func scoredLoad(for activity: Activity) -> TrainingLoad? {
        refreshCardCachesIfNeeded()
        let inputs = [
            activity.sport.hashValue, activity.start.hashValue, activity.duration.hashValue,
            activity.perceivedExertion ?? -1, activity.heartRate.count,
        ]
        return scoredLoadCache.value(for: activity.id, inputs: inputs) {
            let summary = statisticsCalculator.summary(for: activity, athlete: model.athlete)
            return summary.load.confidence > 0 ? summary.load : nil
        }
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
    /// A changed activity fingerprint or athlete (MVP2-56) marks every currently cached week stale and due for
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
    ///
    /// - Parameters:
    ///   - today: The day the pace history is read up to (see ``refreshPaceHistoryIfNeeded(asOf:force:)``).
    ///   - activitiesChanged: `true` after an import, resync, dedup, link, join or delete, which can
    ///     change the stored activities the pace history is built from without anything the week
    ///     view itself keys on changing; forces a pace-history refresh.
    public func refreshWeekCachesIfNeeded(asOf today: Date = .now, activitiesChanged: Bool = false) async {
        let fingerprint = histogramFingerprint()
        let inputsChanged = weekGraphCachesFingerprint != fingerprint
            || weekGraphCachesAthlete != model.athlete
        if inputsChanged {
            weekGraphCachesFingerprint = fingerprint
            weekGraphCachesAthlete = model.athlete
        }
        let window = cachedWeekStarts
        let windowSet = Set(window)
        weekGraphCaches = weekGraphCaches.filter { windowSet.contains($0.key) }

        let displayedWeekStart = self.displayedWeekStart
        if inputsChanged || weekGraphCaches[displayedWeekStart] == nil {
            await cacheWeekGraph(weekStart: displayedWeekStart, priority: .userInitiated)
        }
        for weekStart in window where weekStart != displayedWeekStart
            && (inputsChanged || weekGraphCaches[weekStart] == nil) {
            await cacheWeekGraph(weekStart: weekStart, priority: .utility)
        }
        await refreshPaceHistoryIfNeeded(asOf: today, force: activitiesChanged)
    }

    /// Computes one week's heart-rate histogram off the main actor and stores it in
    /// ``weekGraphCaches``, unless the 3-week window has moved on again by the time it lands (a
    /// stale result for a week no longer near ``displayedWeekStart`` is simply dropped, not
    /// cached).
    private func cacheWeekGraph(weekStart: Date, priority: TaskPriority) async {
        let fingerprint = weekGraphCachesFingerprint
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
        guard isStillCacheable(weekStart, fingerprint: fingerprint), athlete == model.athlete else { return }
        weekGraphCaches[weekStart] = histogram
    }

    /// Whether a background computation for `weekStart` (started under `fingerprint`, the one
    /// ``refreshWeekCachesIfNeeded(asOf:activitiesChanged:)`` had just stored) is still worth
    /// storing — `false` once either has moved on, since the result is now either stale (a
    /// subsequent import changed the underlying activities) or for a week that's fallen outside the
    /// 3-week window this cache keeps.
    ///
    /// Compares against the stored ``weekGraphCachesFingerprint`` rather than re-hashing every
    /// sample: a refresh that sees changed data stores its new fingerprint first, so an older
    /// result is dropped here, and data that changed before any refresh is caught by the next one.
    private func isStillCacheable(_ weekStart: Date, fingerprint: Int?) -> Bool {
        cachedWeekStarts.contains(weekStart) && fingerprint == weekGraphCachesFingerprint
    }

    /// A hash of what the heart-rate histogram reads from each activity — id, start, duration and
    /// every heart-rate sample — so activities changed in place (same count) still invalidate
    /// ``weekGraphCaches`` (MVP2-130). Unlike ``activitiesFingerprint()`` it hashes the samples
    /// themselves: it only runs when the week caches refresh, not on the week-swipe path, and the
    /// histogram is exactly what those samples feed.
    private func histogramFingerprint() -> Int {
        var hasher = Hasher()
        for activity in model.activities {
            hasher.combine(activity.id)
            hasher.combine(activity.start)
            hasher.combine(activity.duration)
            hasher.combine(activity.heartRate)
        }
        return hasher.finalize()
    }

    /// `true` if `day` is `today`'s calendar day in the athlete's timezone — used by the day
    /// list's weekday pills (MVP1-39) to highlight today's row.
    public func isToday(_ day: Date, asOf today: Date = .now) -> Bool {
        calendar.isDate(day, inSameDayAs: today)
    }

    /// `true` if `day` is strictly before `today`'s calendar day, in the athlete's timezone — a
    /// planned workout only makes sense for today or later, so `WeekView`'s "add planned workout"
    /// affordance disables itself (MVP2-15) on a day this returns `true` for, rather than opening
    /// a sheet for a day that's already happened.
    public func isPast(_ day: Date, asOf today: Date = .now) -> Bool {
        Self.isPast(day, asOf: today, calendar: calendar)
    }

    /// ``isPast(_:asOf:)`` for any `calendar`, so code without a `WeekViewModel`'s own calendar
    /// (the search tab's missed plans, MVP2-21) applies the same rule.
    static func isPast(_ day: Date, asOf today: Date, calendar: Calendar) -> Bool {
        calendar.startOfDay(for: day) < calendar.startOfDay(for: today)
    }

    /// The detail view model for `activity`, pushed when it's tapped in the day list.
    public func activityDetailViewModel(for activity: Activity) -> ActivityDetailViewModel {
        ActivityDetailViewModel(
            activity: activity, athlete: model.athlete, overlapContext: overlapContext(for: activity),
            planLinkContext: planLinkContext(for: activity)
        )
    }

    /// The view model for the "Create Planned Workout" sheet (MVP2-15), opened from a day row's
    /// add affordance — `date` defaults the sheet to that day, still editable inside it.
    public func plannedWorkoutSheetViewModel(date: Date) -> PlannedWorkoutSheetViewModel {
        let viewModel = PlannedWorkoutSheetViewModel(
            model: model, date: date, scheduler: plannedWorkoutScheduler
        )
        viewModel.onPlansChanged = { [weak self] in self?.requestWatchSync() }
        return viewModel
    }

    /// The view model for the Library tab (MVP2-21). A plan made from the tab uses the Watch
    /// setting at the time (MVP2-118) and runs the Watch sync afterwards.
    public func workoutLibraryViewModel() -> WorkoutLibraryViewModel {
        // `nil` while sending to the Watch is off, so no fallback to the live bridge here.
        let viewModel = WorkoutLibraryViewModel(model: model) { [weak self] in
            guard let self else { return nil }
            return self.plannedWorkoutScheduler
        }
        viewModel.onPlansChanged = { [weak self] in self?.requestWatchSync() }
        return viewModel
    }

    /// The view model for the search tab (MVP2-21), sharing `library` with the Library tab. Opening
    /// a result first loads this model around its day (``ensureLoaded(around:asOf:)``).
    public func searchViewModel(library: WorkoutLibraryViewModel) -> SearchViewModel {
        let viewModel = SearchViewModel(model: model, library: library)
        viewModel.prepareDetail = { [weak self] date in await self?.ensureLoaded(around: date) }
        return viewModel
    }

    /// The view model for the "Add Race" sheet (MVP2-17), opened from a day row's add affordance
    /// alongside ``plannedWorkoutSheetViewModel(date:)`` — `date` defaults the sheet to that day,
    /// still editable inside it.
    public func raceSheetViewModel(date: Date) -> RaceSheetViewModel {
        RaceSheetViewModel(model: model, date: date)
    }

    /// The view model for the week view's "Export Calendar" sheet (MVP2-100), opened from the
    /// toolbar's share button.
    public func calendarExportViewModel() -> CalendarExportViewModel {
        CalendarExportViewModel(model: model)
    }

    /// The view model for the week view's "Import Calendar" sheet (MVP2-103), opened from the
    /// toolbar's import button.
    public func calendarImportViewModel() -> CalendarImportViewModel {
        let viewModel = CalendarImportViewModel(model: model)
        viewModel.onPlansChanged = { [weak self] in self?.requestWatchSync() }
        return viewModel
    }

    /// The view model for the detail sheet shown when `plan`'s card is tapped (MVP2-38).
    ///
    /// - Parameters:
    ///   - plan: The plan whose card was tapped.
    ///   - today: Decides whether the plan was missed, for its Apple Watch status (MVP2-122); fixed
    ///     when the sheet opens.
    public func plannedWorkoutDetailViewModel(
        for plan: PlannedActivity, asOf today: Date = .now
    ) -> PlannedWorkoutDetailViewModel {
        let viewModel = PlannedWorkoutDetailViewModel(
            model: model, plan: plan, scheduler: plannedWorkoutScheduler
        )
        viewModel.onPlansChanged = { [weak self] in self?.requestWatchSync() }
        viewModel.watchStatus = { [weak self] in self?.watchStatus(for: $0, asOf: today) }
        return viewModel
    }

    /// What the planned-workout sheets schedule a saved plan with: the Watch sync's scheduler, or
    /// none while the athlete has turned sending to the Watch off (MVP2-118), so a save neither
    /// checks the workout against the Watch nor schedules it. Without a sync (WorkoutKit
    /// unavailable, or a test that didn't pass one) it's the default, as before.
    var plannedWorkoutScheduler: (any PlannedWorkoutScheduling)? {
        guard let watchSync else { return PlannedWorkoutSchedulers.live }
        return watchSync.editingScheduler
    }

    /// Runs the Watch sync (MVP2-55) after a plan is saved, deleted or imported, or a plan's link to
    /// an activity may have changed (MVP2-116): a linked plan's entry is kept as done, and an
    /// unlinked one in the window goes back on the Watch. A no-op without a sync.
    ///
    /// - Parameter today: The action's injected day, so the sync's 7-day window matches it.
    func requestWatchSync(asOf today: Date = .now) {
        guard let watchSync else { return }
        pendingWatchSync = watchSync.requestSync(asOf: today)
    }

    /// Whether the week view shows the banner saying planned workouts won't reach the Watch because
    /// the athlete declined permission (MVP2-117). `false` without a sync.
    public var showsWatchPermissionBanner: Bool {
        watchSync?.showsPermissionDeniedBanner ?? false
    }

    /// Hides the Watch permission banner until permission is granted and later declined again.
    func dismissWatchPermissionBanner() {
        watchSync?.dismissPermissionDeniedBanner()
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

    /// Loads the weeks around `date` into `model` as well as the displayed ones, so a detail sheet
    /// opened from the search tab (MVP2-21) for a plan or activity outside the week view's window
    /// finds its plan, workout, link and overlaps in `model`, and follows an edit made in it.
    /// Loads the *union* with the current window, for the same reason as ``metrics(in:asOf:)``.
    /// A failed load leaves `model` as it was, and the sheet opens anyway.
    public func ensureLoaded(around date: Date, asOf today: Date = .now) async {
        let range = Self.loadRange(for: Self.weekStart(containing: date, calendar: calendar), calendar: calendar)
        let currentLoadRange = Self.loadRange(for: displayedWeekStart, calendar: calendar)
        if currentLoadRange.contains(range.lowerBound), currentLoadRange.contains(range.upperBound) { return }
        let unionRange = min(range.lowerBound, currentLoadRange.lowerBound)...max(range.upperBound, currentLoadRange.upperBound)
        try? await model.load(in: unionRange, asOf: today)
        await refreshWeekCachesIfNeeded(asOf: today)
    }

    /// Loads ``loadRange(for:calendar:)`` for ``displayedWeekStart`` from the stores into `model`
    /// — wider than ``chartRange`` itself, so `WeekView`'s neighbor carousel pages already have
    /// their own complete chart data before the athlete ever swipes to them (MVP1-32). Errors are
    /// swallowed — a failed load leaves `model` exactly as it was (`TrainingModel.load(in:)`'s own
    /// guarantee), so there's nothing for the view to reconcile; MVP 1 has no load-failure UI.
    public func load(asOf today: Date = .now) async {
        try? await model.load(in: Self.loadRange(for: displayedWeekStart, calendar: calendar), asOf: today)
        await refreshWeekCachesIfNeeded(asOf: today)
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
        await refreshWeekCachesIfNeeded(asOf: today)
        return model.metrics.filter { range.contains($0.day) }.sorted { $0.day < $1.day }
    }

    /// The metrics, daily-load split and races for `range`, for a metric detail chart's buffer
    /// (MVP2-137).
    ///
    /// The metrics and load are fetched first, which loads `range` into the model; the races are
    /// read after that, so a caller can't read them before they're loaded. Another load that lands
    /// between those steps (the week view navigating, say) could still replace the model's races
    /// before they're read; the metrics have the same property. See ``metrics(in:asOf:)`` for why
    /// loading `range` keeps what the displayed week needs.
    ///
    /// Loads `range` twice, once for the metrics and once for the load split.
    func chartBuffer(in range: ClosedRange<Date>, asOf today: Date = .now) async -> ChartBuffer {
        let metrics = await metrics(in: range, asOf: today)
        let dailyLoadSplit = await dailyLoadSplit(in: range, asOf: today)
        return ChartBuffer(metrics: metrics, dailyLoadSplit: dailyLoadSplit, races: chartRaces(in: range))
    }

    /// Runs a pull-to-refresh import via `refresher`. `TrainingModel.importActivities(from:)`
    /// already reloads `activities` and recomputes `metrics` for whatever range was last loaded
    /// (``chartRange``, assuming ``load(asOf:)`` already ran once for it), so nothing further is
    /// needed here. Failures fail silently back to the pre-refresh state (design doc §3.4).
    ///
    /// Then requests a Watch sync (MVP2-116), since an import can link or unlink a plan. It does so
    /// even when the import fails: the sync is idempotent, and still moves the window on.
    public func refresh(asOf today: Date = .now) async {
        isRefreshing = true
        defer { isRefreshing = false }
        try? await refresher.refreshActivities(asOf: today)
        await refreshWeekCachesIfNeeded(asOf: today, activitiesChanged: true)
        requestWatchSync(asOf: today)
        await checkForMaxHeartRateSuggestion(asOf: today)
    }

    /// Brings the caches up to date after workouts were imported without this view model, by the
    /// background import (MVP2-121, see `TrainingAppEnvironment.importArrivedWorkouts(asOf:)`), which
    /// has already imported them and synced the Watch. What ``refresh(asOf:)`` does after its own
    /// import: the week caches and pace history, and the max heart rate suggestion.
    ///
    /// - Parameter today: Passed through to the cache refresh and the suggestion check.
    public func activitiesImportedElsewhere(asOf today: Date = .now) async {
        await refreshWeekCachesIfNeeded(asOf: today, activitiesChanged: true)
        await checkForMaxHeartRateSuggestion(asOf: today)
    }

    /// The empty-state "Connect Health data" action (design doc §2.1): requests authorization,
    /// then runs the same import ``refresh(asOf:)`` does. Failures fail silently, same as
    /// ``refresh(asOf:)`` — MVP 1 has no error UI, and the empty state simply stays empty.
    ///
    /// Then requests a Watch sync (MVP2-116) once the import succeeded, since it can link plans.
    public func connectHealthData(asOf today: Date = .now) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await refresher.requestAuthorization()
            try await refresher.refreshActivities(asOf: today)
        } catch {
            return
        }
        await refreshWeekCachesIfNeeded(asOf: today, activitiesChanged: true)
        requestWatchSync(asOf: today)
        await checkForMaxHeartRateSuggestion(asOf: today)
    }

    /// The athlete screen's "Force Full Resync" action (design doc §2.3): re-imports every
    /// matching activity from scratch via `refresher.resyncActivities(asOf:)`, so a mapping fix
    /// (e.g. a `Sport` case that used to fall back to `.other`) reaches activities that were
    /// already imported before the fix — `Sport` is resolved once at import time and persisted,
    /// not recomputed on read. Failures fail silently, same as ``refresh(asOf:)`` — MVP 1 has no
    /// error UI.
    ///
    /// Then requests a Watch sync (MVP2-116), since an import can link or unlink a plan. Like
    /// ``refresh(asOf:)``, it does so even when the import fails.
    public func resyncActivities(asOf today: Date = .now) async {
        isResyncing = true
        defer { isResyncing = false }
        try? await refresher.resyncActivities(asOf: today)
        await refreshWeekCachesIfNeeded(asOf: today, activitiesChanged: true)
        requestWatchSync(asOf: today)
        await checkForMaxHeartRateSuggestion(asOf: today)
    }

    /// The athlete screen's "Deduplicate Activities" action (MVP1-44): removes duplicate
    /// `Activity` records left over from before the concurrent-import race that produced them was
    /// fixed (MVP1-26) — including duplicates already synced to CloudKit before that fix, which
    /// deleting and reinstalling the app doesn't clear on its own. Goes straight through `model`
    /// rather than `refresher`, since this is a plain store cleanup with no `ActivityImporting`
    /// dependency. Failures fail silently, same as ``resyncActivities(asOf:)`` — MVP 1 has no
    /// error UI.
    ///
    /// Then requests a Watch sync (MVP2-116), since the change can link or unlink a plan.
    public func deduplicateActivities(asOf today: Date = .now) async {
        isDeduplicating = true
        defer { isDeduplicating = false }
        try? await model.deduplicateActivities(asOf: today)
        await refreshWeekCachesIfNeeded(asOf: today, activitiesChanged: true)
        requestWatchSync(asOf: today)
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
