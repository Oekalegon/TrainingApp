import Foundation

/// Reads what HealthKit recorded for recent workouts, as text (MVP2-146 spike): which workouts were
/// started from a plan, and whether the Watch recorded each step as an event or an activity. A
/// developer tool, shown from the Athlete tab's Developer screen, so the answer comes from a real
/// workout on the athlete's own device instead of a guess.
///
/// A seam, like ``ActivityRefreshing``: the screen is previewed and tested without HealthKit.
@MainActor
public protocol WorkoutInspecting {
    /// A report on the `limit` most recent workouts, newest first.
    ///
    /// - Throws: Whatever the HealthKit query throws, e.g. when access wasn't granted.
    func inspectRecentWorkouts(limit: Int) async throws -> String
}

/// One workout as the spike's report shows it: plain values, so the formatting is tested without
/// HealthKit.
struct InspectedWorkout: Equatable {
    /// A marker inside a workout: a lap, segment, pause, marker...
    struct Event: Equatable {
        let type: String
        let start: Date
        let end: Date
        let metadata: [String: String]
    }

    /// A sub-activity of a workout, e.g. one leg of a multisport workout or one interval.
    struct Activity: Equatable {
        let activityType: String
        let start: Date
        let end: Date?
        let events: [Event]
        let metadata: [String: String]
        /// What HealthKit summarised for this sub-activity, by quantity type, e.g. distance or heart
        /// rate: empty when it recorded none, or when read access to the type wasn't granted.
        let statistics: [String: String]
    }

    let id: UUID
    let activityType: String
    let start: Date
    let end: Date
    /// The id of the plan the workout was started from, if it was started from one.
    let planID: UUID?
    /// What the plan is, e.g. "custom workout 'Short interval run', 5 blocks".
    let planSummary: String?
    let events: [Event]
    let activities: [Activity]
    let metadata: [String: String]
}

/// The text of a spike report.
enum WorkoutInspectionReport {
    /// Formats `workouts` as plain text, one section per workout.
    ///
    /// Every time is written to the second, in ISO 8601 and UTC, so it can be compared with the
    /// activity's own samples. Nothing is left out because it looks empty: "no events" is the answer
    /// the spike is looking for.
    static func format(_ workouts: [InspectedWorkout], generatedAt: Date) -> String {
        var lines = ["Workout inspection, \(timestamp(generatedAt)), \(workouts.count) workouts, newest first", ""]
        for workout in workouts {
            lines.append("== \(workout.activityType)  \(timestamp(workout.start)) to \(timestamp(workout.end))")
            lines.append("   id \(workout.id.uuidString)")
            lines.append("   started from plan: \(workout.planID.map(\.uuidString) ?? "no")")
            if let summary = workout.planSummary { lines.append("   plan: \(summary)") }
            lines.append("   events: \(workout.events.count)")
            lines += workout.events.map { "     " + describe($0) }
            lines.append("   activities: \(workout.activities.count)")
            for activity in workout.activities {
                let end = activity.end.map(timestamp) ?? "open"
                lines.append("     - \(activity.activityType)  \(timestamp(activity.start)) to \(end)")
                if !activity.metadata.isEmpty { lines.append("       metadata: \(describe(activity.metadata))") }
                lines.append("       statistics: \(activity.statistics.isEmpty ? "none" : describe(activity.statistics))")
                lines.append("       events: \(activity.events.count)")
                lines += activity.events.map { "         " + describe($0) }
            }
            if !workout.metadata.isEmpty { lines.append("   metadata: \(describe(workout.metadata))") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func describe(_ event: InspectedWorkout.Event) -> String {
        var text = "\(event.type)  \(timestamp(event.start))"
        if event.end != event.start { text += " to \(timestamp(event.end))" }
        if !event.metadata.isEmpty { text += "  \(describe(event.metadata))" }
        return text
    }

    private static func describe(_ metadata: [String: String]) -> String {
        metadata.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
    }

    private static func timestamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .gmt))
    }
}
