import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@Suite("ActivityAfterPlan (MVP2-146)")
struct ActivityAfterPlanTests {
    private let start = Date(timeIntervalSince1970: 1_699_920_000)

    private func step(_ block: Int, from second: Double, seconds: Double, distance: Double?) -> ActivityStep {
        ActivityStep(
            block: block, repetition: 0, step: 0, start: start.addingTimeInterval(second),
            end: start.addingTimeInterval(second + seconds), distanceMeters: distance
        )
    }

    /// The long run: 5 min, 65:22 and 5 min, with 3:52 after the cool-down, 12 km in all.
    private func longRun(totalDistance: Double? = 12_000, distances: [Double?] = [801.65, 9993.82, 333.3]) -> Activity {
        let steps = [
            step(0, from: 0, seconds: 300, distance: distances[0]),
            step(1, from: 300, seconds: 3922, distance: distances[1]),
            step(2, from: 4222, seconds: 299, distance: distances[2]),
        ]
        var heartRate: [HeartRateSample] = []
        for second in stride(from: 0, to: 4753, by: 5) {
            // 140 during the plan; rising from 100 after it.
            let bpm: Double = second < 4521 ? 140 : 100 + Double(second - 4521) / 10
            heartRate.append(HeartRateSample(time: start.addingTimeInterval(Double(second)), bpm: bpm))
        }
        return Activity(
            source: .manual, sport: .running, start: start, duration: 4753, distanceMeters: totalDistance,
            heartRate: heartRate, steps: steps
        )
    }

    @Test("the time after the last step: when it starts, how long, the distance left over and the heart rate in it")
    func afterTheLongRun() throws {
        let after = try #require(ActivityAfterPlan.make(for: longRun()))

        #expect(after.start == 4521)
        #expect(after.end == 4753)
        #expect(after.duration == 232)  // 3:52
        #expect(after.id == 3)
        let distance = try #require(after.distanceMeters)
        #expect(abs(distance - (12_000 - 801.65 - 9993.82 - 333.3)) < 0.01)
        let heartRate = try #require(after.averageHeartRateBPM)
        #expect(heartRate > 100 && heartRate < 125)  // only the readings after the plan, not the 140s
    }

    @Test("with no recorded steps, or a last step within half a minute of the end, there is no such stretch")
    func nothingAfter() {
        let none = Activity(source: .manual, sport: .running, start: start, duration: 600)
        #expect(ActivityAfterPlan.make(for: none) == nil)

        let closeToEnd = Activity(
            source: .manual, sport: .running, start: start, duration: 320,
            steps: [step(0, from: 0, seconds: 300, distance: 800)]
        )
        #expect(ActivityAfterPlan.make(for: closeToEnd) == nil)
    }

    @Test("the distance left over is left out when any step recorded none, the activity has none, or nothing is left")
    func distanceLeftOut() throws {
        #expect(try #require(ActivityAfterPlan.make(for: longRun(distances: [801.65, nil, 333.3]))).distanceMeters == nil)
        #expect(try #require(ActivityAfterPlan.make(for: longRun(totalDistance: nil))).distanceMeters == nil)
        // The activity's own distance is less than the steps', e.g. recorded differently.
        #expect(try #require(ActivityAfterPlan.make(for: longRun(totalDistance: 11_000))).distanceMeters == nil)
    }

    @Test("the heart rate is left out when no reading falls after the plan")
    func noHeartRateAfter() throws {
        var activity = longRun()
        activity.heartRate = activity.heartRate.filter { $0.time.timeIntervalSince(start) < 4521 }

        #expect(try #require(ActivityAfterPlan.make(for: activity)).averageHeartRateBPM == nil)
    }

    @Test("its card gets the id of its span and the four figures, with a pace from the distance over the time")
    func card() throws {
        let after = try #require(ActivityAfterPlan.make(for: longRun()))

        let card = WorkoutAfterPlanCard.make(after, distanceSystem: .metric)

        #expect(card.recordedStepID == after.id)
        #expect(card.actual.duration == "3:52")
        #expect(card.actual.distance == "871 m")
        #expect(card.actual.averageHeartRate != nil)
        #expect(card.actual.averagePace == "4:26 /km")  // 232 s over 871 m
    }
}
