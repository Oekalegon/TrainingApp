import Foundation
import TrainingCore
import TrainingWatchKit

/// Test data for the simulator, where no phone sends any (WATCH-102, WATCH-103). Launch arguments
/// ask for it; none of it is cached, so it doesn't hide the "nothing received yet" screens on later
/// launches. While an argument asks for it, what a paired phone sends is ignored, since a paired
/// iPhone simulator sends an empty plan that would hide the test workout ("No run planned today").
///
/// - `-fakeZones`: zones with resting 55 and maximum 190.
/// - `-fakePlan`: a 4 × 3 min interval workout planned for today, sent just now.
/// - `-fakeShortPlan`: a workout of steps a few seconds long, for testing the steps.
/// - `-fakeIntervalPlan`: 6 × 20 s intervals, which `Tools/TestTracks/short-intervals.gpx` follows.
/// - `-fakeStalePlan`: sent 3 days ago, whichever workout is asked for (the `-fakePlan` one by default).
///
/// On a real watch the arguments do nothing.
enum SimulatorTestData {
    #if targetEnvironment(simulator)
    private static let arguments = Set(CommandLine.arguments)
    static var replacesZones: Bool { arguments.contains("-fakeZones") }
    static var replacesPlan: Bool {
        !arguments.isDisjoint(with: ["-fakePlan", "-fakeShortPlan", "-fakeIntervalPlan", "-fakeStalePlan"])
    }

    /// Puts the requested test zones and plan in the stores, replacing what they hold.
    @MainActor
    static func apply(zoneStore: WatchZoneStore, planStore: WatchPlanStore) {
        if replacesZones {
            zoneStore.update(WatchZones(settings: .init(
                effectiveDate: .distantPast, restingHeartRateBPM: 55, maxHeartRateBPM: 190)), persist: false)
        }
        guard replacesPlan else { return }
        let name: String
        let blocks: [WorkoutBlock]
        if arguments.contains("-fakeIntervalPlan") {
            (name, blocks) = ("6 × 20 s intervals", TestWorkouts.intervals)
        } else if arguments.contains("-fakeShortPlan") {
            (name, blocks) = ("Short test", TestWorkouts.short)
        } else {
            (name, blocks) = ("4 × 3 min intervals", TestWorkouts.fourByThreeMinutes)
        }
        let sentAt = arguments.contains("-fakeStalePlan") ? Date.now.addingTimeInterval(-3 * 86400) : Date.now
        planStore.update(
            WatchPlan(workouts: [WatchPlannedWorkout(id: UUID(), date: .now, name: name, blocks: blocks)], sentAt: sentAt),
            persist: false)
    }
    #else
    static var replacesZones: Bool { false }
    static var replacesPlan: Bool { false }
    #endif
}
