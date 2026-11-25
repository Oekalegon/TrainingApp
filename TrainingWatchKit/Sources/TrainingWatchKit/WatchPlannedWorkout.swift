import Foundation
import TrainingCore

/// One planned workout as the watch needs it (WATCH-103): which plan entry it is, the day, and the
/// steps. The steps are TrainingKit's own `WorkoutBlock`s, so the watch reads step goals and
/// targets exactly as the phone does and nothing is translated on the way. Nothing else of the
/// phone's workout travels (not its library or template IDs, parameters or purpose), which keeps
/// the payload to what the watch uses.
public struct WatchPlannedWorkout: Identifiable, Sendable, Codable, Hashable {
    /// The planned activity's ID. A run recorded for it is later matched to the plan by this ID.
    public let id: UUID
    /// The day and time the workout is planned for.
    public var date: Date
    /// The workout's name.
    public var name: String
    /// The workout's steps, in blocks that repeat.
    public var blocks: [WorkoutBlock]
    /// How long the phone expects the whole workout to take, in seconds (the forecast from the athlete's
    /// paces that the planned cards show), sent only for a workout with an open step: the battery
    /// forecast uses it for the part that has no end of its own. `nil` otherwise (WATCH-119).
    public var typicalDuration: TimeInterval?
    /// The athlete's own battery drain per hour in earlier runs, as a share of the full charge, when the
    /// phone knows it (from the battery levels the watch wrote into those workouts): the forecast starts
    /// from it instead of a typical rate when the watch has no runs of its own to go by (WATCH-119).
    public var drainPerHour: Double?

    public init(
        id: UUID, date: Date, name: String, blocks: [WorkoutBlock],
        typicalDuration: TimeInterval? = nil, drainPerHour: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.name = name
        self.blocks = blocks
        self.typicalDuration = typicalDuration
        self.drainPerHour = drainPerHour
    }
}
