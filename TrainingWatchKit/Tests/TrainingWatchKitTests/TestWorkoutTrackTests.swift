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

    @Test("the pace and heart rate follow each step: fast and in zone 4 late in a hard step, easy and in zone 2 late in a recovery")
    func followsSteps() throws {
        let points = try track
        let zones = WatchZones(settings: .init(effectiveDate: .distantPast, restingHeartRateBPM: 55, maxHeartRateBPM: 190))
        let origin = points[0].time
        for (step, start) in steps {
            guard case .time(let seconds) = step.step.goal else { continue }
            // The last 5 seconds of the step, by which the heart rate has caught up.
            let late = points.filter {
                let t = $0.time.timeIntervalSince(origin)
                return t > start + seconds - 5 && t <= start + seconds
            }
            let zone = try #require(late.last?.heartRate).map { zones.zone(forHeartRate: $0) }
            switch step.step.kind {
            case .work: #expect(zone == 4, "hard step \(step.index)")
            case .recovery: #expect(zone == 2, "recovery \(step.index)")
            case .warmup, .cooldown: #expect(zone == 1, "step \(step.index)")
            }
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
