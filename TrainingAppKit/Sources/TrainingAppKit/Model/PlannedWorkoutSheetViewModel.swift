import Foundation
import TrainingCore
#if canImport(WorkoutKit)
import TrainingWorkoutKit
#endif

/// Drives the "Create Planned Workout" sheet (MVP2-15): pick a ``WorkoutTemplate``, fill in its
/// parameters with a live expected-load preview, see non-blocking ``PlanEvaluator`` guardrail
/// warnings for the hypothetical addition, then save — which instantiates the template, syncs the
/// result to WorkoutKit, and schedules it.
///
/// Also drives the same sheet in edit mode (MVP2-39, ``init(model:editing:templates:estimator:scheduler:)``):
/// an existing plan's date and expected-load override are editable, its workout is shown read-only
/// (the template and parameters it was instantiated from aren't stored, and a workout definition
/// may be shared by other plans, so it isn't edited here), and ``save()`` updates the plan in
/// place — rescheduling on WorkoutKit if the day moved.
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
    /// The plan being edited, as it was when the sheet opened; `nil` when creating a new one.
    private let editingPlan: PlannedActivity?
    /// The workout ``editingPlan`` schedules — `nil` when creating, or if that workout is no
    /// longer in the library (in which case editing is still allowed, just without a workout name,
    /// guardrail preview or WorkoutKit rescheduling).
    private let editedWorkout: StructuredWorkout?

    /// The template ``editedWorkout`` was instantiated from, when its ``StructuredWorkout/templateID``
    /// is set and that template is still in ``templates`` — what makes parameters editable in edit
    /// mode (MVP2-41). `nil` for a workout built by hand, created before templates were recorded on
    /// workouts, or whose template no longer exists.
    private let editedTemplate: WorkoutTemplate?
    /// ``editedWorkout``'s recorded parameter values (filled out with defaults), to detect whether the
    /// athlete changed any.
    private let originalParameterValues: [String: Double]

    /// `true` when edit mode can change the workout's parameters (see ``editedTemplate``).
    public var canEditParameters: Bool { editedTemplate != nil }
    /// The parameters edit mode offers, in the template's order — empty when ``canEditParameters`` is
    /// `false`.
    public var editableParameters: [WorkoutTemplateParameter] { editedTemplate?.parameters ?? [] }
    /// `true` when any parameter now differs from what the edited workout was built with.
    private var parametersChanged: Bool { editedTemplate != nil && parameterValues != originalParameterValues }

    /// Whether ``save()`` has something to save: an edit always does (date/load/parameters); a new plan
    /// needs a template picked first. The sheet's save button follows this — keying it off
    /// ``selectedTemplate`` alone left edit mode, which has none, permanently disabled.
    public var canSave: Bool { isEditing || selectedTemplate != nil }

    /// `true` when this view model edits an existing plan rather than creating one.
    public var isEditing: Bool { editingPlan != nil }
    /// The edited workout's name, shown read-only in edit mode.
    public var editedWorkoutName: String? { editedWorkout?.name }

    /// The templates offered in the picker — the built-in library only; MVP2-15 doesn't add custom
    /// template persistence.
    public let templates: [WorkoutTemplate]

    /// The day this workout is being planned for.
    public var date: Date {
        didSet {
            guard date != oldValue else { return }
            recomputeGuardrails()
        }
    }
    /// Manual override of the estimated load (``PlannedActivity/expectedLoadOverride``); `nil`
    /// means "use the estimate". Only editable in edit mode, where the sheet shows it.
    public var loadOverride: Double? {
        didSet {
            guard loadOverride != oldValue else { return }
            recomputeExpectedLoad()
            recomputeGuardrails()
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
    /// ``PlanEvaluator`` without ever touching the store. Empty (not an error state) whenever
    /// nothing has been evaluated yet or there's genuinely nothing to flag.
    public private(set) var guardrailFindings: [PlanFinding] = []
    /// The raw per-day CTL/ATL/TSB/ATL-CTL-ratio/warmup values the projection actually produced,
    /// rather than an interpretation of them: this view model has repeatedly guessed wrong at *why*
    /// a particular finding did or didn't fire (missing-athlete-profile, then "not enough history",
    /// then a specific risk/warning pair that didn't reproduce with assumed numbers — see git
    /// history), so it surfaces the numbers themselves and leaves reading them to whoever's looking.
    /// Always populated once a template is selected (not just when ``guardrailFindings`` is empty)
    /// so "what would tomorrow's TSB/ratio be" is directly checkable rather than asked about. `nil`
    /// before the sheet's first recompute.
    public private(set) var guardrailDiagnostic: String?
    /// Set when ``save()`` fails — a WorkoutKit mapping error (unsupported activity/goal/alert) or
    /// a store failure. The sheet shows this as a blocking alert, distinct from the non-blocking
    /// ``guardrailFindings``.
    public private(set) var saveError: String?
    public private(set) var isSaving = false

    /// ``guardrailFindings`` collapsed into one row per contiguous run of the same rule, for
    /// display. `PlanEvaluator` emits a separate finding for every day a rule stays in breach, so a
    /// single sustained excursion (e.g. TSB taking 6 days to recover after a big addition) would
    /// otherwise read as 6 near-identical rows saying the same thing. Sorted worst-severity first,
    /// then by earliest day.
    public var guardrailSummaries: [GuardrailSummary] {
        let calendar = athleteCalendar
        var summaries: [GuardrailSummary] = []
        for (rule, findings) in Dictionary(grouping: guardrailFindings, by: \.rule) {
            let sorted = findings.sorted { $0.day < $1.day }
            var runStart = sorted.startIndex
            for index in sorted.indices {
                let nextDayInRun = calendar.date(byAdding: .day, value: 1, to: sorted[index].day)
                let isRunBoundary = index == sorted.index(before: sorted.endIndex)
                    || nextDayInRun != sorted[index + 1].day
                guard isRunBoundary else { continue }
                let run = sorted[runStart...index]
                summaries.append(
                    GuardrailSummary(
                        rule: rule,
                        severity: run.contains { $0.severity == .risk } ? .risk
                            : run.contains { $0.severity == .warning } ? .warning : .info,
                        firstDay: run.first!.day,
                        lastDay: run.last!.day,
                        dayCount: run.count
                    )
                )
                runStart = index + 1
            }
        }
        return summaries.sorted {
            $0.severity != $1.severity ? $0.severity.isMoreSevere(than: $1.severity) : $0.firstDay < $1.firstDay
        }
    }

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
        self.editingPlan = nil
        self.editedWorkout = nil
        self.editedTemplate = nil
        self.originalParameterValues = [:]
    }

    /// Creates a view model that edits `plan` in place (MVP2-39).
    ///
    /// - Parameters:
    ///   - model: The training model the plan lives in.
    ///   - plan: The plan to edit; its date and ``PlannedActivity/expectedLoadOverride`` seed
    ///     ``date``/``loadOverride``.
    ///   - templates/estimator/scheduler: As for ``init(model:date:templates:estimator:scheduler:)``.
    public init(
        model: TrainingModel,
        editing plan: PlannedActivity,
        templates: [WorkoutTemplate] = BuiltInWorkoutTemplates.all,
        estimator: any PlannedLoadEstimator = TRIMPPlanEstimator(),
        scheduler: (any PlannedWorkoutScheduling)? = PlannedWorkoutSheetViewModel.liveScheduler
    ) {
        self.model = model
        self.date = plan.date
        self.loadOverride = plan.expectedLoadOverride
        self.templates = templates
        self.estimator = estimator
        self.scheduler = scheduler
        self.editingPlan = plan
        let workout = model.workouts.first { $0.id == plan.workoutID }
        self.editedWorkout = workout
        let template = workout?.templateID.flatMap { id in templates.first { $0.id == id } }
        self.editedTemplate = template
        if let template {
            // Recorded values, with any parameter the template gained since filled in from its default.
            let recorded = workout?.parameterValues ?? [:]
            let values = Dictionary(uniqueKeysWithValues: template.parameters.map { ($0.key, recorded[$0.key] ?? $0.defaultValue) })
            self.originalParameterValues = values
            self.parameterValues = values
        } else {
            self.originalParameterValues = [:]
        }
        recomputeExpectedLoad()
        recomputeGuardrails()
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
        recomputeGuardrails()
    }

    private func seedFromSelectedTemplate() {
        guard let selectedTemplate else {
            parameterValues = [:]
            workoutName = ""
            expectedLoad = nil
            guardrailFindings = []
            guardrailDiagnostic = nil
            return
        }
        parameterValues = Dictionary(
            uniqueKeysWithValues: selectedTemplate.parameters.map { ($0.key, $0.defaultValue) }
        )
        workoutName = selectedTemplate.name
        recomputeExpectedLoad()
        recomputeGuardrails()
    }

    /// The workout edit mode currently shows/projects: ``editedWorkout`` untouched, or — once a
    /// parameter changed — a fresh instantiation of ``editedTemplate`` with the new values (keeping
    /// the workout's name), which is also what ``saveEdit(of:)`` persists. `nil` outside edit mode or
    /// when the workout is gone.
    private func effectiveEditedWorkout() -> StructuredWorkout? {
        guard let editedWorkout else { return nil }
        guard parametersChanged, let editedTemplate,
              let instantiated = try? editedTemplate.instantiate(name: editedWorkout.name, values: parameterValues)
        else { return editedWorkout }
        return instantiated
    }

    private func recomputeExpectedLoad() {
        if editingPlan != nil, let editedWorkout = effectiveEditedWorkout() {
            var load = estimator.estimatedLoad(for: editedWorkout, athlete: model.athlete)
            if let loadOverride {
                load.value = loadOverride
            }
            expectedLoad = load
            return
        }
        guard editingPlan == nil, let selectedTemplate else {
            expectedLoad = nil
            return
        }
        expectedLoad = try? selectedTemplate.expectedLoad(
            values: parameterValues, estimator: estimator, athlete: model.athlete
        )
    }

    /// How far past `date` a finding is still shown as caused by this addition — a finding further
    /// out than this is either unrelated day-to-day noise or a pre-existing condition this single
    /// workout can't meaningfully be blamed for.
    private static let guardrailLookaheadDays = 14

    /// Projects the hypothetical addition forward and checks it with ``PlanEvaluator`` — never
    /// touches the store, purely in-memory over data already loaded on `model`.
    ///
    /// Seeded from ``TrainingModel/metrics``'s own entry for the most recent real day before
    /// `date`, rather than recomputing CTL/ATL from scratch over some fetched window: an earlier
    /// version built a from-scratch `PlanSandbox` simulation over the last ~90 days, but that
    /// engine always calls `FitnessMetricsCalculator.metrics(seed: nil)` — meaning "warming up"
    /// was just "fewer than 42 days into *that particular snapshot*", completely disconnected from
    /// the athlete's actual training history and from the size of the addition being tested (an
    /// entry's warmup status never depended on its own load, only its position in the array) — so
    /// every projected day kept reading as warming up regardless of how large a workout was added,
    /// permanently suppressing every cycle-free guardrail rule. `model.metrics` is already
    /// seeded/cache-backed from the athlete's true history, so continuing from its last real day
    /// carries genuine CTL/ATL forward instead of restarting cold.
    private func recomputeGuardrails() {
        let workout: StructuredWorkout
        let plan: PlannedActivity
        if let editingPlan {
            // Edit mode: project the plan as it would be after saving (new date/override), with the
            // original left out of `otherPlans` below so it isn't counted twice.
            guard let editedWorkout = effectiveEditedWorkout() else {
                guardrailFindings = []
                guardrailDiagnostic = nil
                return
            }
            workout = editedWorkout
            var edited = editingPlan
            edited.workoutID = editedWorkout.id
            edited.date = date
            edited.expectedLoadOverride = loadOverride
            plan = edited
        } else {
            guard let selectedTemplate, let instantiated = try? selectedTemplate.instantiate(
                name: workoutName.isEmpty ? nil : workoutName, values: parameterValues
            ) else {
                guardrailFindings = []
                guardrailDiagnostic = nil
                return
            }
            workout = instantiated
            plan = PlannedActivity(workoutID: workout.id, date: date)
        }
        let calendar = athleteCalendar
        let startOfDay = calendar.startOfDay(for: date)
        let displayRange = Self.displayRange(around: date, calendar: calendar)

        let seedEntry = model.metrics.last { $0.day < startOfDay }
        let seed: (ctl: Double, atl: Double)? = seedEntry.map { ($0.ctl, $0.atl) }
        let seriesStart = seedEntry.flatMap { calendar.date(byAdding: .day, value: 1, to: $0.day) } ?? startOfDay

        // Every other already-planned activity in the projected window too, so the projection
        // reflects the whole plan this addition is joining rather than just this one workout in
        // isolation -- `model.plans`/`model.workouts` are whatever's already loaded, no store hit.
        let otherPlans = model.plans.filter {
            $0.id != plan.id && $0.date >= seriesStart && $0.date <= displayRange.upperBound
        }
        // Built by hand rather than via `DailyLoadSeries.days(today:)`: that method's `today` is
        // simultaneously "how far the series extends" *and* the actual/planned boundary ("before
        // today, only logged activities count -- a plan with nothing logged contributes 0"). Every
        // day in this projection is, by construction, still in the future (past dates are disabled
        // from opening this sheet at all), so there's no "boundary" to speak of -- passing either
        // `date` or `displayRange.upperBound` for `today` gets one of the two roles wrong: the
        // former truncates the series the moment nothing else is scheduled past `date`, the latter
        // (an earlier version of this method) silently zeroed the new workout's own load on every
        // day except the last, since everything before it read as "already happened, nothing
        // logged". A plain day-by-day loop over resolved plan loads has neither problem.
        // The workout itself is dropped from `model.workouts` before re-adding it: in edit mode it's
        // already in the library, and `uniqueKeysWithValues` traps on a duplicate id.
        let workoutsByID = Dictionary(
            uniqueKeysWithValues: (model.workouts.filter { $0.id != workout.id } + [workout]).map { ($0.id, $0) }
        )
        var loadByDay: [Date: Double] = [:]
        for scheduledPlan in otherPlans + [plan] {
            guard let scheduledWorkout = workoutsByID[scheduledPlan.workoutID] else { continue }
            let load = scheduledPlan.expectedLoadOverride
                ?? estimator.estimatedLoad(for: scheduledWorkout, athlete: model.athlete).value
            let day = calendar.startOfDay(for: scheduledPlan.date)
            loadByDay[day, default: 0] += load
        }
        var projectedDays: [DayLoad] = []
        var cursor = seriesStart
        while cursor <= displayRange.upperBound {
            projectedDays.append(DayLoad(day: cursor, load: loadByDay[cursor] ?? 0, isProjected: true))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        let projectedMetrics = FitnessMetricsCalculator().metrics(
            for: projectedDays, parameters: model.parameters, seed: seed
        )

        let evaluation = PlanEvaluator().evaluate(projectedMetrics, races: [], cycles: model.cycles)
        let displayedMetrics = projectedMetrics.filter { displayRange.contains($0.day) }
        guardrailFindings = evaluation.findings.filter { displayRange.contains($0.day) }
        guardrailDiagnostic = Self.diagnosticDescription(seeded: seed != nil, displayedMetrics: displayedMetrics)
    }

    /// One line per day in `displayedMetrics` with its raw CTL/ATL/TSB/ATL-CTL-ratio/
    /// ``FitnessMetrics/isWarmingUp`` values, plus whether the projection found a real day to seed
    /// from at all — rather than an interpretation of them (see ``recomputeGuardrails()``'s own doc
    /// comment for why this view model stopped trying to explain that in English). The ratio is
    /// computed here the same way ``PlanEvaluator``'s `atlToCTLRatioFindings` does (`atl/ctl`, `n/a`
    /// for a zero-CTL day) so this always matches whatever that rule actually compared against its
    /// thresholds.
    private static func diagnosticDescription(seeded: Bool, displayedMetrics: [FitnessMetrics]) -> String {
        guard !displayedMetrics.isEmpty else {
            return "No projected days landed in the display window."
        }
        let dateFormat = Date.FormatStyle.dateTime.month(.abbreviated).day()
        let lines = displayedMetrics.map { entry -> String in
            let ratio = entry.ctl > 0 ? entry.atl / entry.ctl : nil
            let ratioText = ratio.map { String(format: "%.2f", $0) } ?? "n/a"
            return "\(entry.day.formatted(dateFormat)): CTL=\(entry.ctl.rounded()) ATL=\(entry.atl.rounded()) "
                + "TSB=\(entry.tsb.rounded()) ratio=\(ratioText) warmingUp=\(entry.isWarmingUp)"
        }
        let header = seeded ? "Seeded from real history." : "No real prior day found to seed from."
        return ([header] + lines).joined(separator: "\n")
    }

    /// `date`'s own calendar day through `date` + ``guardrailLookaheadDays`` — deliberately
    /// excludes days before `date`: a finding there reflects the athlete's pre-existing history,
    /// not something adding this workout caused.
    private static func displayRange(around date: Date, calendar: Calendar) -> ClosedRange<Date> {
        let startOfDay = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: guardrailLookaheadDays, to: startOfDay) ?? startOfDay
        return startOfDay...end
    }

    /// No-op now that ``recomputeGuardrails()`` runs synchronously — kept so existing call sites
    /// (tests, mainly) that await a recompute settling don't need to change.
    public func waitForGuardrailRecompute() async {}

    /// Test seam for ``guardrailSummaries``' grouping logic in isolation, without needing a real
    /// projection to produce a specific set of findings. Internal (not `public`), reachable from
    /// `TrainingAppKitTests` via `@testable import` only.
    func setGuardrailFindingsForTesting(_ findings: [PlanFinding]) {
        guardrailFindings = findings
    }

    private var athleteCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.athlete.timeZone
        return calendar
    }

    /// The earliest day the sheet's `DatePicker` may select — today, in the athlete's calendar.
    /// Matches `WeekViewModel.isPast`'s day-boundary semantics so the in-sheet picker can't be
    /// used to route around the same past-date rule the "+" entry point enforces.
    ///
    /// - Parameter today: Injected rather than read from `.now` internally, matching
    ///   `WeekViewModel.isPast(_:asOf:)`'s own convention (and `TrainingModel.recompute(asOf:)`'s,
    ///   further up the stack) — lets a test pin an exact boundary instead of racing `.now`.
    ///
    /// In edit mode the bound also reaches back to the plan's own day when that's already past (a
    /// missed workout being edited), so the picker can still show the plan's current date rather
    /// than clamping it — it can't be moved to a day earlier than the one it's already on.
    public func minimumDate(asOf today: Date = .now) -> Date {
        let todayStart = athleteCalendar.startOfDay(for: today)
        guard let editingPlan else { return todayStart }
        return min(todayStart, athleteCalendar.startOfDay(for: editingPlan.date))
    }

    /// Instantiates the selected template, syncs it to WorkoutKit, and schedules it — `true` on
    /// success, in which case the sheet dismisses; `false` leaves ``saveError`` set for the sheet
    /// to show.
    ///
    /// Nothing is persisted to `model` until sync *and* schedule have both already succeeded: an
    /// earlier version called `model.add(workout)` right after `sync`, before `schedule` — if
    /// `schedule` then failed (a real possibility on-device: no Watch paired, permission revoked,
    /// iCloud unavailable), the workout was already permanently in the library with no
    /// `PlannedActivity` referencing it, and retrying minted a second, equally orphaned workout
    /// (`instantiate` assigns a fresh id every call).
    ///
    /// Not fully airtight the other way, deliberately: if `schedule` succeeds and then
    /// `model.add(workout)`/`model.add(plan)` throws (a local store write failing, e.g. a
    /// transient CloudKit error), WorkoutKit now has a real scheduled workout with nothing in
    /// TrainingApp's own store referencing it — worse than the orphan above, since it's visible to
    /// the athlete on their Watch with no way to manage it from the app. This ordering accepts
    /// that residual risk rather than eliminating it, on the bet that a local write failing right
    /// after a successful WorkoutKit call is far rarer than WorkoutKit itself failing; genuinely
    /// closing it would need real reconciliation (a "pending schedule" outbox, or reading
    /// `WorkoutScheduler`'s own state back on next launch), which is more machinery than this MVP
    /// feature justifies today.
    @discardableResult
    public func save() async -> Bool {
        // Guards against a double-tap landing before the `Task` wrapping this call has actually
        // started running (and so before `isSaving` below would otherwise have caught it), which
        // would otherwise instantiate and persist two separate workouts for one tap.
        guard !isSaving else { return false }
        if let editingPlan {
            return await saveEdit(of: editingPlan)
        }
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
            let plan = PlannedActivity(workoutID: workout.id, date: date)
            if let scheduler {
                try await scheduler.schedule(plan, workout: workout, calendar: athleteCalendar)
            }
            try await model.add(workout)
            try await model.add(plan)
            return true
        } catch {
            saveError = "Couldn't save this workout: \(error.localizedDescription)"
            return false
        }
    }

    /// Saves `original` over itself with the edited ``date``/``loadOverride`` and, if any parameter
    /// changed, a new workout (MVP2-39, MVP2-41).
    ///
    /// A parameter change instantiates a *new* workout from ``editedTemplate`` and repoints this plan
    /// at it, rather than rewriting the old one — other plans may share the old workout, and the
    /// change is meant for this plan only. The old workout is then removed from the library if no
    /// plan anywhere still references it.
    ///
    /// If the day moved or the workout was replaced, and the workout is still on WorkoutKit's
    /// radar, the plan is scheduled (new day, new workout) on WorkoutKit *first*, and only then
    /// persisted, then the old entry is removed — the same "don't persist until WorkoutKit
    /// succeeded" ordering ``save()`` documents, so a failed schedule leaves the plan untouched
    /// instead of saved somewhere the Watch doesn't know about. The final removals (the old Watch
    /// entry, the unreferenced old workout) are best-effort (`try?`): by then the edit is saved and
    /// correct locally, and failing the whole save over leftovers would just invite a retry that
    /// schedules the new day a second time.
    private func saveEdit(of original: PlannedActivity) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        let calendar = athleteCalendar
        var updated = original
        updated.date = date
        updated.expectedLoadOverride = loadOverride
        let dayMoved = !calendar.isDate(original.date, inSameDayAs: date)
        let oldWorkout = editedWorkout
        do {
            var workout = oldWorkout
            var workoutNeedsSaving = false
            var replacesWorkout = false
            if parametersChanged, let replacement = effectiveEditedWorkout(), replacement.id != oldWorkout?.id {
                workout = replacement
                updated.workoutID = replacement.id
                workoutNeedsSaving = true
                replacesWorkout = true
            }
            let needsScheduling = dayMoved || replacesWorkout
            if needsScheduling, let scheduler, var scheduledWorkout = workout {
                let id = try await scheduler.sync(scheduledWorkout)
                if scheduledWorkout.workoutKitID == nil {
                    // Never synced before (saved without a scheduler, or freshly instantiated): adopt
                    // the id now, so the entry just scheduled can be found and removed again later.
                    scheduledWorkout.workoutKitID = id
                    workout = scheduledWorkout
                    workoutNeedsSaving = true
                }
                try await scheduler.schedule(updated, workout: scheduledWorkout, calendar: calendar)
            }
            if workoutNeedsSaving, let workout {
                try await model.add(workout)
            }
            try await model.add(updated)
            if needsScheduling, let scheduler, let oldWorkout {
                try? await scheduler.unschedule(original, workout: oldWorkout, calendar: calendar)
            }
            if replacesWorkout, let oldWorkout {
                _ = try? await model.deleteWorkoutIfUnreferenced(id: oldWorkout.id)
            }
            return true
        } catch {
            saveError = "Couldn't save this workout: \(error.localizedDescription)"
            return false
        }
    }
}

/// One contiguous run of the same ``PlanRule`` across consecutive days, as grouped by
/// ``PlannedWorkoutSheetViewModel/guardrailSummaries``.
public struct GuardrailSummary: Sendable, Hashable, Identifiable {
    public let rule: PlanRule
    /// The worst (most severe) severity among the findings in this run.
    public let severity: Severity
    public let firstDay: Date
    public let lastDay: Date
    /// How many consecutive days this run spans — always `>= 1`.
    public let dayCount: Int

    public var id: [AnyHashable] { [AnyHashable(rule), AnyHashable(firstDay)] }
}

extension Severity {
    /// `true` if `self` should be treated as worse than `other` — `.risk` > `.warning` > `.info`.
    /// `TrainingCore` doesn't make `Severity` itself `Comparable` (its declaration order already
    /// happens to match this, but that's an implementation detail this makes explicit instead of
    /// relying on).
    func isMoreSevere(than other: Severity) -> Bool {
        func rank(_ severity: Severity) -> Int {
            switch severity {
            case .risk: 0
            case .warning: 1
            case .info: 2
            }
        }
        return rank(self) < rank(other)
    }
}
