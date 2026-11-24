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
    /// How long earlier runs of the same workout template took, in seconds (the median), when there are
    /// some: the battery forecast uses it for the part of the workout that has no end of its own (an
    /// open step). `nil` when there are no earlier runs (WATCH-119).
    public var typicalDuration: TimeInterval?
    /// The athlete's own battery drain per hour in earlier runs, as a share of the full charge, when the
    /// phone knows it: the forecast starts from it instead of a typical rate (WATCH-119).
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
