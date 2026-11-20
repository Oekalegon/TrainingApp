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

    public init(id: UUID, date: Date, name: String, blocks: [WorkoutBlock]) {
        self.id = id
        self.date = date
        self.name = name
        self.blocks = blocks
    }
}
