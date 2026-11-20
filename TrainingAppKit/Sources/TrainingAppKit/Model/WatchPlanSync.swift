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
/// Nothing is sent when the plan is the same as the last one sent in this run of the app, so
/// calling it often is cheap, and the transport holds the latest plan until a watch with the app
/// installed can take it (see ``WatchSyncChannel``).
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

    /// Sends the upcoming planned runs to the Watch if they changed since the last send. Does
    /// nothing when the stores can't be read.
    ///
    /// - Parameter now: The current time, injected so tests can pin the window.
    public func sync(asOf now: Date = .now) async {
        let stores = model.stores
        guard let plans = try? await stores.activePlannedActivities(in: Date.distantPast...Date.distantFuture),
              let workouts = try? await stores.workoutStore.workouts()
        else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.athlete.timeZone
        let plan = Self.plan(from: plans, workouts: workouts, asOf: now, calendar: calendar)
        guard plan != lastSent else { return }
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
    /// other sports stay on the Workout app's schedule.
    ///
    /// - Parameters:
    ///   - plans: The active plan's planned activities.
    ///   - workouts: The workout library, which holds each planned activity's workout.
    ///   - now: The current time.
    ///   - calendar: In the athlete's time zone, so "today" and the window start where the athlete's day does.
    static func plan(
        from plans: [PlannedActivity], workouts: [StructuredWorkout], asOf now: Date, calendar: Calendar
    ) -> WatchPlan {
        let window = WatchSchedulePlanner.window(asOf: now, calendar: calendar)
        let workoutsByID = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return WatchPlan(workouts: plans.compactMap { plan in
            guard window.contains(plan.date), plan.completedActivityID == nil,
                  let workout = workoutsByID[plan.workoutID], workout.sport == .running
            else { return nil }
            return WatchPlannedWorkout(id: plan.id, date: plan.date, workout: workout)
        })
    }
}
