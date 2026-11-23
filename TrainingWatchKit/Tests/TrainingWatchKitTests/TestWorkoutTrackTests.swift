import Foundation
import Testing
import TrainingCore
@testable import TrainingWatchKit

/// The simulator's interval workout and the synthetic GPX track made to follow it must stay in
/// step, or a test run stops lining up (WATCH-104).
@Suite("Interval test workout and its GPX track (WATCH-104)")
struct TestWorkoutTrackTests {
    private var track: [GPXTrackPoint] {
        get throws {
            // This file is TrainingWatchKit/Tests/TrainingWatchKitTests/…; the repo root is four up.
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            let text = try String(contentsOf: root.appending(path: "Tools/TestTracks/short-intervals.gpx"), encoding: .utf8)
            return GPXTrack.points(in: text)
        }
    }

    /// The planned steps with their start second, from the step engine.
    private var steps: [(step: PlannedStep, start: Double)] {
        var start = 0.0
        return WorkoutStepEngine(blocks: TestWorkouts.intervals).steps.map { step in
            defer { if case .time(let seconds) = step.step.goal { start += seconds } }
            return (step, start)
        }
    }

    @Test("the track lasts as long as the workout")
    func duration() throws {
        let points = try track
        let planned = steps.reduce(0.0) { total, entry in
            if case .time(let seconds) = entry.step.step.goal { total + seconds } else { total }
        }
        #expect(planned == 360)
        #expect(points.count == 361)
        #expect(points.last!.time.timeIntervalSince(points.first!.time) == planned)
    }

    /// Where the heart rate is late in each step against the step's own zone. Steps are numbered
    /// from 0: the warm-up, then a hard and an easy step per repetition, then the cool-down. The
    /// excursions are deliberate, to test the alerts; keep in step with `Tools/make-interval-gpx.py`.
    private static let expected: [Int: String] = [
        3: "far above", // rep 2 hard: 190 against zone 4
        6: "below",     // rep 3 easy: 128 against zone 2
        7: "far below", // rep 4 hard: 140 against zone 4
        10: "above",    // rep 5 easy: 156 against zone 2
        11: "below"     // rep 6 hard: 158 against zone 4
    ]

    @Test("late in each step the heart rate is in the step's zone, except in the steps made to go out of it")
    func followsSteps() throws {
        let points = try track
        let bands = try #require(ZoneBands(zones: WatchZones(settings: .init(
            effectiveDate: .distantPast, restingHeartRateBPM: 55, maxHeartRateBPM: 190))))
        let origin = points[0].time
        for (step, start) in steps {
            guard case .time(let seconds) = step.step.goal else { continue }
            let target = try #require(StepHeartRateTarget(step: step.step, bands: bands))
            // The last 2 seconds of the step, by which the heart rate has nearly caught up.
            let late = points.last { $0.time.timeIntervalSince(origin) <= start + seconds }
            let bpm = try #require(late?.heartRate)
            let outcome: String
            switch target.position(forHeartRate: bpm) {
            case .inside: outcome = "inside"
            case .below(let by): outcome = by > 10 ? "far below" : "below"
            case .above(let by): outcome = by > 10 ? "far above" : "above"
            }
            #expect(outcome == Self.expected[step.index] ?? "inside", "step \(step.index) ended at \(bpm) bpm")
        }
    }

    @Test("the first seconds of a hard step are still below zone 4, as with a real heart rate")
    func heartRateLags() throws {
        let points = try track
        let zones = WatchZones(settings: .init(effectiveDate: .distantPast, restingHeartRateBPM: 55, maxHeartRateBPM: 190))
        // Second 61 is the first of the first hard step.
        let zone = zones.zone(forHeartRate: try #require(points[61].heartRate))
        #expect((zone ?? 0) < 4)
    }
}
