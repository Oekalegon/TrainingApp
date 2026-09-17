import Foundation
import TrainingCore
import TrainingTools
#if canImport(WorkoutKit)
import TrainingWorkoutKit
#endif

/// Drives the "Create Planned Workout" sheet (MVP2-15): pick a ``WorkoutTemplate``, fill in its
/// parameters with a live expected-load preview, see non-blocking ``PlanEvaluator`` guardrail
/// warnings for the hypothetical addition, then save — which instantiates the template, syncs the
/// result to WorkoutKit, and schedules it.
@Observable
@MainActor
public final class PlannedWorkoutSheetViewModel {
    private let model: TrainingModel
    private let estimator: any PlannedLoadEstimator
    /// `nil` on a platform without WorkoutKit (e.g. macOS, per `Package.swift`'s doc comment on why
    /// `TrainingAppKit` still declares that platform) or in a test that passed `nil` explicitly to
    /// avoid the real `WorkoutScheduler`, which requires a genuine app bundle context — see
    /// ``PlannedWorkoutScheduling``'s own doc comment. `save()` skips the sync/schedule step
    /// entirely when this is `nil`, rather than only skipping `schedule` — a workout added to the
    /// library without ever having been synced is a consistent, if incomplete, state to save.
    private let scheduler: (any PlannedWorkoutScheduling)?

    /// The templates offered in the picker — the built-in library only; MVP2-15 doesn't add custom
    /// template persistence.
    public let templates: [WorkoutTemplate]

    /// The day this workout is being planned for.
    public var date: Date {
        didSet {
            guard date != oldValue else { return }
            scheduleGuardrailRecompute()
        }
    }
    public var selectedTemplate: WorkoutTemplate? {
        didSet {
            guard selectedTemplate?.id != oldValue?.id else { return }
            seedFromSelectedTemplate()
        }
    }
    public var workoutName: String = ""
    /// Parameter key to value, seeded from each parameter's `defaultValue` when a template is
    /// selected. Not private(set): the sheet's sliders/steppers write through
    /// ``setParameterValue(_:forKey:)`` instead, which also triggers both live recomputations.
    public private(set) var parameterValues: [String: Double] = [:]

    /// The instantiated workout's estimated load, recomputed on every parameter change — `nil`
    /// before a template is picked, or if `selectedTemplate` itself is malformed (an undeclared
    /// parameter reference), which the UI has no way to cause through its own controls but is
    /// handled defensively rather than crashing.
    public private(set) var expectedLoad: TrainingLoad?
    /// Non-blocking guardrail findings for the hypothetical addition, from running it through
    /// ``PlanSandbox``/``PlanEvaluator`` without ever committing it. Empty (not an error state)
    /// whenever nothing has been evaluated yet or the sandbox couldn't be built.
    public private(set) var guardrailFindings: [PlanFinding] = []
    /// Set when ``save()`` fails — a WorkoutKit mapping error (unsupported activity/goal/alert) or
    /// a store failure. The sheet shows this as a blocking alert, distinct from the non-blocking
    /// ``guardrailFindings``.
    public private(set) var saveError: String?
    public private(set) var isSaving = false

    @ObservationIgnored
    private var guardrailTask: Task<Void, Never>?

    /// Creates a planned-workout sheet view model.
    ///
    /// - Parameters:
    ///   - model: The training model to save the instantiated workout/plan into.
    ///   - date: The day this workout is being planned for; defaults to `.now`'s calendar day.
    ///   - templates: The templates offered in the picker; defaults to the built-in library.
    ///   - estimator: Estimates ``expectedLoad`` from a step's target intensity; defaults to the
    ///     same ``TRIMPPlanEstimator`` `TrainingModel` itself uses, so the preview agrees with what
    ///     the fitness chart will show once this workout is scheduled.
    ///   - scheduler: Syncs/schedules the instantiated workout to WorkoutKit; defaults to a real
    ///     `WorkoutKitBridge` where available, `nil` otherwise. Tests pass `nil` explicitly to skip
    ///     WorkoutKit entirely, since the real bridge's `schedule` crashes outside a genuine app
    ///     bundle context.
    public init(
        model: TrainingModel,
        date: Date = .now,
        templates: [WorkoutTemplate] = BuiltInWorkoutTemplates.all,
        estimator: any PlannedLoadEstimator = TRIMPPlanEstimator(),
        scheduler: (any PlannedWorkoutScheduling)? = PlannedWorkoutSheetViewModel.liveScheduler
    ) {
        self.model = model
        self.date = date
        self.templates = templates
        self.estimator = estimator
        self.scheduler = scheduler
    }

    #if canImport(WorkoutKit)
    public static var liveScheduler: (any PlannedWorkoutScheduling)? { WorkoutKitBridge() }
    #else
    public static var liveScheduler: (any PlannedWorkoutScheduling)? { nil }
    #endif

    /// Writes one parameter's value and recomputes ``expectedLoad``/``guardrailFindings``. The
    /// sheet's controls call this rather than mutating ``parameterValues`` directly, since a plain
    /// dictionary write wouldn't trigger the guardrail simulation.
    public func setParameterValue(_ value: Double, forKey key: String) {
        parameterValues[key] = value
        recomputeExpectedLoad()
        scheduleGuardrailRecompute()
    }

    private func seedFromSelectedTemplate() {
        guard let selectedTemplate else {
            parameterValues = [:]
            workoutName = ""
            expectedLoad = nil
            guardrailFindings = []
            return
        }
        parameterValues = Dictionary(
            uniqueKeysWithValues: selectedTemplate.parameters.map { ($0.key, $0.defaultValue) }
        )
        workoutName = selectedTemplate.name
        recomputeExpectedLoad()
        scheduleGuardrailRecompute()
    }

    private func recomputeExpectedLoad() {
        guard let selectedTemplate else {
            expectedLoad = nil
            return
        }
        expectedLoad = try? selectedTemplate.expectedLoad(
            values: parameterValues, estimator: estimator, athlete: model.athlete
        )
    }

    /// How far back ``scheduleGuardrailRecompute()`` snapshots real history before `date` — enough
    /// for CTL/ATL to clear `FitnessMetricsCalculator`'s ~42-day warmup and settle into a real
    /// (if the athlete has little training, near-zero but no longer transient) trend by the time
    /// the simulation reaches `date`.
    private static let guardrailLookbackDays = 90
    /// How far past `date` a finding is still shown as caused by this addition — a finding further
    /// out than this is either unrelated day-to-day noise or a pre-existing condition this single
    /// workout can't meaningfully be blamed for.
    private static let guardrailLookaheadDays = 14

    /// Runs the hypothetical addition through ``PlanSandbox``/``PlanEvaluator`` — never persisted,
    /// discarded as soon as the findings are read. Cancels and replaces any still-running
    /// simulation rather than letting two overlapping ones race to set ``guardrailFindings`` last.
    ///
    /// Scoped to a window around `date` rather than ``PlanSandbox``'s full ~1.5-year default
    /// snapshot range, in both the simulation itself (`range:`) and the findings shown
    /// (`displayRange`): `PlanEvaluator` emits one `PlanFinding` per breaching day, and a
    /// history-thin athlete's near-zero CTL/ATL can sit in guardrail-breaching territory for
    /// hundreds of days at a stretch — unscoped, a single degenerate condition floods the sheet
    /// with what reads as dozens of unrelated warnings instead of the handful that actually bear
    /// on adding *this* workout on *this* day.
    private func scheduleGuardrailRecompute() {
        guardrailTask?.cancel()
        guard let selectedTemplate, let workout = try? selectedTemplate.instantiate(
            name: workoutName.isEmpty ? nil : workoutName, values: parameterValues
        ) else {
            guardrailFindings = []
            return
        }
        let plan = PlannedActivity(workoutID: workout.id, date: date)
        let stores = model.stores
        let today = date
        let estimator = self.estimator
        let calendar = athleteCalendar
        let evaluationRange = Self.evaluationRange(around: date, calendar: calendar)
        let displayRange = Self.displayRange(around: date, calendar: calendar)
        guardrailTask = Task { [weak self] in
            guard let sandbox = try? await PlanSandbox(snapshotOf: stores, range: evaluationRange) else {
                // Most commonly `PlanSandboxError.missingAthleteProfile` -- `TrainingModel.athlete`
                // is a plain, caller-managed property that isn't necessarily saved to the store
                // yet. Clears rather than leaving a stale value from a previous (successful)
                // recompute in place, which would otherwise silently keep showing findings for
                // whatever the template/parameters used to be.
                guard !Task.isCancelled, let self else { return }
                self.guardrailFindings = []
                return
            }
            await sandbox.setWorkouts(await sandbox.workouts + [workout])
            await sandbox.setPlans(await sandbox.plans + [plan])
            let result = await sandbox.simulate(
                engine: DefaultSeriesEngine(estimator: estimator), evaluator: PlanEvaluator(), today: today
            )
            guard !Task.isCancelled, let self else { return }
            self.guardrailFindings = result.evaluation.findings.filter { displayRange.contains($0.day) }
        }
    }

    /// `date` is typically a "day" only in intent — the sheet's default is `.now` and a
    /// `DatePicker` binding can carry whatever time-of-day it started with — but every `PlanFinding`/
    /// `FitnessMetrics` entry's `day` is midnight-aligned. Comparing `date` against those raw would
    /// exclude a finding on `date`'s own calendar day whenever `date`'s time-of-day is later than
    /// midnight, which is effectively always — this normalizes first so the addition's own day is
    /// never silently dropped from either range.
    private static func evaluationRange(around date: Date, calendar: Calendar) -> ClosedRange<Date> {
        let startOfDay = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .day, value: -guardrailLookbackDays, to: startOfDay) ?? startOfDay
        let end = calendar.date(byAdding: .day, value: guardrailLookaheadDays, to: startOfDay) ?? startOfDay
        return start...end
    }

    /// `date`'s own calendar day through `date` + ``guardrailLookaheadDays`` — deliberately
    /// excludes days before `date`: a finding there reflects the athlete's pre-existing history,
    /// not something adding this workout caused.
    private static func displayRange(around date: Date, calendar: Calendar) -> ClosedRange<Date> {
        let startOfDay = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: guardrailLookaheadDays, to: startOfDay) ?? startOfDay
        return startOfDay...end
    }

    /// Waits for any in-flight guardrail recompute (from the most recent template/parameter/date
    /// change) to finish. Exposed for tests, which otherwise have no way to observe when the
    /// fire-and-forget `Task` ``scheduleGuardrailRecompute()`` starts has actually landed.
    public func waitForGuardrailRecompute() async {
        await guardrailTask?.value
    }

    private var athleteCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.athlete.timeZone
        return calendar
    }

    /// Instantiates the selected template, syncs it to WorkoutKit, and schedules it — `true` on
    /// success, in which case the sheet dismisses; `false` leaves ``saveError`` set for the sheet
    /// to show.
    @discardableResult
    public func save() async -> Bool {
        guard let selectedTemplate else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            var workout = try selectedTemplate.instantiate(
                name: workoutName.isEmpty ? nil : workoutName, values: parameterValues
            )
            if let scheduler {
                workout.workoutKitID = try await scheduler.sync(workout)
            }
            try await model.add(workout)
            let plan = PlannedActivity(workoutID: workout.id, date: date)
            if let scheduler {
                try await scheduler.schedule(plan, workout: workout, calendar: athleteCalendar)
            }
            try await model.add(plan)
            return true
        } catch {
            saveError = "Couldn't save this workout: \(error.localizedDescription)"
            return false
        }
    }
}
