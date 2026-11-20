import Foundation

/// The athlete's upcoming planned workouts on the watch, so a run can start with the phone out of
/// reach (WATCH-103). The phone sends the next few days; the watch keeps them until newer ones
/// arrive. An empty plan is a real value: it says nothing is planned and clears the old one.
public struct WatchPlan: Sendable, Codable, Hashable {
    /// The workouts, earliest first.
    public var workouts: [WatchPlannedWorkout]
    /// When the phone sent this plan, so the watch can say how old it is: a plan the phone hasn't
    /// refreshed for days may not be today's, and "no run planned" would then be a guess.
    public var sentAt: Date

    public init(workouts: [WatchPlannedWorkout], sentAt: Date) {
        self.workouts = workouts.sorted { $0.date != $1.date ? $0.date < $1.date : $0.id.uuidString < $1.id.uuidString }
        self.sentAt = sentAt
    }

    /// The workouts planned for the calendar day containing `day`.
    ///
    /// - Parameters:
    ///   - day: Any moment on the day.
    ///   - calendar: The calendar that decides where a day starts and ends; the watch's own, so
    ///     "today" is where the athlete is.
    public func workouts(on day: Date, calendar: Calendar = .current) -> [WatchPlannedWorkout] {
        workouts.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }
}
