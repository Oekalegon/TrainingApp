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

    /// The first day (in the athlete's timezone, respecting `weekStartsOn`) of the week currently
    /// on screen.
    public private(set) var displayedWeekStart: Date
    /// `true` while a pull-to-refresh import is in flight.
    public private(set) var isRefreshing = false

    /// Creates a week view model showing the week containing `today`.
    public init(model: TrainingModel, refresher: any ActivityRefreshing, today: Date = .now) {
        self.model = model
        self.refresher = refresher
        let calendar = Self.calendar(for: model.athlete)
        self.calendar = calendar
        self.displayedWeekStart = Self.weekStart(containing: today, calendar: calendar)
    }

    /// `true` until a HealthKit import has ever completed for this athlete — the empty-state
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

    /// The 7 days of the displayed week, starting `displayedWeekStart`.
    public var weekDates: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: displayedWeekStart) }
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
        displayedWeekStart = Self.weekStart(containing: today, calendar: calendar)
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

    static func calendar(for athlete: AthleteProfile) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        calendar.firstWeekday = athlete.weekStartsOn.rawValue
        return calendar
    }

    static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }
}
