import Foundation
import TrainingCore

/// Decides which plans belong on the Watch (MVP2-55): the unlinked plans of the next 7 days, plus
/// recently completed ones, within WorkoutKit's cap on scheduled entries.
///
/// Pure, so the window and cap rules are tested without WorkoutKit; ``WatchScheduleSync`` applies
/// the result. The Watch's Workout app lists scheduled workouts 7 days back and 7 days ahead, so:
///
/// - **To schedule:** plans dated today through 6 days from now (``isInWindow(_:asOf:calendar:)``)
///   that aren't linked to an activity yet and whose workout can go on the Watch, soonest first.
/// - **To keep:** those, plus plans of the last 7 days (or later today) that are linked to an
///   activity, so the Watch can keep showing them as done — most recent first, while slots remain.
/// - Everything else is removed: missed workouts, plans beyond the window, entries whose plan was
///   deleted, and entries scheduled before MVP2-55 under a workout's id instead of a plan's.
public enum WatchSchedulePlanner {
    /// How many days the Watch shows ahead, today included.
    public static let windowDays = 7

    /// What the Watch should hold.
    public struct Result: Equatable, Sendable {
        /// Plans to schedule, soonest first. Scheduling one that's already there is a no-op.
        public var toSchedule: [PlannedActivity]
        /// The ids of every plan whose entry may stay: ``toSchedule``'s, plus recently completed ones.
        public var keep: Set<UUID>
    }

    /// Whether `date` falls between the start of today and the end of the 7th day, today included,
    /// in `calendar`'s time zone.
    public static func isInWindow(_ date: Date, asOf now: Date, calendar: Calendar) -> Bool {
        window(asOf: now, calendar: calendar).contains(date)
    }

    /// Today through 6 days from now, as a half-open range of instants.
    static func window(asOf now: Date, calendar: Calendar) -> Range<Date> {
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: windowDays, to: today) ?? today
        return today..<end
    }

    /// Decides what the Watch should hold.
    ///
    /// - Parameters:
    ///   - plans: Every plan in the store, not only a loaded range.
    ///   - now: The current time.
    ///   - calendar: The athlete's calendar; plan dates are days in their time zone.
    ///   - cap: The most entries the app may hold (`WorkoutScheduler.maxAllowedScheduledWorkoutCount`).
    ///   - canSchedule: Whether a plan's workout exists and can go on the Watch.
    public static func plan(
        _ plans: [PlannedActivity],
        asOf now: Date,
        calendar: Calendar,
        cap: Int,
        canSchedule: (PlannedActivity) -> Bool
    ) -> Result {
        let window = window(asOf: now, calendar: calendar)
        let lookbackStart = calendar.date(byAdding: .day, value: -windowDays, to: window.lowerBound) ?? window.lowerBound
        let upcoming = plans
            .filter { window.contains($0.date) && $0.completedActivityID == nil && canSchedule($0) }
            .sorted(by: soonestFirst)
            .prefix(max(0, cap))
        let completed = plans
            .filter { $0.completedActivityID != nil && (lookbackStart..<window.upperBound).contains($0.date) }
            .sorted(by: soonestFirst)
            .reversed()
            .prefix(max(0, cap - upcoming.count))
        return Result(
            toSchedule: Array(upcoming),
            keep: Set(upcoming.map(\.id)).union(completed.map(\.id))
        )
    }

    /// Orders by date, then by id, so plans on the same instant always come out in the same order.
    private static func soonestFirst(_ lhs: PlannedActivity, _ rhs: PlannedActivity) -> Bool {
        lhs.date != rhs.date ? lhs.date < rhs.date : lhs.id.uuidString < rhs.id.uuidString
    }
}
