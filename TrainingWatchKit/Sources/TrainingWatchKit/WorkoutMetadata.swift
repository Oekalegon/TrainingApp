import Foundation
import TrainingCore

/// What the watch writes into a saved workout so TrainingApp can recognise it and show its steps
/// (WATCH-104). HealthKit takes custom metadata keys as long as they don't start with "HK".
public enum WorkoutMetadata {
    /// On the `HKWorkout`: the planned activity's ID, so a run is matched to its plan exactly.
    public static let plannedActivityID = "TrainingAppPlannedActivityID"
    /// On the `HKWorkout`: the planned workout's name.
    public static let workoutName = "TrainingAppWorkoutName"

    /// On the `HKWorkout`: the battery level (0 to 1) when the run started, so the phone can work out the
    /// athlete's own drain per hour (WATCH-119).
    public static let batteryStart = "TrainingAppBatteryStart"
    /// On the `HKWorkout`: the battery level (0 to 1) when the run ended.
    public static let batteryEnd = "TrainingAppBatteryEnd"

    /// On a step's segment event: the step's place in the workout, from 0.
    public static let stepIndex = "TrainingAppStepIndex"
    /// On a step's segment event: "warmup", "work", "recovery" or "cooldown".
    public static let stepKind = "TrainingAppStepKind"
    /// On a step's segment event: which repetition of its block the step is, from 1.
    public static let stepRepetition = "TrainingAppStepRepetition"
    /// On a step's segment event: how many times its block repeats.
    public static let stepRepetitions = "TrainingAppStepRepetitions"
    /// On a step's segment event: "time", "distance" or "open".
    public static let stepGoalType = "TrainingAppStepGoalType"
    /// On a step's segment event: the goal in seconds or metres; absent for an open step.
    public static let stepGoalValue = "TrainingAppStepGoalValue"
    /// On a step's segment event: how the step ended, see ``StepEnd``.
    public static let stepEnd = "TrainingAppStepEnd"

    /// How a step came to an end, as written to its segment event.
    public enum StepEnd: String, Sendable {
        /// Its time or distance was reached.
        case goalReached = "goal"
        /// The lap button ended it early.
        case lap
        /// The run ended while the step was still going.
        case workoutEnded

        /// The end that an engine's transition reason means.
        public init(_ reason: WorkoutStepEngine.Reason) {
            switch reason {
            case .goalReached: self = .goalReached
            case .lap: self = .lap
            }
        }
    }

    /// The metadata for a workout started from a plan.
    ///
    /// - Parameters:
    ///   - plannedActivityID: The planned activity's ID.
    ///   - name: The workout's name.
    public static func workout(plannedActivityID: UUID, name: String) -> [String: Any] {
        [Self.plannedActivityID: plannedActivityID.uuidString, workoutName: name]
    }

    /// The metadata for the battery over a run, or `nil` when there are too few readings to say anything.
    ///
    /// - Parameter readings: The battery readings of the run, oldest first.
    public static func battery(readings: [BatteryForecast.Reading]) -> [String: Any]? {
        guard let first = readings.first, let last = readings.last, last.time > first.time else { return nil }
        return [batteryStart: first.level, batteryEnd: last.level]
    }

    /// The metadata for a step's segment event.
    ///
    /// - Parameters:
    ///   - step: The step that ended.
    ///   - end: How it ended.
    public static func segment(for step: PlannedStep, end: StepEnd) -> [String: Any] {
        var metadata: [String: Any] = [
            stepIndex: step.index,
            stepKind: kindName(step.step.kind),
            stepRepetition: step.repetition,
            stepRepetitions: step.repetitions,
            stepEnd: end.rawValue
        ]
        switch step.step.goal {
        case .time(let seconds):
            metadata[stepGoalType] = "time"
            metadata[stepGoalValue] = seconds
        case .distance(let metres):
            metadata[stepGoalType] = "distance"
            metadata[stepGoalValue] = metres
        case .open:
            metadata[stepGoalType] = "open"
        }
        return metadata
    }

    private static func kindName(_ kind: StepKind) -> String {
        switch kind {
        case .warmup: "warmup"
        case .work: "work"
        case .recovery: "recovery"
        case .cooldown: "cooldown"
        }
    }
}
