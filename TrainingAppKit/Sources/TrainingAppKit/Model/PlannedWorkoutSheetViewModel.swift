import Foundation
import TrainingCore
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

    private func recomputeExpectedLoad() {
        guard let selectedTemplate else {
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
        guard let selectedTemplate, let workout = try? selectedTemplate.instantiate(
            name: workoutName.isEmpty ? nil : workoutName, values: parameterValues
        ) else {
            guardrailFindings = []
            guardrailDiagnostic = nil
            return
        }
        let plan = PlannedActivity(workoutID: workout.id, date: date)
        let calendar = athleteCalendar
        let startOfDay = calendar.startOfDay(for: date)
        let displayRange = Self.displayRange(around: date, calendar: calendar)

        let seedEntry = model.metrics.last { $0.day < startOfDay }
        let seed: (ctl: Double, atl: Double)? = seedEntry.map { ($0.ctl, $0.atl) }
        let seriesStart = seedEntry.flatMap { calendar.date(byAdding: .day, value: 1, to: $0.day) } ?? startOfDay

        // Every other already-planned activity in the projected window too, so the projection
        // reflects the whole plan this addition is joining rather than just this one workout in
        // isolation -- `model.plans`/`model.workouts` are whatever's already loaded, no store hit.
        let otherPlans = model.plans.filter { $0.date >= seriesStart && $0.date <= displayRange.upperBound }
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
        let workoutsByID = Dictionary(uniqueKeysWithValues: (model.workouts + [workout]).map { ($0.id, $0) })
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
        // `atlToCTLRatio` excluded: it normalizes fatigue (ATL) against fitness (CTL) as a ratio,
        // which is hypersensitive exactly when CTL is low -- a real report: CTL=9, ATL=14 (TSB=-6,
        // an unremarkable, mild fatigue level `tsbBand` correctly stays silent on) already reads as
        // ratio=1.56, over the 1.4 risk threshold, from the athlete's pre-existing state alone,
        // before this addition contributes anything. `tsbBand` reads the same freshness signal
        // directly (CTL-ATL) without that low-baseline distortion, so it's the one shown here.
        guardrailFindings = evaluation.findings
            .filter { displayRange.contains($0.day) }
            .filter { $0.rule != .atlToCTLRatio }
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
