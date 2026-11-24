import Foundation
import TrainingCore
import TrainingWatchKit

/// Keeps the Apple Watch app's copy of the upcoming planned workouts in step with the plans
/// (WATCH-103), so a run can start from the plan with the phone out of reach.
///
/// Sends the next 7 days of the active plan's planned runs that aren't completed yet, with their
/// workouts, whenever they change. ``WatchScheduleSync`` calls ``sync(asOf:)`` at the start of each
/// of its runs, so this follows exactly the moments the Workout app's schedule does: the app
/// becoming active, a plan saved, deleted or imported, and anything that links or unlinks a plan.
/// A plan is sent when it differs from the last one sent in this run of the app, and again after
/// ``refreshInterval`` even if it doesn't: each plan carries when it was sent, which is how the
/// watch can tell a plan that is current from one the phone hasn't refreshed for days. So calling
/// it often is cheap, and the transport holds the latest plan until a watch with the app installed
/// can take it (see ``WatchSyncChannel``).
///
/// It doesn't follow the Athlete tab's "Send Planned Workouts to Apple Watch" switch, which is
/// about the Workout app's schedule (``WatchScheduleSync/isEnabled``): the watch app is the athlete's
/// own, and its plan is what it records against.
@MainActor
public final class WatchPlanSync {
    private let model: TrainingModel
    private let sender: any WatchSyncSending
    private var lastSent: WatchPlan?
    private var rejectedError: String?

    /// How long an unchanged plan goes unsent before it is sent again, to tell the watch it is
    /// still current (`WatchPlanStore.freshFor` is 24 hours).
    public static let refreshInterval: TimeInterval = 6 * 3600

    /// Why the plan couldn't be handed to the Watch, for a screen to show: it couldn't be encoded,
    /// or the transport refused it; `nil` when the last attempt worked or none was made. A Watch
    /// that isn't paired or has no app yet isn't an error: the transport keeps the plan until one is.
    public var lastError: String? { rejectedError ?? sender.lastSendError }

    /// - Parameters:
    ///   - model: Where the plans and the athlete's time zone come from.
    ///   - sender: What puts the plan on the watch.
    public init(model: TrainingModel, sender: any WatchSyncSending) {
        self.model = model
        self.sender = sender
    }

    /// Sends the upcoming planned runs to the Watch if they changed since the last send, or the
    /// last send is older than ``refreshInterval``. Does nothing when the stores can't be read.
    ///
    /// Reads only the plans in the next 7 days and the workouts they use, not the whole plan and
    /// library, which grow with every plan made.
    ///
    /// - Parameter now: The current time, injected so tests can pin the window.
    public func sync(asOf now: Date = .now) async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.athlete.timeZone
        let window = WatchSchedulePlanner.window(asOf: now, calendar: calendar)
        let stores = model.stores
        let candidates: [PlannedActivity]
        var workouts: [UUID: StructuredWorkout] = [:]
        do {
            candidates = try await stores.activePlannedActivities(in: window.lowerBound...window.upperBound)
            for id in Set(candidates.map(\.workoutID)) {
                workouts[id] = try await stores.workoutStore.workout(id: id)
            }
        } catch {
            return
        }
        let plan = Self.plan(
            from: candidates, workouts: workouts, asOf: now, calendar: calendar,
            athlete: model.athlete, paceHistory: model.paceHistory)
        if let lastSent, lastSent.workouts == plan.workouts, now.timeIntervalSince(lastSent.sentAt) < Self.refreshInterval {
            return
        }
        do {
            try sender.send(plan: plan)
            lastSent = plan
            rejectedError = nil
        } catch {
            rejectedError = error.localizedDescription
        }
    }

    /// The plan the Watch should have: the planned runs in the next 7 days (today included) that
    /// have a workout and aren't completed. Only runs, because the watch app records runs (WATCH-101);
    /// other sports stay on the Workout app's schedule. Also what the tests use to pin that choice.
    ///
    /// - Parameters:
    ///   - plans: The active plan's planned activities.
    ///   - workouts: Each planned activity's workout, by ID; a plan whose workout is missing is left out.
    ///   - now: The current time, which is also when the plan counts as sent.
    ///   - calendar: In the athlete's time zone, so "today" and the window start where the athlete's day does.
    ///   - athlete: Whose paces the duration of a workout with an open step is forecast from.
    ///   - paceHistory: The athlete's recent runs, which that forecast is made from.
    static func plan(
        from plans: [PlannedActivity], workouts: [UUID: StructuredWorkout], asOf now: Date, calendar: Calendar,
        athlete: AthleteProfile? = nil, paceHistory: PaceHistory = .empty
    ) -> WatchPlan {
        let calculator = StatisticsCalculator()
        let window = WatchSchedulePlanner.window(asOf: now, calendar: calendar)
        return WatchPlan(workouts: plans.compactMap { plan in
            guard window.contains(plan.date), plan.completedActivityID == nil,
                  let workout = workouts[plan.workoutID], workout.sport == .running
            else { return nil }
            // The same forecast the planned cards show. The watch needs it only for an open step, which has
            // no end of its own (WATCH-119), so it isn't sent otherwise: it would make the plan change
            // every time the pace history does.
            let hasOpenStep = workout.blocks.contains { $0.repetitions > 0 && $0.steps.contains { $0.goal == .open } }
            let duration = hasOpenStep ? athlete.map {
                calculator.projection(for: workout, athlete: $0, paceHistory: paceHistory, before: plan.date).duration
            } : nil
            return WatchPlannedWorkout(
                id: plan.id, date: plan.date, name: workout.name, blocks: workout.blocks,
                typicalDuration: duration.flatMap { $0 > 0 ? $0 : nil })
        }, sentAt: now)
    }
}
