import Foundation
import TrainingCore

/// One planned workout as the watch needs it (WATCH-103): which plan entry it is, the day, and the
/// workout with its steps. The workout is TrainingKit's own `StructuredWorkout`, so the watch reads
/// step goals and targets exactly as the phone does and nothing is translated on the way.
public struct WatchPlannedWorkout: Identifiable, Sendable, Codable, Hashable {
    /// The planned activity's ID. A run recorded for it is later matched to the plan by this ID.
    public let id: UUID
    /// The day and time the workout is planned for.
    public var date: Date
    /// The workout to do.
    public var workout: StructuredWorkout

    public init(id: UUID, date: Date, workout: StructuredWorkout) {
        self.id = id
        self.date = date
        self.workout = workout
    }
}

/// The athlete's upcoming planned workouts on the watch, so a run can start with the phone out of
/// reach (WATCH-103). The phone sends the next few days; the watch keeps them until newer ones
/// arrive. An empty plan is a real value: it says nothing is planned and clears the old one.
public struct WatchPlan: Sendable, Codable, Hashable {
    /// The workouts, earliest first.
    public var workouts: [WatchPlannedWorkout]

    public init(workouts: [WatchPlannedWorkout]) {
        self.workouts = workouts.sorted { $0.date != $1.date ? $0.date < $1.date : $0.id.uuidString < $1.id.uuidString }
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

/// Everything the phone sends to the watch in one go. A WatchConnectivity application context
/// replaces the one before it as a whole, so the zones and the plan travel together: sending them
/// separately would let each wipe out the other.
public struct WatchContext: Sendable, Codable, Hashable {
    /// The athlete's heart-rate zones; `nil` while the phone has none to send.
    public var zones: WatchZones?
    /// The upcoming planned workouts; `nil` while the phone hasn't sent any yet (an empty
    /// ``WatchPlan`` is "nothing planned", which is different).
    public var plan: WatchPlan?

    public init(zones: WatchZones? = nil, plan: WatchPlan? = nil) {
        self.zones = zones
        self.plan = plan
    }
}

extension WatchContext {
    /// The key the context travels under in a WatchConnectivity application context.
    static let contextKey = "watchContext.v1"

    /// The application context that carries this to the other device.
    public func applicationContext() throws -> [String: Any] {
        [Self.contextKey: try JSONEncoder().encode(self)]
    }

    /// The context in encoded form, or `nil` when it can't be decoded.
    public init?(data: Data) {
        guard let context = try? JSONDecoder().decode(WatchContext.self, from: data) else { return nil }
        self = context
    }

    /// The context in an application context, or `nil` when it holds none.
    public init?(applicationContext: [String: Any]) {
        guard let data = applicationContext[Self.contextKey] as? Data else { return nil }
        self.init(data: data)
    }
}
