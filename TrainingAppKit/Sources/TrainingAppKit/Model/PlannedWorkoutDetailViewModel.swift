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
    /// Called after the plan is deleted or edited, so the Watch sync can run again (MVP2-55).
    @ObservationIgnored
    public var onPlansChanged: (@MainActor () -> Void)?
    /// Looks up a plan's Apple Watch status, set by `WeekViewModel` to its own `watchStatus(for:)`
    /// so the sheet and the plan's card always agree (MVP2-122); `nil` shows no status.
    @ObservationIgnored
    public var watchStatus: (@MainActor (PlannedActivity) -> WeekViewModel.PlannedWatchStatus?)?
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
        scheduler: (any PlannedWorkoutScheduling)? = PlannedWorkoutSchedulers.live
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

    /// Why the plan's workout can't go on the Apple Watch, e.g. "Apple Watch doesn't support this
    /// alert for cycling." (MVP2-122): the same reason the plan's card shows, for the sheet's Apple
    /// Watch section. `nil` when it can, or when the card would show nothing either: a missed or
    /// done plan, or sending to the Watch turned off. Reads the current ``plan``, so it follows an
    /// edit once the Watch sync has run again.
    public var watchIncompatibility: String? {
        guard case .unsupported(let reason)? = watchStatus?(plan) else { return nil }
        return reason
    }

    /// The athlete's timezone — the sheet formats ``plan``'s date with this.
    public var timeZone: TimeZone { model.athlete.timeZone }

    /// Sport, name, load and the one measure the workout defines — the same numbers the day list's
    /// card shows.
    public var summary: WeekViewModel.PlannedCardSummary {
        WeekViewModel.PlannedCardSummary.make(
            plan: plan, workout: workout, athlete: model.athlete, calculator: statisticsCalculator,
            history: model.paceHistory
        )
    }

    /// The "Expected" section's values, worked out together so the forecast runs once per read.
    public struct Expected: Equatable, Sendable {
        /// The workout's expected duration.
        public let duration: TimeInterval
        /// Its expected distance; `nil` when the athlete has no heart-rate zone settings to derive
        /// paces from.
        public let distanceMeters: Double?
        /// `true` when ``duration`` is a forecast rather than the sum of the steps' times: the
        /// workout has a distance or open step.
        public let isDurationForecast: Bool
        /// `true` when ``distanceMeters`` is a forecast rather than something the workout defines:
        /// the workout isn't made solely of distance steps.
        public let isDistanceForecast: Bool
        /// How many earlier activities the forecast came from; `0` for the pace model alone.
        public let activityCount: Int

        /// What the forecast is based on, for the section's footer; `nil` when nothing is a forecast.
        public var basis: String? {
            guard isDurationForecast || isDistanceForecast else { return nil }
            switch activityCount {
            case 0: return "Forecast from your pace model; no similar workouts yet."
            case 1: return "Forecast from your pace in 1 similar workout."
            case let count: return "Forecast from your paces in \(count) similar workouts."
            }
        }
    }

    /// The workout's forecast duration and distance from the athlete's earlier, similar workouts in
    /// `TrainingModel.paceHistory` — the same forecast as the day list's card and the week's
    /// statistics (`StatisticsCalculator.projection(for:athlete:paceHistory:before:excluding:)`).
    /// Reads the history live, so a history that lands while the sheet is open updates it. `nil`
    /// when the workout is gone.
    public var expected: Expected? {
        guard let workout else { return nil }
        let projection = statisticsCalculator.projection(
            for: workout, athlete: model.athlete, paceHistory: model.paceHistory, before: plan.date
        )
        var hasDistanceStep = false
        var hasOtherStep = false
        for block in workout.blocks where block.repetitions > 0 {
            for step in block.steps {
                switch step.goal {
                case .distance: hasDistanceStep = true
                case .time, .open: hasOtherStep = true
                }
            }
        }
        let hasOpenStep = workout.blocks.contains { block in
            block.repetitions > 0 && block.steps.contains { $0.goal == .open }
        }
        return Expected(
            duration: projection.duration,
            distanceMeters: projection.distanceMeters,
            isDurationForecast: hasDistanceStep || hasOpenStep,
            isDistanceForecast: projection.distanceMeters != nil && !(hasDistanceStep && !hasOtherStep),
            activityCount: projection.matchedActivityCount
        )
    }

    /// The workout's expected duration (see ``expected``).
    public var expectedDuration: TimeInterval? {
        expected?.duration
    }

    /// The workout's expected distance (see ``expected``).
    public var expectedDistanceMeters: Double? {
        expected?.distanceMeters
    }

    /// How many earlier activities the forecast came from (see ``expected``).
    public var forecastActivityCount: Int {
        expected?.activityCount ?? 0
    }

    /// What the forecast is based on (see ``Expected/basis``).
    public var forecastBasis: String? {
        expected?.basis
    }

    /// Whether the duration is a forecast (see ``Expected/isDurationForecast``).
    public var isDurationForecast: Bool {
        expected?.isDurationForecast ?? false
    }

    /// Whether the distance is a forecast (see ``Expected/isDistanceForecast``).
    public var isDistanceForecast: Bool {
        expected?.isDistanceForecast ?? false
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
        let editor = PlannedWorkoutSheetViewModel(model: model, editing: plan, scheduler: scheduler)
        editor.onPlansChanged = onPlansChanged
        return editor
    }

    /// Deletes the plan — only the plan, never the library workout. The plan is removed locally first
    /// (a failure there leaves everything as it was, with ``deleteError`` set), then its WorkoutKit
    /// entry is removed best-effort: by then the deletion is done and correct locally, and a leftover
    /// Watch entry isn't worth reporting as a failed delete (same reasoning as
    /// ``PlannedWorkoutSheetViewModel``'s edit save) — ``WatchScheduleSync`` removes it on its next
    /// run anyway, since no plan has its id any more.
    ///
    /// - Returns: `true` on success, in which case the sheet dismisses.
    @discardableResult
    public func delete() async -> Bool {
        guard !isDeleting else { return false }
        isDeleting = true
        defer { isDeleting = false }
        let deleted = plan
        do {
            try await model.deletePlan(id: planID)
        } catch {
            deleteError = "Couldn't delete this workout: \(error.localizedDescription)"
            return false
        }
        await scheduler?.unschedule(deleted)
        onPlansChanged?()
        return true
    }
}
