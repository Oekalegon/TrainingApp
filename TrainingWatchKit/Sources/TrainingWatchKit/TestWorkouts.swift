import Foundation
import TrainingCore

/// Workouts the watch simulator can be given for testing, where no phone sends a plan. Here, away
/// from the simulator-only code that hands them out, so a test can check them against the GPX
/// tracks made to follow them.
public enum TestWorkouts {
    /// 60 s warm-up, 6 × (20 s zone 4, 20 s zone 2), 60 s cool-down: 6 minutes.
    /// `Tools/TestTracks/short-intervals.gpx` follows it step for step.
    public static let intervals: [WorkoutBlock] = [
        WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(60), target: .heartRateZone(1))]),
        WorkoutBlock(steps: [
            WorkoutStep(kind: .work, goal: .time(20), target: .heartRateZone(4)),
            WorkoutStep(kind: .recovery, goal: .time(20), target: .heartRateZone(2))
        ], repetitions: 6),
        WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(60), target: .heartRateZone(1))])
    ]

    /// 60 s warm-up, 4 × (90 s zone 4, 90 s zone 2), 60 s cool-down: 14 minutes, for the zone alerts.
    /// Steps are long enough for an alert to fire (the first comes 2 s into a step).
    /// `Tools/TestTracks/alert-test.gpx` follows it, and goes out of the zones on purpose.
    public static let alertTest: [WorkoutBlock] = [
        WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(60), target: .heartRateZone(1))]),
        WorkoutBlock(steps: [
            WorkoutStep(kind: .work, goal: .time(90), target: .heartRateZone(4)),
            WorkoutStep(kind: .recovery, goal: .time(90), target: .heartRateZone(2))
        ], repetitions: 4),
        WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(60), target: .heartRateZone(1))])
    ]

    /// Steps a few seconds long (and a 15 m cool-down), to go through every kind of step quickly.
    public static let short: [WorkoutBlock] = [
        WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(8), target: .heartRateZone(1))]),
        WorkoutBlock(steps: [
            WorkoutStep(kind: .work, goal: .time(6), target: .heartRateZone(4)),
            WorkoutStep(kind: .recovery, goal: .time(4), target: .heartRateZone(2))
        ], repetitions: 2),
        WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .distance(15), target: .heartRateZone(1))])
    ]

    /// 10 min warm-up, 4 × (3 min zone 4.0-4.5, 2 min zone 2), 1 km cool-down.
    public static let fourByThreeMinutes: [WorkoutBlock] = [
        WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(600), target: .heartRateZone(1))]),
        WorkoutBlock(steps: [
            WorkoutStep(kind: .work, goal: .time(180), target: .heartRateZoneRange(4.0...4.5)),
            WorkoutStep(kind: .recovery, goal: .time(120), target: .heartRateZone(2))
        ], repetitions: 4),
        WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .distance(1000), target: .heartRateZone(1))])
    ]
}
