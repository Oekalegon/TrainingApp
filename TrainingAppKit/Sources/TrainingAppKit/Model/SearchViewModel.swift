import Foundation
import TrainingCore

/// Drives the search tab (MVP2-21, design doc §2.5): instant results across the workout templates,
/// the planned workouts and the activities as the athlete types in the tab bar's search field,
/// which is there from every tab.
///
/// Plans and activities come from the stores, over all dates, read by ``reload()``:
/// `TrainingModel` only holds the week view's loaded window. Activities are kept as light
/// ``ActivityResult``s, read as `ActivityListItem`s so the samples are never built; ``activity(id:)`` fetches the full one when a result
/// is opened, and the week view's model is loaded around a result's day before its detail sheet
/// opens (``prepareDetail``). Each result's searchable text (names, sport, dates) is written once at reload, so
/// typing only compares strings. Templates come from ``library``.
@Observable
@MainActor
public final class SearchViewModel {
    private let model: TrainingModel
    /// The Library tab's view model, for the template results and their detail screen.
    public let library: WorkoutLibraryViewModel

    /// Where a planned workout stands, for its result's subtitle.
    public enum PlanStatus: Equatable, Sendable {
        /// Due today or later, not done yet.
        case upcoming
        /// An activity is linked to it.
        case done
        /// Its day has passed with no activity linked — the week view's missed card
        /// (`WeekViewModel.isMissed(_:asOf:calendar:)`).
        case missed
    }

    /// A planned workout in the results.
    public struct PlanResult: Identifiable, Equatable, Sendable {
        /// The plan itself, for its detail sheet.
        public let plan: PlannedActivity
        /// Its workout's name, or "Planned workout" when the workout is gone.
        public let name: String
        /// Its workout's sport; `nil` when the workout is gone.
        public let sport: Sport?
        /// `true` once an activity is linked to it.
        public let isDone: Bool
        /// Name, sport and dates, written at reload for matching.
        let searchFields: [String]

        public var id: UUID { plan.id }
    }

    /// An activity in the results — what its row shows, without the activity's samples.
    public struct ActivityResult: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let sport: Sport
        public let start: Date
        public let duration: TimeInterval
        public let distanceMeters: Double?
        /// The name of the planned workout it's linked to, if any — the row's title when set.
        public let planName: String?
        /// Sport, linked plan name and dates, written at reload for matching.
        let searchFields: [String]
    }

    /// The results for one query, each kind newest first.
    public struct Results: Equatable, Sendable {
        public let templates: [WorkoutLibraryViewModel.Entry]
        public let plans: [PlanResult]
        public let activities: [ActivityResult]

        /// `true` when nothing matched.
        public var isEmpty: Bool { templates.isEmpty && plans.isEmpty && activities.isEmpty }
    }

    /// Every plan, as of the last ``reload()``, newest first.
    public private(set) var plans: [PlanResult] = []
    /// Every activity, as of the last ``reload()``, newest first.
    public private(set) var activities: [ActivityResult] = []
    /// Set when ``reload()`` fails.
    public private(set) var loadError: String?
    /// Set when ``activity(id:)`` fails; the tab shows it as an alert and clears it with
    /// ``clearActivityError()``.
    public private(set) var activityError: String?
    /// `true` while ``open(_:)`` or ``openActivity(id:)`` is getting a result ready, so another
    /// tap is ignored until it's done.
    public private(set) var isOpening = false
    /// Loads the week view's model around a date before a detail sheet opens on it. Set by
    /// `WeekViewModel.searchViewModel(library:)` to `ensureLoaded(around:)`: the detail sheets read
    /// `TrainingModel`, which otherwise only holds the week view's window, so an older plan or
    /// activity would open without its plan, workout, link or overlaps, and not follow an edit.
    @ObservationIgnored
    public var prepareDetail: (@MainActor (Date) async -> Void)?
    /// Set when a detail sheet opened from the results changed something, so closing it reloads.
    @ObservationIgnored private var hasChanges = false
    /// Counts ``reload()`` calls, so a reload that finishes after a later one started drops its
    /// older snapshot instead of overwriting the newer one.
    @ObservationIgnored private var reloadGeneration = 0

    /// Creates a search view model.
    ///
    /// - Parameters:
    ///   - model: The training model whose stores are searched.
    ///   - library: The Library tab's view model, shared so both show the same plan counts.
    public init(model: TrainingModel, library: WorkoutLibraryViewModel) {
        self.model = model
        self.library = library
    }

    /// Reads every plan, workout and activity from the stores, and reloads ``library``.
    public func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        await library.reload()
        do {
            let stores = model.stores
            let everything = Date.distantPast...Date.distantFuture
            let allPlans = try await stores.planStore.plans(in: everything)
            let workouts = try await stores.workoutStore.workouts()
            let allActivities = try await stores.activityStore.activityListItems(in: everything)

            guard generation == reloadGeneration else { return }

            let workoutsByID = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let plansByID = Dictionary(allPlans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            plans = allPlans
                .map { plan in
                    let workout = workoutsByID[plan.workoutID]
                    let name = workout?.name ?? "Planned workout"
                    return PlanResult(
                        plan: plan, name: name, sport: workout?.sport,
                        isDone: plan.completedActivityID != nil,
                        searchFields: [name, workout?.sport.displayName ?? ""] + dateFields(plan.date)
                    )
                }
                .sorted { $0.plan.date > $1.plan.date }
            activities = allActivities
                .map { activity in
                    let plan = activity.linkedPlanID.flatMap { plansByID[$0] }
                    let planName = plan.flatMap { workoutsByID[$0.workoutID]?.name }
                    return ActivityResult(
                        id: activity.id, sport: activity.sport, start: activity.start,
                        duration: activity.duration, distanceMeters: activity.distanceMeters,
                        planName: planName,
                        searchFields: [activity.sport.displayName, planName ?? ""] + dateFields(activity.start)
                    )
                }
                .sorted { $0.start > $1.start }
            loadError = nil
        } catch {
            guard generation == reloadGeneration else { return }
            loadError = "Couldn't load your workouts: \(error.localizedDescription)"
        }
    }

    /// A date as the results match it: written out in full and abbreviated, in the athlete's
    /// timezone and the device's locale, e.g. "Saturday, September 20, 2025" and "Sep 20".
    private func dateFields(_ date: Date) -> [String] {
        var long = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day().year()
        long.timeZone = timeZone
        var short = Date.FormatStyle.dateTime.month(.abbreviated).day()
        short.timeZone = timeZone
        return [date.formatted(long), date.formatted(short)]
    }

    /// Where `result`'s plan stands on `today`: done, missed or upcoming, by the week view's rule.
    public func status(of result: PlanResult, asOf today: Date = .now) -> PlanStatus {
        if result.isDone { return .done }
        let calendar = WeekViewModel.calendar(for: model.athlete)
        return WeekViewModel.isMissed(result.plan, asOf: today, calendar: calendar) ? .missed : .upcoming
    }

    /// The athlete's timezone — results' dates are matched and shown in it.
    public var timeZone: TimeZone { model.athlete.timeZone }

    /// Everything matching `query`; empty for a blank query.
    ///
    /// - A template matches on its name, default title or sport (see
    ///   ``WorkoutLibraryViewModel/entries(matching:asOf:)``).
    /// - A planned workout matches on its workout's name, its sport or its date.
    /// - An activity matches on its sport, its date or the name of the planned workout it's
    ///   linked to.
    ///
    /// Every typed word must match one of those, ignoring case and diacritics. A date matches as
    /// written in the athlete's timezone and locale, e.g. "Saturday, September 20, 2025" or
    /// "Sep 20", so "september" or "2025" work. The fields were written at ``reload()``, so this
    /// only compares strings.
    ///
    /// - Parameters:
    ///   - query: What the athlete typed.
    ///   - today: Decides which plans count as upcoming in the template results.
    public func results(for query: String, asOf today: Date = .now) -> Results {
        let search = SearchQuery(query)
        guard !search.isEmpty else { return Results(templates: [], plans: [], activities: []) }
        return Results(
            templates: library.entries(matching: query, asOf: today),
            plans: plans.filter { search.matches($0.searchFields) },
            activities: activities.filter { search.matches($0.searchFields) }
        )
    }

    /// Gets a planned-workout result ready for its detail sheet: loads the model around its day
    /// (``prepareDetail``) and returns the plan to present; `nil` while another result is opening.
    public func open(_ result: PlanResult) async -> PlannedActivity? {
        guard !isOpening else { return nil }
        isOpening = true
        defer { isOpening = false }
        await prepareDetail?(result.plan.date)
        return result.plan
    }

    /// Gets an activity result ready for its detail sheet: fetches the full activity, then loads
    /// the model around its day (``prepareDetail``). `nil` while another result is opening, or when
    /// the fetch fails (then ``activityError`` says why).
    public func openActivity(id: UUID) async -> Activity? {
        guard !isOpening else { return nil }
        isOpening = true
        defer { isOpening = false }
        guard let activity = await activity(id: id) else { return nil }
        await prepareDetail?(activity.start)
        return activity
    }

    /// Records that a detail sheet opened from the results saved, deleted, linked or joined
    /// something, so ``reloadIfChanged()`` reloads when it closes.
    public func markChanged() {
        hasChanges = true
    }

    /// Reloads after a detail sheet closes, only if it changed something (``markChanged()``):
    /// a reload reads every plan and activity, so closing a sheet that only looked doesn't pay for one.
    public func reloadIfChanged() async {
        guard hasChanges else { return }
        hasChanges = false
        await reload()
    }

    /// The full activity for a result, with its samples; `nil` when it's gone or can't be read
    /// (then ``activityError`` says why).
    public func activity(id: UUID) async -> Activity? {
        do {
            guard let activity = try await model.stores.activityStore.activity(id: id) else {
                activityError = "This activity no longer exists."
                return nil
            }
            return activity
        } catch {
            activityError = "Couldn't open this activity: \(error.localizedDescription)"
            return nil
        }
    }

    /// Clears ``activityError`` once its alert is dismissed.
    public func clearActivityError() {
        activityError = nil
    }
}
