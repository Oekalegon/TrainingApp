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
/// see ``showsPermissionDeniedBanner``. The athlete can turn sending off on the Athlete tab
/// (MVP2-118, ``isEnabled``); each run then removes the app's entries instead of scheduling.
@Observable
@MainActor
public final class WatchScheduleSync {
    private static let bannerDismissedKey = "watchSync.permissionDeniedBannerDismissed"
    private static let enabledKey = "watchSync.enabled"

    private let model: TrainingModel
    private let scheduler: any PlannedWorkoutScheduling
    private let defaults: UserDefaults
    @ObservationIgnored private var isSyncing = false
    /// Set when a sync is requested while one runs; that run then goes round once more, so a plan
    /// saved after it read the store still ends up on the Watch.
    @ObservationIgnored private var needsRerun = false

    /// Whether the app may schedule workouts, as of the last sync or check: what the Athlete tab's
    /// Apple Watch section shows. `nil` until one has run.
    public private(set) var authorization: WatchSchedulingAuthorization?

    /// Whether the athlete declined permission to schedule workouts, as of the last sync or check.
    /// `false` until one has run, and when permission was never asked for or the device can't
    /// schedule workouts.
    public var isPermissionDenied: Bool {
        authorization == .denied
    }

    /// Whether planned workouts are sent to the Watch: the Athlete tab's "Send Planned Workouts to
    /// Apple Watch" switch (MVP2-118), on by default. Kept in `UserDefaults`, local to this device.
    /// While off, each run removes the app's entries from the Watch and schedules nothing, and the
    /// planned-workout sheets don't schedule either (``editingScheduler``). Change it with
    /// ``setEnabled(_:asOf:)``.
    public private(set) var isEnabled: Bool

    /// The scheduler the planned-workout sheets use to put a saved plan on the Watch right away:
    /// `nil` while sending is off, so a save neither checks the workout against the Watch nor
    /// schedules it.
    public var editingScheduler: (any PlannedWorkoutScheduling)? {
        isEnabled ? scheduler : nil
    }

    /// Whether the athlete dismissed the permission banner. Kept in `UserDefaults`, so the banner
    /// stays away across launches; cleared once permission is granted, so declining again later
    /// brings it back.
    private var isBannerDismissed: Bool

    /// Whether the week view shows the banner explaining that planned workouts won't reach the
    /// Watch, with a button to the Athlete tab's Apple Watch section (MVP2-117): sending is on,
    /// permission is denied and the athlete hasn't dismissed the banner. With sending turned off
    /// (MVP2-118), the athlete chose not to send, so there's nothing to warn about.
    public var showsPermissionDeniedBanner: Bool {
        isEnabled && isPermissionDenied && !isBannerDismissed
    }

    /// - Parameters:
    ///   - model: Supplies the stores and the athlete's time zone.
    ///   - scheduler: The Watch; `WorkoutKitBridge` in the app, a fake in tests.
    ///   - defaults: Where the banner's dismissal and ``isEnabled`` are kept; tests pass their own
    ///     suite.
    public init(model: TrainingModel, scheduler: any PlannedWorkoutScheduling, defaults: UserDefaults = .standard) {
        self.model = model
        self.scheduler = scheduler
        self.defaults = defaults
        self.isBannerDismissed = defaults.bool(forKey: Self.bannerDismissedKey)
        self.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Turns sending planned workouts to the Watch on or off (MVP2-118), from the Athlete tab's
    /// switch. ``isEnabled`` changes at once, so the switch follows the tap; the Watch catches up
    /// in the returned task.
    ///
    /// Turning it off runs a sync, which removes the app's entries from the Watch. Turning it on
    /// asks for permission if the athlete hasn't been asked yet, then syncs
    /// (``requestPermission(asOf:)``). A permission declined before stays declined: only the Watch
    /// app's Workout settings can change it.
    ///
    /// - Parameters:
    ///   - enabled: Whether to send planned workouts to the Watch.
    ///   - now: The current time, passed on to the sync.
    /// - Returns: The task updating the Watch, for a caller (or test) that wants to wait for it.
    @discardableResult
    public func setEnabled(_ enabled: Bool, asOf now: Date = .now) -> Task<Void, Never> {
        guard enabled != isEnabled else { return Task {} }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        return Task {
            if enabled {
                await requestPermission(asOf: now)
            } else {
                await sync(asOf: now)
            }
        }
    }

    /// Hides the permission banner until permission is granted and later declined again.
    public func dismissPermissionDeniedBanner() {
        isBannerDismissed = true
        defaults.set(true, forKey: Self.bannerDismissedKey)
    }

    /// Reads the current permission without asking, for the Athlete tab's Apple Watch section to
    /// show when it appears, before any sync has run.
    public func refreshAuthorization() async {
        record(await scheduler.authorizationStatus())
    }

    /// Asks for permission to schedule workouts, from the Athlete tab's Allow button or its switch
    /// being turned on (``setEnabled(_:asOf:)``), and syncs once it's granted.
    ///
    /// iOS asks only once: when permission was declined before, this returns at once with
    /// ``authorization`` still `.denied`, and only the Workout settings in the Watch app can turn
    /// it back on.
    ///
    /// - Parameter now: The current time, passed on to ``sync(asOf:)``.
    public func requestPermission(asOf now: Date = .now) async {
        let authorization = await scheduler.requestAuthorizationIfNeeded()
        record(authorization)
        if authorization.isAuthorized {
            await sync(asOf: now)
        }
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
    /// that fails to schedule is skipped and tried again on the next run. Each run that reads the
    /// stores also records whether permission is denied, for ``showsPermissionDeniedBanner``.
    ///
    /// With sending turned off (``isEnabled``, MVP2-118), it removes every entry the app put on the
    /// Watch instead, without asking for permission.
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
        guard isEnabled else {
            await removeAllEntries()
            return
        }
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

        // Sending was turned off while this run awaited the stores or permission: the run that
        // turn-off requested removes everything, so don't add entries first.
        guard isEnabled else { return }
        // Removals first, so the slots they free are there for the new entries.
        await scheduler.unscheduleAll(except: result.keep)
        for plan in result.toSchedule {
            guard isEnabled else { return }
            guard let workout = workoutsByID[plan.workoutID] else { continue }
            try? await scheduler.schedule(plan, workout: workout, calendar: calendar)
        }
    }

    /// With sending off (MVP2-118): removes every entry the app put on the Watch. Still records the
    /// permission, so the Athlete tab stays current, and never asks for it.
    private func removeAllEntries() async {
        let authorization = await scheduler.authorizationStatus()
        record(authorization)
        guard authorization.isAuthorized else { return }
        await scheduler.unscheduleAll(except: [])
    }

    /// Updates ``authorization``, and forgets a dismissed banner once permission is granted.
    private func record(_ authorization: WatchSchedulingAuthorization) {
        self.authorization = authorization
        if authorization == .authorized, isBannerDismissed {
            isBannerDismissed = false
            defaults.removeObject(forKey: Self.bannerDismissedKey)
        }
    }
}
