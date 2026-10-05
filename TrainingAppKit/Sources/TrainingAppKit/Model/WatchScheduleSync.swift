import Foundation
import TrainingCore

/// Keeps the Watch's scheduled workouts in step with the plans (MVP2-55): the next 7 days of
/// planned workouts are put on the Watch, and entries that no longer belong there are removed.
///
/// WorkoutKit never wakes the app, so the window only moves forward when the app runs. `AppTabView`
/// calls ``requestSync(asOf:)`` whenever the app becomes active, which covers launch and the
/// window rolling over at midnight. `WeekViewModel` calls it after a plan is saved, deleted or
/// imported, and after anything that can link or unlink a plan: a HealthKit import, linking by
/// hand, deduplicating, or deleting, joining or unjoining an activity (MVP2-116). Each run compares
/// what should be on the Watch with what is, so it can run any number of times: scheduling an
/// unchanged plan is a no-op.
///
/// Reads every plan from the store rather than `TrainingModel.plans`, which holds only the range the
/// week view loaded: removing entries for plans that aren't listed would otherwise remove entries
/// for plans outside that range.
///
/// Also tracks whether the athlete declined permission, for the week view's banner (MVP2-117):
/// see ``showsPermissionDeniedBanner``.
@Observable
@MainActor
public final class WatchScheduleSync {
    private static let bannerDismissedKey = "watchSync.permissionDeniedBannerDismissed"

    private let model: TrainingModel
    private let scheduler: any PlannedWorkoutScheduling
    private let defaults: UserDefaults
    @ObservationIgnored private var isSyncing = false
    /// Set when a sync is requested while one runs; that run then goes round once more, so a plan
    /// saved after it read the store still ends up on the Watch.
    @ObservationIgnored private var needsRerun = false

    /// Whether the athlete declined permission to schedule workouts, as of the last sync. `false`
    /// until a sync has run, and when permission was never asked for or the device can't schedule
    /// workouts.
    public private(set) var isPermissionDenied = false

    /// Whether the athlete dismissed the permission banner. Kept in `UserDefaults`, so the banner
    /// stays away across launches; cleared once permission is granted, so declining again later
    /// brings it back.
    private var isBannerDismissed: Bool

    /// Whether the week view shows the banner explaining that planned workouts won't reach the
    /// Watch and how to allow it in Settings (MVP2-117): permission is denied and the athlete
    /// hasn't dismissed the banner.
    public var showsPermissionDeniedBanner: Bool {
        isPermissionDenied && !isBannerDismissed
    }

    /// - Parameters:
    ///   - model: Supplies the stores and the athlete's time zone.
    ///   - scheduler: The Watch; `WorkoutKitBridge` in the app, a fake in tests.
    ///   - defaults: Where the banner's dismissal is kept; tests pass their own suite.
    public init(model: TrainingModel, scheduler: any PlannedWorkoutScheduling, defaults: UserDefaults = .standard) {
        self.model = model
        self.scheduler = scheduler
        self.defaults = defaults
        self.isBannerDismissed = defaults.bool(forKey: Self.bannerDismissedKey)
    }

    /// Hides the permission banner until permission is granted and later declined again.
    public func dismissPermissionDeniedBanner() {
        isBannerDismissed = true
        defaults.set(true, forKey: Self.bannerDismissedKey)
    }

    /// The live sync, or `nil` where WorkoutKit isn't available.
    public static func live(model: TrainingModel) -> WatchScheduleSync? {
        PlannedWorkoutSchedulers.live.map { WatchScheduleSync(model: model, scheduler: $0) }
    }

    /// Starts ``sync(asOf:)`` without waiting for it, for callers that aren't `async`.
    ///
    /// - Parameter now: The current time; callers with an injected `today` pass it through.
    /// - Returns: The started task, for a caller (or test) that wants to wait for it. A request made
    ///   while a run is in progress finishes at once; the running pass does the extra round.
    @discardableResult
    public func requestSync(asOf now: Date = .now) -> Task<Void, Never> {
        Task { await sync(asOf: now) }
    }

    /// Puts the next 7 days of planned workouts on the Watch and removes entries that no longer
    /// belong there (see ``WatchSchedulePlanner``).
    ///
    /// Asks for permission to schedule workouts the first time there's a plan to send, so a new
    /// athlete isn't asked before they've planned anything. Does nothing when permission is declined
    /// or not yet asked for, the device can't schedule workouts, or the stores can't be read. A plan
    /// that fails to schedule is skipped and tried again on the next run.
    /// Each run that reads the stores also records whether permission is denied, for
    /// ``showsPermissionDeniedBanner``.
    ///
    /// A call made while a run is in progress returns at once and makes that run go round again
    /// when it finishes: the running pass may have read the store before the change that prompted
    /// the call, and could otherwise remove or overwrite the entry that change just made.
    ///
    /// - Parameter now: The current time, injected so tests can pin the window.
    public func sync(asOf now: Date = .now) async {
        guard !isSyncing else {
            needsRerun = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            needsRerun = false
            await syncOnce(asOf: now)
        } while needsRerun
    }

    private func syncOnce(asOf now: Date) async {
        let stores = model.stores
        guard let plans = try? await stores.planStore.plans(in: Date.distantPast...Date.distantFuture),
              let workouts = try? await stores.workoutStore.workouts()
        else { return }

        let workoutsByID = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.athlete.timeZone
        let scheduler = scheduler
        let result = WatchSchedulePlanner.plan(
            plans, asOf: now, calendar: calendar, cap: scheduler.maxScheduledCount
        ) { plan in
            guard let workout = workoutsByID[plan.workoutID] else { return false }
            return (try? scheduler.validate(workout)) != nil
        }

        let authorization: WatchSchedulingAuthorization
        if result.toSchedule.isEmpty {
            authorization = await scheduler.authorizationStatus()
        } else {
            authorization = await scheduler.requestAuthorizationIfNeeded()
        }
        record(authorization)
        guard authorization.isAuthorized else { return }

        // Removals first, so the slots they free are there for the new entries.
        await scheduler.unscheduleAll(except: result.keep)
        for plan in result.toSchedule {
            guard let workout = workoutsByID[plan.workoutID] else { continue }
            try? await scheduler.schedule(plan, workout: workout, calendar: calendar)
        }
    }

    /// Updates ``isPermissionDenied``, and forgets a dismissed banner once permission is granted.
    private func record(_ authorization: WatchSchedulingAuthorization) {
        isPermissionDenied = authorization == .denied
        if authorization == .authorized, isBannerDismissed {
            isBannerDismissed = false
            defaults.removeObject(forKey: Self.bannerDismissedKey)
        }
    }
}
