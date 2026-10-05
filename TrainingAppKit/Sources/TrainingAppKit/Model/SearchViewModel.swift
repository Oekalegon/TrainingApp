import Foundation
import TrainingCore

/// Drives the search tab (MVP2-21, design doc §2.5): instant results across the workout templates,
/// the planned workouts and the activities as the athlete types in the tab bar's search field,
/// which is there from every tab.
///
/// Plans and activities come from the stores, over all dates, read by ``reload()``:
/// `TrainingModel` only holds the week view's loaded window. Activities are kept as light
/// ``ActivityResult``s without their samples; ``activity(id:)`` fetches the full one when a result
/// is opened. Templates come from ``library``.
@Observable
@MainActor
public final class SearchViewModel {
    private let model: TrainingModel
    /// The Library tab's view model, for the template results and their detail screen.
    public let library: WorkoutLibraryViewModel

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
    /// Set when ``reload()`` or ``activity(id:)`` fails.
    public private(set) var loadError: String?

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
        await library.reload()
        do {
            let stores = model.stores
            let everything = Date.distantPast...Date.distantFuture
            let allPlans = try await stores.planStore.plans(in: everything)
            let workouts = try await stores.workoutStore.workouts()
            let allActivities = try await stores.activityStore.activities(in: everything)

            let workoutsByID = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let plansByID = Dictionary(allPlans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            plans = allPlans
                .map { plan in
                    let workout = workoutsByID[plan.workoutID]
                    return PlanResult(
                        plan: plan, name: workout?.name ?? "Planned workout", sport: workout?.sport,
                        isDone: plan.completedActivityID != nil
                    )
                }
                .sorted { $0.plan.date > $1.plan.date }
            activities = allActivities
                .map { activity in
                    let plan = activity.linkedPlanID.flatMap { plansByID[$0] }
                    return ActivityResult(
                        id: activity.id, sport: activity.sport, start: activity.start,
                        duration: activity.duration, distanceMeters: activity.distanceMeters,
                        planName: plan.flatMap { workoutsByID[$0.workoutID]?.name }
                    )
                }
                .sorted { $0.start > $1.start }
            loadError = nil
        } catch {
            loadError = "Couldn't load your workouts: \(error.localizedDescription)"
        }
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
    /// "Sep 20", so "september" or "2025" work.
    ///
    /// - Parameters:
    ///   - query: What the athlete typed.
    ///   - today: Decides which plans count as upcoming in the template results.
    public func results(for query: String, asOf today: Date = .now) -> Results {
        let search = SearchQuery(query)
        guard !search.isEmpty else { return Results(templates: [], plans: [], activities: []) }
        let longDate = dateFormat(Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day().year())
        let shortDate = dateFormat(Date.FormatStyle.dateTime.month(.abbreviated).day())
        func dateFields(_ date: Date) -> [String] {
            [date.formatted(longDate), date.formatted(shortDate)]
        }
        return Results(
            templates: library.entries(matching: query, asOf: today),
            plans: plans.filter { result in
                search.matches([result.name, result.sport?.displayName ?? ""] + dateFields(result.plan.date))
            },
            activities: activities.filter { result in
                search.matches([result.sport.displayName, result.planName ?? ""] + dateFields(result.start))
            }
        )
    }

    private func dateFormat(_ format: Date.FormatStyle) -> Date.FormatStyle {
        var format = format
        format.timeZone = timeZone
        return format
    }

    /// The full activity for a result, with its samples, for its detail sheet; `nil` when it's
    /// gone or can't be read (then ``loadError`` says why).
    public func activity(id: UUID) async -> Activity? {
        do {
            return try await model.stores.activityStore.activity(id: id)
        } catch {
            loadError = "Couldn't open this activity: \(error.localizedDescription)"
            return nil
        }
    }
}
