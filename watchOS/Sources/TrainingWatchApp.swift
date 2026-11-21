import SwiftUI
import TrainingCore
import TrainingWatchKit

@main
struct TrainingWatchApp: App {
    @State private var recorder = RunRecorder()
    @State private var zoneStore = WatchZoneStore()
    @State private var planStore = WatchPlanStore()
    /// Receives the athlete's zones and plan from the iPhone (WATCH-102, WATCH-103).
    @State private var syncChannel = WatchSyncChannel.live()

    var body: some Scene {
        WindowGroup {
            RunView(recorder: recorder, zoneStore: zoneStore, planStore: planStore)
                .task {
                    syncChannel?.activate { context in
                        // A part the phone hasn't sent yet is `nil`: keep what the watch has.
                        // In the simulator, test data wins over anything a paired phone sends.
                        if let zones = context.zones, !fakesZones { zoneStore.update(zones) }
                        if let plan = context.plan, !fakesPlan { planStore.update(plan) }
                    }
                    #if targetEnvironment(simulator)
                    addSimulatorTestData()
                    #endif
                }
        }
    }

    #if targetEnvironment(simulator)
    private var fakesZones: Bool { CommandLine.arguments.contains("-fakeZones") }
    private var fakesPlan: Bool {
        ["-fakePlan", "-fakeShortPlan", "-fakeIntervalPlan", "-fakeStalePlan"].contains(where: CommandLine.arguments.contains)
    }
    #else
    private var fakesZones: Bool { false }
    private var fakesPlan: Bool { false }
    #endif

    #if targetEnvironment(simulator)
    /// Test data for the simulator. None of it is cached, so it doesn't hide the "nothing
    /// received yet" screens on later launches, and while an argument asks for it, what a paired
    /// phone sends is ignored.
    ///
    /// - `-fakeZones`: zones with resting 55 and maximum 190.
    /// - `-fakePlan`: an interval workout planned for today, sent just now.
    /// - `-fakeShortPlan`: a workout of steps a few seconds long, for testing the steps.
    /// - `-fakeIntervalPlan`: 60 s warm-up, 6 × (20 s zone 4, 20 s zone 2), 60 s cool-down, which
    ///   `Tools/TestTracks/short-intervals.gpx` follows step for step.
    /// - `-fakeStalePlan`: the same, sent 3 days ago.
    private func addSimulatorTestData() {
        // Replaces whatever is cached or was already received: a paired iPhone simulator sends an
        // empty plan, which would otherwise hide the test workout ("No run planned today").
        if fakesZones {
            zoneStore.update(WatchZones(settings: .init(
                effectiveDate: .distantPast, restingHeartRateBPM: 55, maxHeartRateBPM: 190)), persist: false)
        }
        let short = CommandLine.arguments.contains("-fakeShortPlan")
        let intervals = CommandLine.arguments.contains("-fakeIntervalPlan")
        let fresh = CommandLine.arguments.contains("-fakePlan") || short || intervals
        let stale = CommandLine.arguments.contains("-fakeStalePlan")
        if fresh || stale {
            let blocks = intervals ? [
                WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(60), target: .heartRateZone(1))]),
                WorkoutBlock(steps: [
                    WorkoutStep(kind: .work, goal: .time(20), target: .heartRateZone(4)),
                    WorkoutStep(kind: .recovery, goal: .time(20), target: .heartRateZone(2))
                ], repetitions: 6),
                WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(60), target: .heartRateZone(1))])
            ] : short ? [
                // Seconds, not minutes, so a test run goes through every kind of step quickly.
                WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(8), target: .heartRateZone(1))]),
                WorkoutBlock(steps: [
                    WorkoutStep(kind: .work, goal: .time(6), target: .heartRateZone(4)),
                    WorkoutStep(kind: .recovery, goal: .time(4), target: .heartRateZone(2))
                ], repetitions: 2),
                WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .distance(15), target: .heartRateZone(1))])
            ] : [
                WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(600), target: .heartRateZone(1))]),
                WorkoutBlock(steps: [
                    WorkoutStep(kind: .work, goal: .time(180), target: .heartRateZoneRange(4.0...4.5)),
                    WorkoutStep(kind: .recovery, goal: .time(120), target: .heartRateZone(2))
                ], repetitions: 4),
                WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .distance(1000), target: .heartRateZone(1))])
            ]
            let sentAt = stale ? Date.now.addingTimeInterval(-3 * 86400) : Date.now
            planStore.update(
                WatchPlan(
                    workouts: [WatchPlannedWorkout(id: UUID(), date: .now, name: intervals ? "6 × 20 s intervals" : short ? "Short test" : "4 × 3 min intervals", blocks: blocks)],
                    sentAt: sentAt),
                persist: false)
        }
    }
    #endif
}
