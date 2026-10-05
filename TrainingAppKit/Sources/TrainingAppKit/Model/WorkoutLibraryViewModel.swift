import Foundation
import TrainingCore

/// Drives the Library tab (MVP2-21, design doc §2.4): the workout templates the athlete can plan,
/// grouped by sport, each with its default title, its steps at the default parameter values, an
/// estimated load, and how it's used in the plan so far. The tab will also host MVP5's plan builder.
///
/// The library shows templates rather than `TrainingModel.workouts`: saving a planned workout
/// instantiates its own ``StructuredWorkout`` (MVP2-15), so the stored workouts are per-plan copies,
/// not a list worth browsing. A template's plans are found through the workouts'
/// ``StructuredWorkout/templateID``.
///
/// The counts come from every plan in the store, read by ``reload()``: `TrainingModel.plans` only
/// holds the week view's loaded window. The tab reloads each time it appears and after a plan is
/// saved from it. The athlete is read live, for the load estimates.
@Observable
@MainActor
public final class WorkoutLibraryViewModel {
    private let model: TrainingModel
    private let estimator: any PlannedLoadEstimator
    private let scheduler: @MainActor () -> (any PlannedWorkoutScheduling)?
    /// Called after a plan is saved from the tab, so the Watch sync can run again (MVP2-55).
    @ObservationIgnored
    public var onPlansChanged: (@MainActor () -> Void)?

    /// Every plan in the store, as of the last ``reload()``.
    public private(set) var plans: [PlannedActivity] = []
    /// Every workout in the store, as of the last ``reload()``.
    public private(set) var workouts: [StructuredWorkout] = []
    /// Set when ``reload()`` fails; the counts then stay as they were.
    public private(set) var loadError: String?
    /// The reload started after a plan is saved from the tab; tests await it.
    @ObservationIgnored
    private(set) var pendingReload: Task<Void, Never>?
    /// Counts ``reload()`` calls, so a reload that finishes after a later one started (the tab's
    /// `.task` and ``pendingReload`` can overlap) drops its older snapshot.
    @ObservationIgnored private var reloadGeneration = 0

    /// The templates the library offers — the built-in library only, as in the planned-workout
    /// sheet's picker; custom templates come with the Structured Workout creator.
    public let templates: [WorkoutTemplate]
    /// How distances are written in default titles; defaults to the device's measurement system.
    public var distanceSystem: DistanceSystem = Locale.current.measurementSystem == .metric ? .metric : .imperial

    /// One template in the library, with what its row and detail screen show.
    public struct Entry: Identifiable, Equatable, Sendable {
        /// The template itself.
        public let template: WorkoutTemplate
        /// The template's generated title at its default values (MVP2-110), e.g. "40min Easy Run".
        public let defaultTitle: String
        /// One line per block at the default values, e.g. `"4 × Work 8:00, Recovery 2:00"`; empty
        /// when the template can't be instantiated.
        public let stepLines: [String]
        /// The estimated load in TRIMP at the default values; `nil` when it can't be estimated.
        /// Always an estimate, so shown with a "~" (MVP2-8).
        public let expectedLoad: Double?
        /// How many plans use a workout made from this template, done and missed ones included.
        public let planCount: Int
        /// The day of the earliest plan from this template that's due today or later and not yet
        /// done; `nil` when there's none.
        public let nextPlannedDate: Date?

        public var id: UUID { template.id }
    }

    /// The entries for one sport, in the order the templates are listed.
    public struct SportSection: Identifiable, Equatable, Sendable {
        /// The sport every entry in this section is for.
        public let sport: Sport
        /// The section's templates.
        public let entries: [Entry]

        public var id: Sport { sport }
    }

    /// Creates a library view model.
    ///
    /// - Parameters:
    ///   - model: The training model whose plans and athlete the entries are worked out from, and
    ///     that a plan made from the tab is saved into.
    ///   - templates: The templates to list; defaults to the built-in library.
    ///   - estimator: Estimates each entry's load; defaults to the same ``TRIMPPlanEstimator`` the
    ///     planned-workout sheet uses, so the two agree.
    ///   - scheduler: Asked for the planned-workout sheet's scheduler each time one opens (see
    ///     ``makePlanner(for:date:)``), so it follows the Watch setting: `WeekViewModel` returns
    ///     `nil` while sending to the Watch is turned off (MVP2-118). Tests return `nil`.
    public init(
        model: TrainingModel,
        templates: [WorkoutTemplate] = BuiltInWorkoutTemplates.all,
        estimator: any PlannedLoadEstimator = TRIMPPlanEstimator(),
        scheduler: @escaping @MainActor () -> (any PlannedWorkoutScheduling)? = { PlannedWorkoutSchedulers.live }
    ) {
        self.model = model
        self.templates = templates
        self.estimator = estimator
        self.scheduler = scheduler
    }

    /// Reads every plan and workout from the store, for the plan counts.
    public func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        do {
            let stores = model.stores
            let plans = try await stores.planStore.plans(in: Date.distantPast...Date.distantFuture)
            let workouts = try await stores.workoutStore.workouts()
            guard generation == reloadGeneration else { return }
            self.plans = plans
            self.workouts = workouts
            loadError = nil
        } catch {
            guard generation == reloadGeneration else { return }
            loadError = "Couldn't load your plans: \(error.localizedDescription)"
        }
    }

    /// The library's templates grouped by sport, sections in the order each sport first appears in
    /// ``templates``.
    ///
    /// - Parameter today: Decides which plans count as upcoming for ``Entry/nextPlannedDate``.
    public func sections(asOf today: Date = .now) -> [SportSection] {
        let entries = self.entries(asOf: today)
        var sports: [Sport] = []
        for entry in entries where !sports.contains(entry.template.sport) {
            sports.append(entry.template.sport)
        }
        return sports.map { sport in
            SportSection(sport: sport, entries: entries.filter { $0.template.sport == sport })
        }
    }

    /// The entries matching `query`, in ``templates``' order, for the search tab (MVP2-21). A
    /// template matches when its name, its default title or its sport's name contains every word
    /// of `query`, ignoring case and diacritics; an empty query matches all.
    ///
    /// - Parameters:
    ///   - query: What the athlete typed.
    ///   - today: Decides which plans count as upcoming for ``Entry/nextPlannedDate``.
    public func entries(matching query: String, asOf today: Date = .now) -> [Entry] {
        let search = SearchQuery(query)
        let entries = self.entries(asOf: today)
        guard !search.isEmpty else { return entries }
        return entries.filter { search.matches([$0.template.name, $0.defaultTitle, $0.template.sport.displayName]) }
    }

    /// Every template's entry, in ``templates``' order.
    ///
    /// - Parameter today: Decides which plans count as upcoming for ``Entry/nextPlannedDate``.
    public func entries(asOf today: Date = .now) -> [Entry] {
        let athlete = model.athlete
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = athlete.timeZone
        let startOfToday = calendar.startOfDay(for: today)

        let templateByWorkout = Dictionary(
            workouts.compactMap { workout in workout.templateID.map { (workout.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        var plansByTemplate: [UUID: [PlannedActivity]] = [:]
        for plan in plans {
            guard let templateID = templateByWorkout[plan.workoutID] else { continue }
            plansByTemplate[templateID, default: []].append(plan)
        }

        return templates.map { template in
            let plans = plansByTemplate[template.id] ?? []
            let workout = try? template.instantiate()
            let load = try? template.expectedLoad(estimator: estimator, athlete: athlete)
            return Entry(
                template: template,
                defaultTitle: template.defaultTitle(distanceSystem: distanceSystem),
                stepLines: (workout?.blocks ?? []).map { PlannedWorkoutDetailViewModel.line(for: $0) },
                expectedLoad: load?.value,
                planCount: plans.count,
                nextPlannedDate: plans
                    .filter { $0.completedActivityID == nil && $0.date >= startOfToday }
                    .map(\.date)
                    .min()
            )
        }
    }

    /// The athlete's timezone — the tab formats ``Entry/nextPlannedDate`` with this.
    public var timeZone: TimeZone { model.athlete.timeZone }

    /// The "Create Planned Workout" sheet's view model with `template` already picked, for the
    /// detail screen's "Plan This Workout" button. Saving runs ``onPlansChanged`` and reloads the
    /// counts.
    ///
    /// - Parameters:
    ///   - template: The template to plan.
    ///   - date: The day the sheet starts on; defaults to today, still editable inside it.
    public func makePlanner(for template: WorkoutTemplate, date: Date = .now) -> PlannedWorkoutSheetViewModel {
        let planner = PlannedWorkoutSheetViewModel(
            model: model, date: date, templates: templates, estimator: estimator, scheduler: scheduler()
        )
        planner.distanceSystem = distanceSystem
        planner.selectedTemplate = template
        planner.onPlansChanged = { [weak self] in
            guard let self else { return }
            self.onPlansChanged?()
            self.pendingReload = Task { await self.reload() }
        }
        return planner
    }
}
