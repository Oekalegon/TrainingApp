import Foundation
import TrainingCore

/// Drives the read-only detail sheet shown when a planned activity's card is tapped (MVP2-38): the
/// workout's name, sport, date, expected duration/distance/load, a plain step list, plus Delete and
/// (via ``makeEditor()``) the hand-off to ``PlannedWorkoutSheetViewModel``'s edit mode.
///
/// Reads the plan from `model.plans` on every access rather than snapshotting it, so the sheet
/// reflects an edit made in the nested edit sheet the moment that saves; ``isDeleted`` flips once
/// the plan is gone so the sheet can dismiss itself.
@Observable
@MainActor
public final class PlannedWorkoutDetailViewModel {
    private let model: TrainingModel
    private let planID: UUID
    /// The plan as it was when the sheet opened — what ``plan`` falls back to once it's been deleted
    /// (so the alert/summary don't go blank in the instant before the sheet dismisses).
    private let openedPlan: PlannedActivity
    private let scheduler: (any PlannedWorkoutScheduling)?
    private let statisticsCalculator = StatisticsCalculator()

    /// Set when ``delete()`` fails; the sheet shows it as an alert.
    public private(set) var deleteError: String?
    public private(set) var isDeleting = false

    /// Creates a detail view model for `plan`.
    ///
    /// - Parameters:
    ///   - model: The training model `plan` lives in.
    ///   - plan: The plan to show.
    ///   - scheduler: Removes the plan's WorkoutKit entry on delete and reschedules on edit; defaults
    ///     to the real bridge where available, `nil` otherwise (tests pass `nil` — see
    ///     ``PlannedWorkoutScheduling``).
    public init(
        model: TrainingModel,
        plan: PlannedActivity,
        scheduler: (any PlannedWorkoutScheduling)? = PlannedWorkoutSheetViewModel.liveScheduler
    ) {
        self.model = model
        self.planID = plan.id
        self.openedPlan = plan
        self.scheduler = scheduler
    }

    /// The plan's current state — `model.plans`' entry if still there, else the plan as opened.
    public var plan: PlannedActivity {
        model.plans.first { $0.id == planID } ?? openedPlan
    }

    /// `true` once the plan is no longer in `model.plans` — the sheet dismisses itself on this.
    public var isDeleted: Bool {
        !model.plans.contains { $0.id == planID }
    }

    /// The plan's workout, if it's still in the library.
    public var workout: StructuredWorkout? {
        model.workouts.first { $0.id == plan.workoutID }
    }

    /// The athlete's timezone — the sheet formats ``plan``'s date with this.
    public var timeZone: TimeZone { model.athlete.timeZone }

    /// Sport, name, load and the one measure the workout defines — the same numbers the day list's
    /// card shows.
    public var summary: WeekViewModel.PlannedCardSummary {
        WeekViewModel.PlannedCardSummary.make(
            plan: plan, workout: workout, athlete: model.athlete, calculator: statisticsCalculator
        )
    }

    /// The workout's projected duration and distance — the same projection the week's statistics use
    /// (``StatisticsCalculator/projection(for:athlete:)``), `nil` when the workout is gone.
    private var projection: WorkoutProjection? {
        workout.map { statisticsCalculator.projection(for: $0, athlete: model.athlete) }
    }

    /// The workout's estimated duration.
    public var expectedDuration: TimeInterval? {
        projection?.duration
    }

    /// The workout's expected distance: exact for a distance-based workout, a pace-model estimate for
    /// a duration-based one (see ``StatisticsCalculator/projection(for:athlete:)``). `nil` when the
    /// athlete has no heart-rate zone settings to derive paces from.
    public var expectedDistanceMeters: Double? {
        projection?.distanceMeters
    }

    /// One line per block, e.g. `"Warm-up 10:00"` or `"4 × Work 8:00, Recovery 2:00"`. Empty when the
    /// workout is missing.
    public var stepLines: [String] {
        (workout?.blocks ?? []).map(Self.line(for:))
    }

    static func line(for block: WorkoutBlock) -> String {
        let steps = block.steps.map { "\(kindName($0.kind)) \(goalText($0.goal))" }.joined(separator: ", ")
        return block.repetitions > 1 ? "\(block.repetitions) × \(steps)" : steps
    }

    private static func kindName(_ kind: StepKind) -> String {
        switch kind {
        case .warmup: "Warm-up"
        case .work: "Work"
        case .recovery: "Recovery"
        case .cooldown: "Cool-down"
        }
    }

    private static func goalText(_ goal: StepGoal) -> String {
        switch goal {
        case .time(let seconds):
            Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
        case .distance(let meters):
            Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated))
        case .open:
            "open"
        }
    }

    /// The alert's message — the workout's name and the plan's day, e.g. `"Steady on Sat, Sep 20"`.
    public var deletionMessage: String {
        var format = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        format.timeZone = timeZone
        return "\(summary.name ?? "Planned workout") on \(plan.date.formatted(format))"
    }

    /// The edit-mode view model for this plan, presented by the sheet's pencil button (MVP2-39).
    public func makeEditor() -> PlannedWorkoutSheetViewModel {
        PlannedWorkoutSheetViewModel(model: model, editing: plan, scheduler: scheduler)
    }

    /// Deletes the plan — only the plan, never the library workout. The plan is removed locally first
    /// (a failure there leaves everything as it was, with ``deleteError`` set), then its WorkoutKit
    /// entry is removed best-effort: by then the deletion is done and correct locally, and a leftover
    /// Watch entry isn't worth reporting as a failed delete (same reasoning as
    /// ``PlannedWorkoutSheetViewModel``'s edit save).
    ///
    /// - Returns: `true` on success, in which case the sheet dismisses.
    @discardableResult
    public func delete() async -> Bool {
        guard !isDeleting else { return false }
        isDeleting = true
        defer { isDeleting = false }
        let deleted = plan
        let deletedWorkout = workout
        do {
            try await model.deletePlan(id: planID)
        } catch {
            deleteError = "Couldn't delete this workout: \(error.localizedDescription)"
            return false
        }
        if let scheduler, let deletedWorkout {
            try? await scheduler.unschedule(deleted, workout: deletedWorkout, calendar: schedulingCalendar)
        }
        return true
    }

    private var schedulingCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.athlete.timeZone
        return calendar
    }
}
