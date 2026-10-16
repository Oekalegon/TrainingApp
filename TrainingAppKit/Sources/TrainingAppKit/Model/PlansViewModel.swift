import Foundation
import TrainingCore

/// Drives the Plans screen (MVP5-125): the training plans with their status, and what the athlete can
/// do with each — activate, archive, duplicate, rename and delete — plus a preview of a draft's
/// projected form against the active plan's.
///
/// The plans come from ``TrainingModel/trainingPlans`` and their workout counts from the stores,
/// both read by ``reload()``. Only the active plan's workouts and cycles are in `TrainingModel` (and
/// so in the calendar, the micro-cycle view, the statistics and the Watch), so every change that can
/// alter which plan that is calls ``onPlansChanged`` afterwards; `MicroCycleViewModel` then drops
/// what it cached for the previous plan (``MicroCycleViewModel/activePlanChanged(asOf:)``).
///
/// Failures are reported in ``actionError`` and leave the plans as they were. A plan an activity has
/// completed a workout of is history: deleting it is refused with a hint to archive it instead.
@Observable
@MainActor
public final class PlansViewModel {
    private let model: TrainingModel
    private let estimator: @MainActor () -> any PlannedLoadEstimator
    private let now: @MainActor () -> Date
    /// Called after a change that can alter the active plan or its workouts, so the calendar, the
    /// micro-cycle view and the Watch schedule catch up.
    @ObservationIgnored
    public var onPlansChanged: (@MainActor () async -> Void)?

    /// One plan in the list, with what its row shows.
    public struct Entry: Identifiable, Equatable, Sendable {
        /// The plan itself.
        public let plan: TrainingPlan
        /// How many planned workouts the plan has, completed ones included.
        public let workoutCount: Int
        /// The first and last day with a planned workout, if it has any.
        public let dateSpan: ClosedRange<Date>?
        /// Whether an activity has completed one of its workouts, which makes it history that can be
        /// archived but not deleted.
        public let hasCompletedWorkouts: Bool

        /// The plan's id.
        public var id: UUID { plan.id }
        /// Whether this is the plan in use.
        public var isActive: Bool { plan.status == .active }
        /// Whether ``PlansViewModel/delete(_:)`` would be refused.
        public var canDelete: Bool { !hasCompletedWorkouts }
    }

    /// A draft's projected form beside the active plan's, from today to the end of the longer plan.
    public struct Preview: Equatable, Sendable {
        /// One day of both projections.
        public struct Day: Equatable, Sendable {
            /// The start of the day.
            public let day: Date
            /// Chronic training load (fitness) with the draft.
            public let draftCTL: Double
            /// Training stress balance (form) with the draft.
            public let draftTSB: Double
            /// Chronic training load with the active plan; equal to the draft's when nothing is active.
            public let activeCTL: Double
            /// Training stress balance with the active plan.
            public let activeTSB: Double
        }

        /// The plan previewed.
        public let planID: UUID
        /// Every day of the projection.
        public let days: [Day]
        /// What ``PlanEvaluator`` finds in the draft's projection.
        public let draftFindings: [PlanFinding]
        /// What it finds in the active plan's projection, for comparison; empty without an active plan.
        public let activeFindings: [PlanFinding]
        /// Whether a plan is active to compare against.
        public let hasActivePlan: Bool

        /// The highest fitness the draft reaches.
        public var draftPeakCTL: Double { days.map(\.draftCTL).max() ?? 0 }
        /// The highest fitness the active plan reaches.
        public var activePeakCTL: Double { days.map(\.activeCTL).max() ?? 0 }
        /// The draft's fitness on the last day.
        public var draftFinalCTL: Double { days.last?.draftCTL ?? 0 }
        /// The active plan's fitness on the last day.
        public var activeFinalCTL: Double { days.last?.activeCTL ?? 0 }
    }

    /// The plans, the active one first, then drafts, then archived and cancelled ones, each group
    /// newest first; as of the last ``reload()``.
    public private(set) var entries: [Entry] = []
    /// Set when ``reload()`` fails; the list then stays as it was.
    public private(set) var loadError: String?
    /// Set when a change fails; the screen shows it as an alert. Cleared by the next successful change.
    public var actionError: String?
    /// Whether a change is running, so the screen disables its buttons meanwhile.
    public private(set) var isWorking = false
    /// The preview of the last plan asked for with ``loadPreview(for:)``, `nil` before one or when
    /// that plan has no workouts to project.
    public private(set) var preview: Preview?
    /// Set when the preview can't be made: no workouts, or a store read failed.
    public private(set) var previewMessage: String?
    /// Whether the plans have been read from the model at least once.
    public private(set) var hasLoaded = false
    /// Whether the active plan's workouts and cycles are what the plans were read for, i.e. a plan
    /// store is configured. Without one the screen explains that plans aren't available.
    public var isAvailable: Bool { model.stores.trainingPlanStore != nil }

    @ObservationIgnored private var reloadGeneration = 0
    @ObservationIgnored private var previewGeneration = 0
    /// How far past the last planned workout the projection goes: the form settles over about six weeks.
    private static let previewTailDays = 14
    /// The longest projection, so a plan with a workout years out doesn't compute a series that long.
    private static let maxPreviewDays = 400

    /// - Parameters:
    ///   - model: The app's training model.
    ///   - estimator: The load estimator for workouts without a stated load, read when a preview is made.
    ///   - now: The current time; replaced by tests.
    public init(
        model: TrainingModel,
        estimator: @escaping @MainActor () -> any PlannedLoadEstimator = { TRIMPPlanEstimator() },
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.model = model
        self.estimator = estimator
        self.now = now
    }

    // MARK: - Loading

    /// Reads the plans from the model and each plan's workouts from the store.
    public func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        do {
            let all = try await model.stores.planStore.plans(in: Date.distantPast...Date.distantFuture)
            guard generation == reloadGeneration else { return }
            var byPlan: [UUID: [PlannedActivity]] = [:]
            for item in all {
                if let planID = item.planID { byPlan[planID, default: []].append(item) }
            }
            // The canonical active plan, so a sync that left two active shows one as in use.
            let activeID = model.trainingPlans.canonicalActivePlan?.id
            let built = model.trainingPlans.map { plan -> Entry in
                let items = byPlan[plan.id] ?? []
                let dates = items.map(\.date)
                var shown = plan
                // Another active plan is shown as the draft it effectively is.
                if shown.status == .active, shown.id != activeID { shown.status = .draft }
                return Entry(
                    plan: shown, workoutCount: items.count,
                    dateSpan: dates.min().flatMap { low in dates.max().map { low...$0 } },
                    hasCompletedWorkouts: items.contains { $0.completedActivityID != nil }
                )
            }
            entries = Self.sorted(built)
            loadError = nil
            hasLoaded = true
        } catch {
            guard generation == reloadGeneration else { return }
            loadError = "Couldn't load your plans: \(error.localizedDescription)"
        }
    }

    private static func sorted(_ entries: [Entry]) -> [Entry] {
        func rank(_ status: PlanStatus) -> Int {
            switch status {
            case .active: 0
            case .draft: 1
            case .archived, .cancelled: 2
            }
        }
        return entries.sorted {
            let (a, b) = (rank($0.plan.status), rank($1.plan.status))
            if a != b { return a < b }
            if $0.plan.createdDate != $1.plan.createdDate { return $0.plan.createdDate > $1.plan.createdDate }
            return $0.plan.id.uuidString < $1.plan.id.uuidString
        }
    }

    /// The entry for the plan with `id`.
    public func entry(id: UUID) -> Entry? {
        entries.first { $0.id == id }
    }

    // MARK: - Changes

    /// Makes `entry`'s plan the active one. The previous active plan becomes a draft, or a cancelled
    /// plan (kept as history) if the athlete has completed workouts under it.
    public func activate(_ entry: Entry) async {
        await perform("Couldn't activate the plan") { [model, now] in
            try await model.activateTrainingPlan(id: entry.id, asOf: now())
        }
    }

    /// Archives `entry`'s plan: it stays stored but feeds nothing. Archiving the active plan leaves
    /// none active.
    public func archive(_ entry: Entry) async {
        await perform("Couldn't archive the plan") { [model, now] in
            try await model.setStatus(.archived, ofTrainingPlan: entry.id, asOf: now())
        }
    }

    /// Makes a draft copy of `entry`'s plan: its cycles and its workouts from today on that no
    /// activity completed.
    ///
    /// - Returns: The copy, or `nil` if it failed (see ``actionError``).
    @discardableResult
    public func duplicate(_ entry: Entry) async -> TrainingPlan? {
        var copy: TrainingPlan?
        await perform("Couldn't duplicate the plan") { [model, now] in
            copy = try await model.duplicateTrainingPlan(id: entry.id, asOf: now())
        }
        return copy
    }

    /// Creates an empty draft plan named `name`. A name that is empty after trimming is refused.
    ///
    /// - Returns: The new plan, or `nil` if it was refused or failed (see ``actionError``).
    @discardableResult
    public func create(named name: String) async -> TrainingPlan? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            actionError = "A plan needs a name."
            return nil
        }
        var plan: TrainingPlan?
        await perform("Couldn't create the plan") { [model, now] in
            plan = try await model.createTrainingPlan(named: trimmed, status: .draft, asOf: now())
        }
        return plan
    }

    /// The current day, in the athlete's time zone as far as a default date for a sheet needs.
    public func today() -> Date { now() }

    /// The plan in use, if any.
    public var activeEntry: Entry? { entries.first(where: \.isActive) }

    /// Renames `entry`'s plan. A name that is empty after trimming is refused.
    public func rename(_ entry: Entry, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            actionError = "A plan needs a name."
            return
        }
        guard trimmed != entry.plan.name else { return }
        await perform("Couldn't rename the plan") { [model] in
            try await model.renameTrainingPlan(id: entry.id, to: trimmed)
        }
    }

    /// Deletes `entry`'s plan with its cycles and workouts. Refused, with a hint to archive it, for
    /// a plan an activity completed a workout of.
    public func delete(_ entry: Entry) async {
        // Checked against the store rather than the entry, which may be a reload behind.
        do {
            if try await model.trainingPlanHasCompletedWorkouts(id: entry.id) {
                actionError = "“\(entry.plan.name)” has completed workouts, so it's part of your history. Archive it instead."
                return
            }
        } catch {
            actionError = "Couldn't delete the plan: \(error.localizedDescription)"
            return
        }
        await perform("Couldn't delete the plan") { [model, now] in
            try await model.deleteTrainingPlan(id: entry.id, asOf: now())
        }
        if preview?.planID == entry.id {
            preview = nil
            previewMessage = nil
        }
    }

    /// Runs `change`, reloads, and tells ``onPlansChanged``'s owner; reports a failure in ``actionError``.
    /// Reloads and notifies even after a failure, since a store may have written before it threw.
    private func perform(_ failure: String, _ change: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await change()
            actionError = nil
        } catch {
            actionError = "\(failure): \(error.localizedDescription)"
        }
        await reload()
        await onPlansChanged?()
    }

    // MARK: - Preview

    /// Projects `entry`'s plan beside the active plan's, into ``preview``.
    ///
    /// Both start from the athlete's real fitness on the day before today (``TrainingModel/metrics``),
    /// then add the planned workouts from today on, each at its stated or estimated load, and run
    /// ``PlanEvaluator`` over the result with the plan's own cycles. Nothing is stored and the active
    /// plan's series is untouched, as for ``PlanSandbox``.
    ///
    /// - Parameter entry: The plan to preview; for the active plan the two projections coincide.
    public func loadPreview(for entry: Entry) async {
        previewGeneration += 1
        let generation = previewGeneration
        do {
            let result = try await makePreview(for: entry.id)
            guard generation == previewGeneration else { return }
            preview = result
            previewMessage = result == nil ? "This plan has no upcoming workouts to project." : nil
        } catch {
            guard generation == previewGeneration else { return }
            preview = nil
            previewMessage = "Couldn't project the plan: \(error.localizedDescription)"
        }
    }

    private func makePreview(for planID: UUID) async throws -> Preview? {
        let stores = model.stores
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.athlete.timeZone
        let today = calendar.startOfDay(for: now())
        let everything = today...Date.distantFuture

        let draftItems = try await model.plannedActivities(ofPlan: planID, in: everything)
        guard let lastDraft = draftItems.map(\.date).max() else { return nil }
        let activePlan = model.activeTrainingPlan
        let activeItems = try await stores.activePlannedActivities(in: everything)
            .filter { $0.completedActivityID == nil }
        let lastDay = max(lastDraft, activeItems.map(\.date).max() ?? lastDraft)
        let horizon = min(
            calendar.date(byAdding: .day, value: Self.previewTailDays, to: calendar.startOfDay(for: lastDay)) ?? lastDay,
            calendar.date(byAdding: .day, value: Self.maxPreviewDays, to: today) ?? lastDay
        )

        let workouts = try await stores.workoutStore.workouts()
        let races = try await stores.raceStore.races(in: today...horizon)
        let draftCycles = try await model.cycles(ofPlan: planID, in: today...horizon)
        let activeCycles = try await stores.activeCycles(in: today...horizon)

        let seedEntry = model.metrics.last { $0.day < today }
        let seed = seedEntry.map { (ctl: $0.ctl, atl: $0.atl) }
        let start = seedEntry.flatMap { calendar.date(byAdding: .day, value: 1, to: $0.day) } ?? today

        let draftMetrics = project(draftItems, workouts: workouts, from: start, through: horizon, seed: seed, calendar: calendar)
        let activeMetrics = activePlan?.id == planID
            ? draftMetrics
            : project(activeItems, workouts: workouts, from: start, through: horizon, seed: seed, calendar: calendar)

        let evaluator = PlanEvaluator()
        let draftFindings = evaluator.evaluate(draftMetrics, races: races, cycles: draftCycles).findings
            .filter { $0.day >= today }
        let activeFindings = activePlan == nil ? [] : evaluator.evaluate(activeMetrics, races: races, cycles: activeCycles).findings
            .filter { $0.day >= today }

        let activeByDay = Dictionary(activeMetrics.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        let days = draftMetrics.filter { $0.day >= today }.map { entry in
            let active = activeByDay[entry.day] ?? entry
            return Preview.Day(
                day: entry.day, draftCTL: entry.ctl, draftTSB: entry.tsb,
                activeCTL: active.ctl, activeTSB: active.tsb
            )
        }
        return Preview(
            planID: planID, days: days, draftFindings: draftFindings, activeFindings: activeFindings,
            hasActivePlan: activePlan != nil
        )
    }

    /// The fitness series from `start` through `end` with `items` as the only planned load, continued
    /// from `seed`. Built day by day as in ``PlannedWorkoutSheetViewModel``'s guardrail projection,
    /// since every day here is in the future.
    private func project(
        _ items: [PlannedActivity], workouts: [StructuredWorkout], from start: Date, through end: Date,
        seed: (ctl: Double, atl: Double)?, calendar: Calendar
    ) -> [FitnessMetrics] {
        let estimator = estimator()
        let workoutsByID = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var loadByDay: [Date: Double] = [:]
        for item in items {
            guard let workout = workoutsByID[item.workoutID] else { continue }
            let load = item.expectedLoadOverride ?? estimator.estimatedLoad(for: workout, athlete: model.athlete).value
            loadByDay[calendar.startOfDay(for: item.date), default: 0] += load
        }
        var days: [DayLoad] = []
        var cursor = start
        while cursor <= end {
            days.append(DayLoad(day: cursor, load: loadByDay[cursor] ?? 0, isProjected: true))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return FitnessMetricsCalculator().metrics(for: days, parameters: model.parameters, seed: seed)
    }
}
